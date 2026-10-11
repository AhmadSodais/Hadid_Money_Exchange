import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Settlement side on company payments: payable (we owe) vs receivable (they owe us).
abstract final class MigrationV12 {
  static Future<void> up(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(company_payments)');
    final columns = {
      for (final row in info) (row['name'] as String?) ?? '',
    };
    if (!columns.contains('settlement_side')) {
      await db.execute(
        "ALTER TABLE company_payments ADD COLUMN settlement_side TEXT NOT NULL DEFAULT 'payable'",
      );
    }
  }
}
