import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds partner / dimension fields for Excel-style warehouse movements.
abstract final class MigrationV2 {
  static Future<void> up(Database db) async {
    await _addColumnIfMissing(db, 'stock_movements', 'partner_name', 'TEXT');
    await _addColumnIfMissing(db, 'stock_movements', 'length_m', 'REAL');
    await _addColumnIfMissing(db, 'stock_movements', 'width_m', 'REAL');
    await _addColumnIfMissing(
      db,
      'stock_movements',
      'broken_qty',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'products', 'notes', 'TEXT');
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String typeSql,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $typeSql');
  }
}
