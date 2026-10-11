import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Invoice-linked company payment allocations (purchase / order).
abstract final class MigrationV16 {
  static Future<void> up(Database db) async {
    final cols = await db.rawQuery(
      'PRAGMA table_info(company_payment_allocations)',
    );
    final names = {for (final r in cols) r['name'] as String};

    if (!names.contains('purchase_id')) {
      await db.execute(
        'ALTER TABLE company_payment_allocations '
        'ADD COLUMN purchase_id INTEGER REFERENCES purchases(id)',
      );
    }
    if (!names.contains('order_id')) {
      await db.execute(
        'ALTER TABLE company_payment_allocations '
        'ADD COLUMN order_id INTEGER REFERENCES orders(id)',
      );
    }

    // Allow legacy rows without a movement when allocating to invoices only.
    // SQLite cannot drop NOT NULL easily; new inserts may set movement_id null
    // only if the column is nullable. Recreate if still NOT NULL.
    final movementCol = cols.where((r) => r['name'] == 'movement_id').firstOrNull;
    final notNull = (movementCol?['notnull'] as int? ?? 0) == 1;
    if (notNull) {
      await db.execute('''
        CREATE TABLE company_payment_allocations_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          payment_id INTEGER NOT NULL
            REFERENCES company_payments(id) ON DELETE CASCADE,
          movement_id INTEGER REFERENCES stock_movements(id) ON DELETE CASCADE,
          purchase_id INTEGER REFERENCES purchases(id),
          order_id INTEGER REFERENCES orders(id),
          amount REAL NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO company_payment_allocations_new
          (id, payment_id, movement_id, purchase_id, order_id, amount)
        SELECT id, payment_id, movement_id, NULL, NULL, amount
        FROM company_payment_allocations
      ''');
      await db.execute('DROP TABLE company_payment_allocations');
      await db.execute(
        'ALTER TABLE company_payment_allocations_new '
        'RENAME TO company_payment_allocations',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_company_payment_alloc_payment '
        'ON company_payment_allocations(payment_id)',
      );
    }
  }
}
