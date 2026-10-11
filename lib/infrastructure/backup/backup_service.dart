import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../application/app_services.dart';
import '../../application/audit_writer.dart';
import '../../application/ledger_events.dart';
import '../../application/ledger_queries.dart';
import '../../domain/errors/domain_errors.dart';
import '../../domain/security/permissions.dart';
import '../database/exchange_database.dart';

const int kBackupFormatVersion = 1;
const String kBackupAppId = 'hadid_money_exchange';

final class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.app,
    required this.schemaVersion,
    required this.createdAt,
    required this.kind,
    required this.sha256,
    required this.sizeBytes,
    required this.fingerprint,
  });

  factory BackupManifest.fromJson(Map<String, Object?> j) => BackupManifest(
        formatVersion: j['format_version'] as int,
        app: j['app'] as String,
        schemaVersion: j['schema_version'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
        kind: j['kind'] as String,
        sha256: j['sha256'] as String,
        sizeBytes: j['size_bytes'] as int,
        fingerprint: (j['fingerprint'] as Map).cast<String, Object?>(),
      );

  final int formatVersion;
  final String app;
  final int schemaVersion;
  final DateTime createdAt;
  final String kind;
  final String sha256;
  final int sizeBytes;
  final Map<String, Object?> fingerprint;

  Map<String, Object?> toJson() => {
        'format_version': formatVersion,
        'app': app,
        'schema_version': schemaVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
        'kind': kind,
        'sha256': sha256,
        'size_bytes': sizeBytes,
        'fingerprint': fingerprint,
      };
}

final class BackupVerification {
  const BackupVerification({
    required this.path,
    required this.problems,
    this.manifest,
    this.schemaVersion,
    this.fingerprint,
  });

  final String path;
  final List<String> problems;
  final BackupManifest? manifest;
  final int? schemaVersion;
  final Map<String, Object?>? fingerprint;

  bool get isValid => problems.isEmpty;
}

final class BackupResult {
  const BackupResult(this.databaseFile, this.manifestFile, this.manifest);

  final File databaseFile;
  final File manifestFile;
  final BackupManifest manifest;
}

/// Consistent database snapshots and verified restoration.
///
/// * Snapshots use `VACUUM INTO`, which reads inside one transaction and so
///   yields a consistent copy even while the WAL database is open (a plain
///   file copy of an open SQLite database is not safe).
/// * Each snapshot has a JSON manifest (format/schema version, SHA-256, size,
///   ledger fingerprint) and is re-opened and integrity-checked after writing.
/// * Restore verifies the candidate, takes a safety backup of the current
///   database, swaps files, re-verifies, and rolls back on any failure.
final class BackupService {
  BackupService(this._app);

  final AppServices _app;

  static String manifestPathFor(String dbPath) =>
      '${p.withoutExtension(dbPath)}.manifest.json';

