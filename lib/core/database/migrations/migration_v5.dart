import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drops modules no longer used: sales, orders, cutting jobs, expenses.
abstract final class MigrationV5 {
  static Future<void> up(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    for (final table in const [
      'sale_items',
      'sales',
      'order_items',
      'orders',
      'cutting_jobs',
      'expenses',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    await db.execute('PRAGMA foreign_keys = ON');
  }
}
