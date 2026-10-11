import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Per-product expiry alert window (value + unit).
abstract final class MigrationV27 {
  static Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db,
      'products',
      'expiry_alert_value',
      'ALTER TABLE products ADD COLUMN expiry_alert_value INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      'products',
      'expiry_alert_unit',
      "ALTER TABLE products ADD COLUMN expiry_alert_unit TEXT NOT NULL DEFAULT 'month'",
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String sql,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final names = {for (final r in cols) r['name'] as String};
    if (!names.contains(column)) {
      await db.execute(sql);
    }
  }
}
