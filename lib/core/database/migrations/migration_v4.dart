import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds currency on stock movements for inbound / outbound prices.
abstract final class MigrationV4 {
  static Future<void> up(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(stock_movements)');
    final exists = info.any((row) => row['name'] == 'currency_id');
    if (exists) return;
    await db.execute(
      'ALTER TABLE stock_movements ADD COLUMN currency_id INTEGER '
      'REFERENCES currencies(id)',
    );
  }
}
