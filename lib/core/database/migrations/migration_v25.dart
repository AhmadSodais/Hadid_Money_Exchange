import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Disable glass cut-to-size tracking for general-store stock.
abstract final class MigrationV25 {
  static Future<void> up(Database db) async {
    await db.execute(
      'UPDATE products SET track_stock_by_sheet = 0 '
      'WHERE IFNULL(track_stock_by_sheet, 0) != 0',
    );
  }
}
