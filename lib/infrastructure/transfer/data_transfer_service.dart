import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:shamsi_date/shamsi_date.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../application/app_services.dart';
import '../../application/audit_writer.dart';
import '../../application/ledger_events.dart';
import '../../application/ledger_queries.dart';
import '../../application/read_models.dart';
import '../../application/security_service.dart';
import '../../domain/accounting/account.dart';
import '../../domain/errors/domain_errors.dart';
import '../../domain/security/permissions.dart';
import '../database/exchange_database.dart';
import '../export/excel_export.dart';

const String kDataWorkbookApp = 'hadid_money_exchange';
const int kDataWorkbookFormat = 1;

/// Rows written to (export) or read from (import) each table.
typedef DataTransferSummary = Map<String, int>;

/// Full-data Excel transfer and data reset.
///
/// * Export writes every business table to one workbook (one sheet per
///   table, column names in the first row) from a single read transaction.
///   Dates are written in the Solar Hijri calendar; credentials are never
///   exported.
/// * Import never merges into live data. It builds a separate database from
///   the workbook, checks the ledger invariants and the exported fingerprint,
///   and only then swaps it in through [BackupService.replaceLive], which
///   takes a safety backup first and rolls back on any failure.
/// * Clear swaps in a freshly seeded database the same way, keeping only the
///   exchange information, posting policies and currency definitions.
final class DataTransferService {
  DataTransferService(this._app);

  final AppServices _app;

  /// Insert order; parents come before the rows that reference them.
  static const tables = [
    'currencies',
    'application_settings',
    'sequences',
    'roles',
    'permissions',
    'role_permissions',
    'users',
    'customers',
    'cash_drawers',
    'accounts',
    'exchange_rates',
    'transactions',
    'journal_entries',
    'journal_lines',
    'opening_balances',
    'reconciliation_records',
    'transaction_corrections',
    'audit_logs',
  ];

  static const _requiredTables = {'currencies', 'roles', 'users', 'customers', 'cash_drawers', 'accounts'};
  static const _excludedColumns = {
    'users': {'password_hash', 'password_salt', 'password_iterations', 'failed_attempts', 'locked_until'},
  };
  static const _businessDateColumns = {'effective_date', 'business_date'};
  static const infoSheet = 'info';

  static bool _isTimestamp(String column) => column.endsWith('_at');

  // ------------------------------------------------------------------ export

  /// Builds the full-data workbook.
  Future<(List<int>, DataTransferSummary)> exportWorkbook(Actor actor) async {
    _require(actor, Permissions.backupCreate, 'اجازه خروجی گرفتن از داده‌ها را ندارید.');
    return _buildWorkbook();
  }

  Future<(List<int>, DataTransferSummary)> _buildWorkbook() async {
    final summary = <String, int>{};
    final sheets = <ExportSheet>[];
    late Map<String, Object?> fingerprint;
    late int schema;
    await _app.db.transaction((txn) async {
      schema = await ExchangeDatabase.schemaVersion(txn);
      fingerprint = await LedgerQueries(txn).ledgerFingerprint();
      for (final table in tables) {
        final excluded = _excludedColumns[table] ?? const <String>{};
        final columns = [
          for (final c in await txn.rawQuery('PRAGMA table_info($table)'))
            if (!excluded.contains(c['name'])) c['name'] as String,
        ];
        final rows = await txn.query(table, columns: columns, orderBy: 'rowid');
        summary[table] = rows.length;
        sheets.add(
          ExportSheet(
            name: table,
            headers: columns,
            rows: [
              for (final r in rows) [for (final c in columns) _exportCell(c, r[c])],
            ],
          ),
        );
      }
    });
    final info = ExportSheet(
      name: infoSheet,
      headers: const ['key', 'value'],
      rows: [
        ['app', kDataWorkbookApp],
        ['format_version', '$kDataWorkbookFormat'],
        ['schema_version', '$schema'],
        ['exported_at', _shamsiTimestamp(_app.now().toUtc())],
        ['fingerprint', jsonEncode(fingerprint)],
        [
          'note',
          'این فایل از «خروجی اکسل» ساخته شده و با «ورودی اکسل» در تنظیمات قابل بازگردانی است. تاریخ‌ها هجری شمسی هستند.',
        ],
      ],
    );
    return (ExcelExport.build([info, ...sheets]), summary);
  }