  Future<BackupResult> create({
    String kind = 'manual',
    String? directory,
    Actor? actor,
  }) async {
    if (actor != null && !actor.can(Permissions.backupCreate)) {
      throw const AuthorizationError('auth.denied', 'اجازه تهیه پشتیبان را ندارید.');
    }
    final dir = Directory(directory ?? _app.backupDirectory);
    await dir.create(recursive: true);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var target = p.join(dir.path, 'hadid_backup_${stamp}_$kind.db');
    var n = 1;
    while (await File(target).exists()) {
      target = p.join(dir.path, 'hadid_backup_${stamp}_${kind}_${n++}.db');
    }

    final escaped = target.replaceAll("'", "''");
    await _app.db.execute("VACUUM INTO '$escaped'");

    final file = File(target);
    final digest = await _sha256(file);
    final size = await file.length();
    final schema = await ExchangeDatabase.schemaVersion(_app.db);
    final fingerprint = await LedgerQueries(_app.db).ledgerFingerprint();
    final manifest = BackupManifest(
      formatVersion: kBackupFormatVersion,
      app: kBackupAppId,
      schemaVersion: schema,
      createdAt: now.toUtc(),
      kind: kind,
      sha256: digest,
      sizeBytes: size,
      fingerprint: fingerprint,
    );
    final manifestFile = File(manifestPathFor(target));
    await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));

    final check = await verify(target);
    if (!check.isValid) {
      throw PersistenceError('backup.verifyFailed',
          'پشتیبان ایجاد شد اما بررسی آن ناکام بود: ${check.problems.join('؛ ')}');
    }

    await _app.db.transaction((txn) async {
      await txn.insert('backup_history', {
        'kind': kind,
        'file_path': target,
        'created_at': now.toUtc().toIso8601String(),
        'schema_version': schema,
        'size_bytes': size,
        'sha256': digest,
      });
      await AuditWriter.write(txn,
          actor: actor,
          action: 'backup.create',
          entityType: 'backup',
          entityId: p.basename(target),
          after: {'kind': kind, 'size': size});
    });
    if (kind == 'auto') await _applyRetention(dir);
    return BackupResult(file, manifestFile, manifest);
  }

  /// Integrity check + manifest comparison without modifying anything.
  Future<BackupVerification> verify(String path) async {
    final problems = <String>[];
    final file = File(path);
    if (!await file.exists()) {
      return BackupVerification(path: path, problems: ['فایل پشتیبان پیدا نشد.']);
    }
    final header = await file.openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
    if (!String.fromCharCodes(header).startsWith('SQLite format 3')) {
      return BackupVerification(path: path, problems: ['فایل انتخاب‌شده پایگاه داده SQLite نیست.']);
    }

    BackupManifest? manifest;
    final manifestFile = File(manifestPathFor(path));
    if (await manifestFile.exists()) {
      try {
        manifest = BackupManifest.fromJson(
            (jsonDecode(await manifestFile.readAsString()) as Map).cast<String, Object?>());
        if (manifest.app != kBackupAppId) problems.add('این پشتیبان مربوط به این برنامه نیست.');
        if (manifest.formatVersion > kBackupFormatVersion) {
          problems.add('قالب پشتیبان جدیدتر از این نسخه برنامه است.');
        }
        final digest = await _sha256(file);
        if (digest != manifest.sha256) {
          problems.add('چک‌سام فایل با مانیفست مطابقت ندارد (فایل تغییر کرده یا خراب است).');
        }
      } catch (e) {
        problems.add('مانیفست پشتیبان قابل خواندن نیست: $e');
      }
    } else {
      problems.add('مانیفست پشتیبان یافت نشد؛ صحت فایل قابل تأیید نیست.');
    }

    int? schema;
    Map<String, Object?>? fingerprint;
    Database? db;
    try {
      db = await ExchangeDatabase.open(path, readOnly: true);
      final ic = await db.rawQuery('PRAGMA integrity_check');
      if (ic.isEmpty || ic.first.values.first != 'ok') {
        problems.add('بررسی سلامت SQLite ناکام بود: ${ic.map((r) => r.values.first).join(', ')}');
      }
      schema = await ExchangeDatabase.schemaVersion(db);
      if (schema == 0) problems.add('این فایل پایگاه داده صرافی حدید نیست.');
      if (schema > ExchangeDatabase.latestVersion) {
        problems.add('نسخه پایگاه داده پشتیبان ($schema) از برنامه جدیدتر است.');
      }
      if (schema > 0) {
        final queries = LedgerQueries(db);
        problems.addAll(await queries.integrityProblems());
        fingerprint = await queries.ledgerFingerprint();
        if (manifest != null && jsonEncode(fingerprint) != jsonEncode(manifest.fingerprint)) {
          problems.add('خلاصه دفتر حساب با مانیفست مطابقت ندارد.');
        }
      }
    } catch (e) {
      problems.add('باز کردن پشتیبان ناکام بود: $e');
    } finally {
      await db?.close();
    }
    return BackupVerification(
        path: path,
        problems: problems,
        manifest: manifest,
        schemaVersion: schema,
        fingerprint: fingerprint);
  }

  /// Replaces the live database with a verified backup.
  Future<void> restore(String path, Actor actor) async {
    if (!actor.can(Permissions.backupRestore)) {
      throw const AuthorizationError('auth.denied', 'اجازه بازیابی پشتیبان را ندارید.');
    }
    final check = await verify(path);
    if (!check.isValid) {
      throw BusinessRuleError('backup.invalid',
          'پشتیبان معتبر نیست و بازیابی انجام نشد: ${check.problems.join('؛ ')}');
    }
    final safety = await create(kind: 'pre_restore', actor: actor);

    final live = _app.databasePath;
    final staging = '$live.restore-staging';
    final previous = '$live.pre-restore-${DateTime.now().millisecondsSinceEpoch}';
    await File(path).copy(staging);

    await _app.db.close();
    try {
      await File(live).rename(previous);
      for (final suffix in ['-wal', '-shm']) {
        final f = File('$live$suffix');
        if (await f.exists()) await f.delete();
      }
      await File(staging).rename(live);
      final db = await ExchangeDatabase.open(live);
      final problems = await LedgerQueries(db).integrityProblems();
      if (problems.isNotEmpty) {
        await db.close();
        throw StateError(problems.join('; '));
      }
      _app.rebind(db);
      await db.insert('backup_history', {
        'kind': 'pre_restore',
        'file_path': safety.databaseFile.path,
        'created_at': safety.manifest.createdAt.toIso8601String(),
        'schema_version': safety.manifest.schemaVersion,
        'size_bytes': safety.manifest.sizeBytes,
        'sha256': safety.manifest.sha256,
      });
      await AuditWriter.write(db,
          actor: actor,
          action: 'backup.restore',
          entityType: 'backup',
          entityId: p.basename(path),
          after: {'safety_backup': p.basename(safety.databaseFile.path)});
      await File(previous).delete();
    } catch (e) {
      // Roll back to the pre-restore database file.
      if (await File(live).exists()) await File(live).delete();
      if (await File(previous).exists()) {
        await File(previous).rename(live);
      } else {
        await File(safety.databaseFile.path).copy(live);
      }
      _app.rebind(await ExchangeDatabase.open(live));
      throw PersistenceError('backup.restoreFailed',
          'بازیابی ناکام شد و پایگاه داده قبلی برگردانده شد: $e', cause: e);
    } finally {
      if (await File(staging).exists()) await File(staging).delete();
    }
    _app.events.notify(LedgerChange.restore);
  }

  /// Creates an automatic backup when the last one is older than the
  /// configured interval. Returns null when not due or disabled.
  Future<BackupResult?> autoBackupIfDue() async {
    if (await _app.catalog.setting('backup.auto_enabled') == '0') return null;
    final hours = int.tryParse(await _app.catalog.setting('backup.auto_interval_hours') ?? '') ?? 24;
    final rows = await _app.db.rawQuery(
        "SELECT MAX(created_at) AS t FROM backup_history WHERE kind = 'auto'");
    final last = rows.first['t'] as String?;
    if (last != null &&
        DateTime.now().toUtc().difference(DateTime.parse(last)) < Duration(hours: hours)) {
      return null;
    }
    return create(kind: 'auto');
  }

  Future<List<Map<String, Object?>>> history() =>
      _app.db.query('backup_history', orderBy: 'id DESC', limit: 100);

  Future<void> _applyRetention(Directory dir) async {
    final keep = int.tryParse(await _app.catalog.setting('backup.retention_count') ?? '') ?? 30;
    final autos = await dir
        .list()
        .where((e) => e is File && RegExp(r'hadid_backup_.*_auto(_\d+)?\.db$').hasMatch(e.path))
        .cast<File>()
        .toList();
    autos.sort((a, b) => b.path.compareTo(a.path));
    for (final old in autos.skip(keep)) {
      await old.delete();
      final m = File(manifestPathFor(old.path));
      if (await m.exists()) await m.delete();
    }
  }

  static Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();
}
