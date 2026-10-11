import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Removes static demo rows that older migrations used to insert on first open.
abstract final class MigrationV20 {
  static const _demoCategories = [
    'Sheet Glass',
    'Tempered',
    'Double Glazing',
    'Mirrors',
    'Accessories',
    'Services',
  ];

  static const _demoWarehouses = [
    'A1-01 – Main Warehouse',
    'B1-02 – Finished Glass',
    'C1-01 – Mirror Section',
    'D1-01 – Tempered Glass',
  ];

  static const _demoUnits = [
    'Sheet',
    'Square Meter',
    'Piece',
    'Meter',
    'Liter',
    'Kilogram',
  ];

  static Future<void> up(Database db) async {
    // Unlink products from demo categories / warehouses before deleting.
    final catPlaceholders = List.filled(_demoCategories.length, '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE products SET category_id = NULL
      WHERE category_id IN (
        SELECT id FROM categories WHERE name IN ($catPlaceholders)
      )
      ''',
      _demoCategories,
    );

    final whPlaceholders = List.filled(_demoWarehouses.length, '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE products SET warehouse_id = NULL
      WHERE warehouse_id IN (
        SELECT id FROM warehouses WHERE name IN ($whPlaceholders)
      )
      ''',
      _demoWarehouses,
    );
    await db.rawUpdate(
      '''
      UPDATE stock_movements SET warehouse_id = NULL
      WHERE warehouse_id IN (
        SELECT id FROM warehouses WHERE name IN ($whPlaceholders)
      )
      ''',
      _demoWarehouses,
    );

    await db.delete(
      'categories',
      where: 'name IN ($catPlaceholders)',
      whereArgs: _demoCategories,
    );
    await db.delete(
      'warehouses',
      where: 'name IN ($whPlaceholders)',
      whereArgs: _demoWarehouses,
    );

    final unitPlaceholders = List.filled(_demoUnits.length, '?').join(',');
    await db.delete(
      'units_of_measure',
      where: 'name IN ($unitPlaceholders)',
      whereArgs: _demoUnits,
    );

    // Keep AFN / USD / EUR — they are required for currency dropdowns.
    // (Demo seed removal must not wipe the base currency catalog.)

    // Walk-in customer only when unused.
    final walkIn = await db.query(
      'customers',
      columns: ['id'],
      where: 'LOWER(name) = ?',
      whereArgs: ['walk-in customer'],
      limit: 1,
    );
    if (walkIn.isNotEmpty) {
      final id = walkIn.first['id'] as int;
      final used = await db.rawQuery(
        '''
        SELECT
          (SELECT COUNT(*) FROM stock_movements WHERE customer_id = ?) +
          (SELECT COUNT(*) FROM orders WHERE customer_id = ?)
            AS refs
        ''',
        [id, id],
      );
      final refs = used.isEmpty ? 0 : (used.first['refs'] as int? ?? 0);
      if (refs == 0) {
        await db.delete('customers', where: 'id = ?', whereArgs: [id]);
      }
    }

    // Clear branded default store name if still present.
    await db.update(
      'app_settings',
      {
        'value': '',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'key = ? AND value = ?',
      whereArgs: ['store_name', 'GlassFlow Shop'],
    );
  }
}