  Future<DataTransferSummary> exportTo(String path, Actor actor) async {
    final (bytes, summary) = await exportWorkbook(actor);
    await File(path).writeAsBytes(bytes, flush: true);
    await AuditWriter.write(
      _app.db,
      actor: actor,
      action: 'data.export',
      entityType: 'excel',
      entityId: p.basename(path),
      after: {
        'transactions': summary['transactions'] ?? 0,
        'customers': summary['customers'] ?? 0,
      },
    );
    return summary;
  }

  // ------------------------------------------------------------ auto export

  /// Folder for automatic exports: the configured one, else the default.
  Future<String> autoExportDirectory() async {
    final configured = (await _app.catalog.setting('excel.auto_directory'))?.trim();
    return configured == null || configured.isEmpty ? _app.excelExportDirectory : configured;
  }

  /// Writes a workbook to the automatic-export folder when enabled and the
  /// last attempt is older than the configured interval. Every attempt,
  /// successful or not, is recorded in `excel_export_history`. Returns the
  /// history row, or null when not due or disabled.
  Future<Map<String, Object?>?> autoExportIfDue() async {
    if (await _app.catalog.setting('excel.auto_enabled') != '1') return null;
    final hours = int.tryParse(await _app.catalog.setting('excel.auto_interval_hours') ?? '') ?? 24;
    final rows = await _app.db.rawQuery('SELECT MAX(created_at) AS t FROM excel_export_history');
    final last = rows.first['t'] as String?;
    final now = _app.now().toUtc();
    if (last != null && now.difference(DateTime.parse(last)) < Duration(hours: hours)) return null;
    return runAutoExport();
  }

  /// Runs one automatic export now, regardless of the schedule. A call made
  /// while another automatic export is running joins that one. [actor] is
  /// null only for the scheduler.
  Future<Map<String, Object?>> runAutoExport({Actor? actor}) {
    if (actor != null) _require(actor, Permissions.backupCreate, 'اجازه خروجی گرفتن از داده‌ها را ندارید.');
    final running = _autoExport;
    if (running != null) return running;
    return _autoExport = _runAutoExport().whenComplete(() => _autoExport = null);
  }

  Future<Map<String, Object?>>? _autoExport;

  Future<Map<String, Object?>> _runAutoExport() async {
    final now = _app.now();
    final dir = await autoExportDirectory();
    final stamp = _shamsiTimestamp(now.toUtc()).replaceAll('/', '-').replaceAll(':', '').replaceAll(' ', '_');
    var target = p.join(dir, 'hadid_auto_$stamp.xlsx');
    var n = 2;
    while (await File(target).exists()) {
      target = p.join(dir, 'hadid_auto_${stamp}_${n++}.xlsx');
    }
    final row = <String, Object?>{'file_path': target, 'created_at': now.toUtc().toIso8601String()};
    try {
      await Directory(dir).create(recursive: true);
      final (bytes, summary) = await _buildWorkbook();
      await File(target).writeAsBytes(bytes, flush: true);
      row.addAll({'outcome': 'success', 'size_bytes': bytes.length, 'transactions': summary['transactions'] ?? 0});
    } catch (e) {
      row.addAll({'outcome': 'failure', 'message': '$e'});
    }
    row['id'] = await _app.db.insert('excel_export_history', row);
    if (row['outcome'] == 'success') await _applyAutoRetention();
    _app.events.notify(LedgerChange.export);
    return row;
  }

  Future<List<Map<String, Object?>>> autoExportHistory({int limit = 100}) =>
      _app.db.query('excel_export_history', orderBy: 'id DESC', limit: limit);

