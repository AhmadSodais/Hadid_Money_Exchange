import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds warehouses table and warehouse_id links on products / stock_movements.
abstract final class MigrationV6 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_warehouses_name ON warehouses(name)',
    );

    await db.execute(
      'ALTER TABLE products ADD COLUMN warehouse_id INTEGER REFERENCES warehouses(id)',
    );
    await db.execute(
      'ALTER TABLE stock_movements ADD COLUMN warehouse_id INTEGER REFERENCES warehouses(id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_warehouse ON products(warehouse_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse ON stock_movements(warehouse_id)',
    );

    // Link products whose notes first line matches an existing warehouse name.
    final warehouses = await db.query('warehouses', columns: ['id', 'name']);
    final byName = {
      for (final w in warehouses) (w['name'] as String).trim().toLowerCase(): w['id'] as int,
    };
    final products = await db.query('products', columns: ['id', 'notes']);
    for (final p in products) {
      final notes = (p['notes'] as String?)?.trim();
      if (notes == null || notes.isEmpty) continue;
      final first = notes.split('\n').first.trim().toLowerCase();
      final wid = byName[first];
      if (wid == null) continue;
      await db.update(
        'products',
        {'warehouse_id': wid},
        where: 'id = ?',
        whereArgs: [p['id']],
      );
    }

    // Backfill movements from their product's warehouse when possible.
    await db.execute('''
      UPDATE stock_movements
      SET warehouse_id = (
        SELECT p.warehouse_id FROM products p WHERE p.id = stock_movements.product_id
      )
      WHERE warehouse_id IS NULL
        AND EXISTS (
          SELECT 1 FROM products p
          WHERE p.id = stock_movements.product_id AND p.warehouse_id IS NOT NULL
        )
    ''');
  }
}
