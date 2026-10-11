import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Per-product cost currency and per-purchase-line selling currency.
abstract final class MigrationV15 {
  static Future<void> up(Database db) async {
    final productCols = await db.rawQuery('PRAGMA table_info(products)');
    final hasCostCurrency = productCols.any(
      (row) => row['name'] == 'cost_currency_id',
    );
    if (!hasCostCurrency) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN cost_currency_id INTEGER '
        'REFERENCES currencies(id)',
      );
      // Seed from existing catalog currency when present.
      await db.execute(
        'UPDATE products SET cost_currency_id = currency_id '
        'WHERE cost_currency_id IS NULL AND currency_id IS NOT NULL',
      );
    }

    final itemCols = await db.rawQuery('PRAGMA table_info(purchase_items)');
    final hasSellCurrency = itemCols.any(
      (row) => row['name'] == 'selling_currency_id',
    );
    if (!hasSellCurrency) {
      await db.execute(
        'ALTER TABLE purchase_items ADD COLUMN selling_currency_id INTEGER '
        'REFERENCES currencies(id)',
      );
    }

    final hasSellPrice = itemCols.any(
      (row) => row['name'] == 'selling_price',
    );
    if (!hasSellPrice) {
      await db.execute(
        'ALTER TABLE purchase_items ADD COLUMN selling_price REAL',
      );
    }
  }
}
