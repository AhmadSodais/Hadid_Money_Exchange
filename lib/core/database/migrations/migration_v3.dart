import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adds per-transaction unit price for inbound / outbound movements.
abstract final class MigrationV3 {
  static Future<void> up(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(stock_movements)');
    final exists = info.any((row) => row['name'] == 'unit_price');
    if (exists) return;
    await db.execute(
      'ALTER TABLE stock_movements ADD COLUMN unit_price REAL',
    );
  }
}