  /// Deletes automatic export files beyond the retention count. Only files
  /// recorded in the history are touched, never other files in the folder.
  Future<void> _applyAutoRetention() async {
    final keep = int.tryParse(await _app.catalog.setting('excel.auto_retention_count') ?? '') ?? 30;
    final old = await _app.db.query(
      'excel_export_history',
      columns: ['file_path'],
      where: "outcome = 'success'",
      orderBy: 'id DESC',
      limit: -1,
      offset: keep,
    );
    for (final r in old) {
      final f = File(r['file_path'] as String);
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Newest Excel output, input, and clear-all events.
  Future<List<AuditEntry>> fileLog({int limit = 100}) async {
    final rows = await _app.db.rawQuery('''
      SELECT a.*, u.display_name AS actor_name
      FROM audit_logs a LEFT JOIN users u ON u.id = a.actor_user_id
      WHERE a.action IN ('data.export', 'data.import', 'data.clear')
      ORDER BY a.id DESC LIMIT ?
    ''', [limit]);
    return rows.map(AuditEntry.fromRow).toList();
  }

  // ------------------------------------------------------------------ import

  /// Replaces all data with the content of a workbook produced by export.
  Future<DataTransferSummary> importFrom(String path, Actor actor) async {
    _require(actor, Permissions.backupRestore, 'اجازه ورود داده‌ها را ندارید.');
    final book = _readWorkbook(await File(path).readAsBytes());
    final info = _readInfo(book);

    final staging = '${_app.databasePath}.import-staging';
    await _deleteDatabaseFiles(staging);
    final summary = <String, int>{};
    Database? db;
    try {
      db = await ExchangeDatabase.open(staging, seed: false);
      try {
        await db.transaction((txn) async {
          await txn.execute('PRAGMA defer_foreign_keys = ON');
          for (final table in tables) {
            final rows = book[table];
            if (rows == null) {
              if (_requiredTables.contains(table)) {
                throw ValidationError('import.sheetMissing', 'برگه «$table» در فایل اکسل وجود ندارد.');
              }
              continue;
            }
            summary[table] = await _insertSheet(txn, table, rows);
          }
          for (final perm in Permissions.all.entries) {
            await txn.insert('permissions', {
              'code': perm.key,
              'description_fa': perm.value,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        });
      } on DatabaseException catch (e) {
        throw ValidationError('import.references', 'ارجاعات داخل فایل اکسل با هم سازگار نیستند: $e');
      }
      final problems = await _importProblems(db, info);
      if (problems.isNotEmpty) {
        throw BusinessRuleError('import.invalid', 'فایل اکسل معتبر نیست و داده‌ها تغییر نکرد: ${problems.join('؛ ')}');
      }
      await db.close();
      db = null;
    } catch (_) {
      await db?.close();
      await _deleteDatabaseFiles(staging);
      rethrow;
    }

    await _app.backups.replaceLive(
      staging,
      actor,
      action: 'data.import',
      entityId: p.basename(path),
      failureCode: 'import.failed',
      failureMessage: 'ورود داده‌ها ناکام شد و داده‌های قبلی برگردانده شد',
      keepBackupHistory: true,
    );
    return summary;
  }

  Future<int> _insertSheet(Transaction txn, String table, List<List<String?>> rows) async {
    if (rows.isEmpty) return 0;
    final columns = {for (final c in await txn.rawQuery('PRAGMA table_info($table)')) c['name'] as String: c};
    final header = [for (final h in rows.first) (h ?? '').trim()];
    final indexed = <int, String>{
      for (var i = 0; i < header.length; i++)
        if (columns.containsKey(header[i])) i: header[i],
    };
    if (indexed.isEmpty) {
      throw ValidationError('import.header', 'ردیف اول برگه «$table» نام ستون‌ها را ندارد.');
    }
    var count = 0;
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => c == null || c.trim().isEmpty)) continue;
      final values = <String, Object?>{};
      for (final e in indexed.entries) {
        final raw = e.key < row.length ? row[e.key]?.trim() ?? '' : '';
        final column = columns[e.value]!;
        if (raw.isEmpty) {
          if (column['dflt_value'] != null) continue;
          final text = !'${column['type']}'.toUpperCase().contains('INT');
          values[e.value] = column['notnull'] == 1 && text ? '' : null;
          continue;
        }
        values[e.value] = _importCell(table, e.value, '${column['type']}', raw, r + 1);
      }
      try {
        await txn.insert(table, values);
      } on DatabaseException catch (e) {
        throw ValidationError('import.row', 'برگه «$table»، ردیف ${r + 1}: $e');
      }
      count++;
    }
    return count;
  }

  Future<List<String>> _importProblems(Database db, Map<String, String> info) async {
    final queries = LedgerQueries(db);
    final problems = [...await queries.integrityProblems()];
    final expected = info['fingerprint'];
    if (expected != null && expected.isNotEmpty) {
      final actual = jsonEncode(await queries.ledgerFingerprint());
      String canonical;
      try {
        canonical = jsonEncode(jsonDecode(expected));
      } catch (_) {
        canonical = expected;
      }
      if (actual != canonical) {
        problems.add('تعداد یا جمع اسناد با خلاصه ثبت‌شده در فایل مطابقت ندارد (فایل ناقص یا دستکاری شده است)');
      }
    }
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        (await db.rawQuery(sql, args)).first.values.first as int;
    if (await count('SELECT COUNT(*) FROM users WHERE id = ?', [SecurityService.ownerUserId]) == 0) {
      problems.add('کاربر مالک برنامه در فایل نیست');
    }
    if (await count("SELECT COUNT(*) FROM customers WHERE is_walk_in = 1") != 1) {
      problems.add('مشتری متفرقه در فایل نیست');
    }
    if (await count('SELECT COUNT(*) FROM cash_drawers WHERE is_active = 1') == 0) {
      problems.add('هیچ صندوق فعالی در فایل نیست');
    }
    if (await count('''SELECT COUNT(*) FROM customers c
        WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.customer_id = c.id)''') >
        0) {
      problems.add('حساب بعضی از مشتریان در فایل نیست');
    }
    if (await count('''SELECT COUNT(*) FROM cash_drawers d
        WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.drawer_id = d.id)''') >
        0) {
      problems.add('حساب بعضی از صندوق‌ها در فایل نیست');
    }
    for (final role in AccountRole.values) {
      if (role == AccountRole.control || role == AccountRole.cash || role == AccountRole.customer) continue;
      if (await count('SELECT COUNT(*) FROM accounts WHERE role = ?', [role.name]) != 1) {
        problems.add('حساب سیستمی «${role.name}» در فایل نیست');
      }
    }
    return problems;
  }

  Map<String, List<List<String?>>> _readWorkbook(List<int> bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ValidationError('import.file', 'فایل انتخاب‌شده فایل اکسل معتبر نیست: $e');
    }
    return {
      for (final e in excel.tables.entries)
        e.key: [
          for (final row in e.value.rows) [for (final cell in row) _cellText(cell?.value)],
        ],
    };
  }

  Map<String, String> _readInfo(Map<String, List<List<String?>>> book) {
    final rows = book[infoSheet];
    if (rows == null) {
      throw const ValidationError(
        'import.notOurs',
        'این فایل از «خروجی اکسل» همین برنامه ساخته نشده است (برگه info وجود ندارد).',
      );
    }
    final info = <String, String>{
      for (final r in rows.skip(1))
        if (r.length >= 2 && r[0] != null) r[0]!.trim(): (r[1] ?? '').trim(),
    };
    if (info['app'] != kDataWorkbookApp) {
      throw const ValidationError('import.notOurs', 'این فایل از «خروجی اکسل» همین برنامه ساخته نشده است.');
    }
    final format = int.tryParse(info['format_version'] ?? '');
    if (format == null || format > kDataWorkbookFormat) {
      throw const ValidationError('import.format', 'قالب فایل اکسل جدیدتر از این نسخه برنامه است.');
    }
    final schema = int.tryParse(info['schema_version'] ?? '');
    if (schema == null || schema > ExchangeDatabase.latestVersion) {
      throw const ValidationError('import.schema', 'فایل اکسل از نسخه جدیدتر برنامه ساخته شده است.');
    }
    return info;
  }

  // ------------------------------------------------------------------- clear

  /// Removes every customer, transaction, rate, balance count and audit
  /// entry. Exchange information, posting policies, currency definitions and
  /// user names and phone numbers are kept. A safety backup of the removed
  /// data is taken first.
  Future<void> clearAll(Actor actor) async {
    _require(actor, Permissions.backupRestore, 'اجازه پاک کردن داده‌ها را ندارید.');
    final settings = await _app.db.query('application_settings');
    final currencies = await _app.db.query('currencies', orderBy: 'sort_order, code');
    final profiles = await _app.db.query('users', columns: ['id', 'display_name', 'phone']);

    final staging = '${_app.databasePath}.clear-staging';
    await _deleteDatabaseFiles(staging);
    try {
      final db = await ExchangeDatabase.open(staging);
      try {
        await db.transaction((txn) async {
          for (final s in settings) {
            await txn.insert('application_settings', s, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final c in currencies) {
            final updated = await txn.update('currencies', c, where: 'code = ?', whereArgs: [c['code']]);
            if (updated == 0) await txn.insert('currencies', c);
          }
          for (final u in profiles) {
            await txn.update('users', {'display_name': u['display_name'], 'phone': u['phone']},
                where: 'id = ?', whereArgs: [u['id']]);
          }
        });
      } finally {
        await db.close();
      }
    } catch (_) {
      await _deleteDatabaseFiles(staging);
      rethrow;
    }

    await _app.backups.replaceLive(
      staging,
      actor,
      action: 'data.clear',
      entityId: 'all',
      failureCode: 'clear.failed',
      failureMessage: 'پاک کردن داده‌ها ناکام شد و داده‌های قبلی برگردانده شد',
      keepBackupHistory: true,
    );
  }

  // ----------------------------------------------------------------- helpers

  static void _require(Actor actor, String permission, String message) {
    if (!actor.can(permission)) throw AuthorizationError('auth.denied', message);
  }

  static Future<void> _deleteDatabaseFiles(String path) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _exportCell(String column, Object? value) {
    if (value == null) return '';
    if (value is String) {
      if (_businessDateColumns.contains(column)) return _shamsiDate(value);
      if (_isTimestamp(column)) {
        final t = DateTime.tryParse(value);
        return t == null ? value : _shamsiTimestamp(t);
      }
    }
    return '$value';
  }

  static String _shamsiDate(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) return iso;
    final j = Jalali.fromDateTime(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
    return '${j.year}/${_two(j.month)}/${_two(j.day)}';
  }

  static String _shamsiTimestamp(DateTime t) {
    final local = t.toLocal();
    final j = Jalali.fromDateTime(local);
    return '${j.year}/${_two(j.month)}/${_two(j.day)} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  /// Accepts Solar Hijri `yyyy/mm/dd` (as exported) or Gregorian ISO.
  static DateTime? _parseDate(String text) {
    final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    try {
      if (y < 1700) {
        final j = Jalali(y, mo, d);
        if (j.month != mo || j.day != d || d > j.monthLength) return null;
        return j.toDateTime();
      }
      final g = DateTime(y, mo, d);
      return g.month == mo && g.day == d ? g : null;
    } catch (_) {
      return null;
    }
  }

  static Object _importCell(String table, String column, String type, String raw, int rowNo) {
    String where() => 'برگه «$table»، ردیف $rowNo، ستون $column';
    if (_businessDateColumns.contains(column)) {
      final d = _parseDate(raw);
      if (d == null) throw ValidationError('import.date', 'تاریخ نامعتبر در ${where()}: $raw');
      return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
    }
    if (_isTimestamp(column)) {
      final parts = raw.split(RegExp(r'\s+'));
      if (parts.length == 2) {
        final d = _parseDate(parts[0]);
        final t = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(parts[1]);
        if (d != null && t != null) {
          return DateTime(
            d.year,
            d.month,
            d.day,
            int.parse(t[1]!),
            int.parse(t[2]!),
            int.parse(t[3] ?? '0'),
          ).toUtc().toIso8601String();
        }
      }
      final iso = DateTime.tryParse(raw);
      if (iso != null) return iso.toUtc().toIso8601String();
      final dateOnly = _parseDate(raw);
      if (dateOnly != null) return dateOnly.toUtc().toIso8601String();
      throw ValidationError('import.date', 'زمان نامعتبر در ${where()}: $raw');
    }
    if (type.toUpperCase().contains('INT')) {
      final n = int.tryParse(raw) ?? _wholeDouble(raw);
      if (n == null) throw ValidationError('import.number', 'عدد صحیح نامعتبر در ${where()}: $raw');
      return n;
    }
    return raw;
  }

  static int? _wholeDouble(String raw) {
    final d = double.tryParse(raw);
    if (d == null || d != d.truncateToDouble() || d.abs() > 9007199254740991) return null;
    return d.toInt();
  }

  static String? _cellText(CellValue? value) => switch (value) {
    null => null,
    DoubleCellValue(:final value) when value == value.truncateToDouble() && value.abs() < 9007199254740991 =>
      value.toInt().toString(),
    DateCellValue() => () {
      final d = value.asDateTimeLocal();
      return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
    }(),
    DateTimeCellValue() => value.asDateTimeLocal().toIso8601String(),
    _ => value.toString(),
  };
}
