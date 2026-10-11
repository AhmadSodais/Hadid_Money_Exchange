import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds per-product unit weight and weight unit for inbound/outbound display.
abstract final class MigrationV8 {
  static Future<void> up(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(products)');
    final columns = {
      for (final row in info) (row['name'] as String?) ?? '',
    };

    if (!columns.contains('unit_weight')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN unit_weight REAL',
      );
    }
    if (!columns.contains('weight_unit')) {
      await db.execute(
        "ALTER TABLE products ADD COLUMN weight_unit TEXT DEFAULT 'kg'",
      );
    }
  }
}
