import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Company payment ledger for settled accounts (never hard-deleted).
abstract final class MigrationV11 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partner_type TEXT NOT NULL,
        partner_id INTEGER NOT NULL,
        partner_name TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'AFN',
        paid_at TEXT NOT NULL,
        payment_method TEXT,
        settlement_side TEXT NOT NULL DEFAULT 'payable',
        notes TEXT,
        is_voided INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL
          REFERENCES company_payments(id) ON DELETE CASCADE,
        movement_id INTEGER NOT NULL
          REFERENCES stock_movements(id) ON DELETE CASCADE,
        amount REAL NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_payments_partner '
      'ON company_payments(partner_type, partner_id, paid_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_payment_alloc_payment '
      'ON company_payment_allocations(payment_id)',
    );
  }
}
