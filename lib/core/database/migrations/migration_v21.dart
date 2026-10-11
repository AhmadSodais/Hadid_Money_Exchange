import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds remnant / cut-to-size linkage on products.
abstract final class MigrationV21 {
  static Future<void> up(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    final names = {for (final r in cols) r['name'] as String};

    if (!names.contains('parent_product_id')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN parent_product_id INTEGER '
        'REFERENCES products(id)',
      );
    }
    if (!names.contains('is_remnant')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN is_remnant INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_parent '
      'ON products(parent_product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_remnant '
      'ON products(is_remnant)',
    );
  }
}
