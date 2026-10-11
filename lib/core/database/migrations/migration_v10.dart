import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Paid amount on stock movements for receivable / payable tracking.
abstract final class MigrationV10 {
  static Future<void> up(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(stock_movements)');
    final columns = {
      for (final row in info) (row['name'] as String?) ?? '',
    };
    if (!columns.contains('paid_amount')) {
      await db.execute(
        'ALTER TABLE stock_movements ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0',
      );
    }
  }
}
