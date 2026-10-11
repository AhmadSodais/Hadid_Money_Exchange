import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Restores the expenses module (dropped in v5).
abstract final class MigrationV17 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        currency_id INTEGER REFERENCES currencies(id),
        currency_code TEXT,
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        payee TEXT,
        expense_date TEXT NOT NULL,
        note TEXT,
        receipt_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)',
    );
  }
}
