import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Product code (SKU) is optional: blank codes are exempt from uniqueness.
abstract final class MigrationV28 {
  static Future<void> up(Database db) async {
    await db.execute('DROP INDEX IF EXISTS idx_products_sku');
    await db.execute(
      "CREATE UNIQUE INDEX idx_products_sku ON products(sku) "
      "WHERE is_archived = 0 AND sku <> ''",
    );
  }
}
