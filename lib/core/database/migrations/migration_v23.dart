import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Persists cut-piece area alongside length/width on sales lines & movements.
abstract final class MigrationV23 {
  static Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db,
      'stock_movements',
      'area_m2',
      'ALTER TABLE stock_movements ADD COLUMN area_m2 REAL',
    );
    await _addColumnIfMissing(
      db,
      'stock_movements',
      'parent_length_m',
      'ALTER TABLE stock_movements ADD COLUMN parent_length_m REAL',
    );
    await _addColumnIfMissing(
      db,
      'stock_movements',
      'parent_width_m',
      'ALTER TABLE stock_movements ADD COLUMN parent_width_m REAL',
    );
    await _addColumnIfMissing(
      db,
      'order_items',
      'area_m2',
      'ALTER TABLE order_items ADD COLUMN area_m2 REAL',
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
