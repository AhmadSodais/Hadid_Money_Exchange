import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/errors/domain_errors.dart';
import '../database/exchange_database.dart';

/// Raw rows of the legacy three-database layout, exactly as stored.
final class LegacySnapshot {
  const LegacySnapshot({
    required this.customers,
    required this.balances,
    required this.removed,
    required this.fingerprint,
    required this.sources,
  });

  /// `customers.db` → `customers(id, name, phone, customersdata, date, time)`.
  final List<Map<String, Object?>> customers;

  /// `balance.db` → `balance(date, time, currency, systemInventory, ...)`.
  final List<Map<String, Object?>> balances;

  /// `removed_data.db` → `removed_data(...)`: entries deleted in the legacy app.
  final List<Map<String, Object?>> removed;

  /// SHA-256 over the source files; identifies one legacy data set.
  final String fingerprint;

  /// Absolute paths that were read.
  final List<String> sources;
}

/// Reads legacy databases without ever opening the originals: each file (and
/// any `-wal`/`-shm` companion) is copied to a private temporary folder and
/// the copy is opened read-only.
final class LegacyReader {
  static Future<LegacySnapshot> read({
    required String customersDb,
    String? balanceDb,
    String? removedDb,
  }) async {
    final sources = [customersDb, ?balanceDb, ?removedDb];
    for (final s in sources) {
      if (!await File(s).exists()) {
        throw ValidationError('legacy.fileMissing', 'فایل پیدا نشد: $s');
      }
    }

    final temp = await Directory.systemTemp.createTemp('hadid_legacy_');
    try {
      final bytes = BytesBuilder(copy: false);
      for (final s in sources) {
        bytes.add(p.basename(s).codeUnits);
        bytes.add(await File(s).readAsBytes());
      }
      final fingerprint = sha256.convert(bytes.takeBytes()).toString();

      final customers = await _readTable(customersDb, temp, 'customers');
      final balances = balanceDb == null ? <Map<String, Object?>>[] : await _readTable(balanceDb, temp, 'balance');
      final removed =
          removedDb == null ? <Map<String, Object?>>[] : await _readTable(removedDb, temp, 'removed_data');
      return LegacySnapshot(
        customers: customers,
        balances: balances,
        removed: removed,
        fingerprint: fingerprint,
        sources: [for (final s in sources) p.absolute(s)],
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<List<Map<String, Object?>>> _readTable(String source, Directory temp, String table) async {
    final copy = p.join(temp.path, '${temp.listSync().length}_${p.basename(source)}');
    await File(source).copy(copy);
    for (final suffix in ['-wal', '-shm']) {
      final companion = File('$source$suffix');
      if (await companion.exists()) await companion.copy('$copy$suffix');
    }
    Database? db;
    try {
      db = await ExchangeDatabase.factory.openDatabase(
        copy,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final exists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [table]);
      if (exists.isEmpty) {
        throw ValidationError('legacy.tableMissing',
            'جدول «$table» در فایل ${p.basename(source)} وجود ندارد؛ این فایل از برنامه قبلی نیست.');
      }
      final rows = await db.rawQuery('SELECT rowid AS _rowid, * FROM $table ORDER BY rowid');
      return [for (final r in rows) Map<String, Object?>.of(r)];
    } on DatabaseException catch (e) {
      throw PersistenceError('legacy.unreadable', 'فایل ${p.basename(source)} قابل خواندن نیست.', cause: e);
    } finally {
      await db?.close();
    }
  }
}
