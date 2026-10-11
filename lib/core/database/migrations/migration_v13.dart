import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sales invoices (orders) with line items; link stock_movements via order_id.
abstract final class MigrationV13 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        partner_type TEXT,
        partner_id INTEGER,
        partner_name TEXT,
        currency_id INTEGER,
        currency_code TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'paid',
        status TEXT NOT NULL DEFAULT 'completed',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        length_m REAL,
        width_m REAL,
        paid_amount REAL NOT NULL DEFAULT 0,
        currency_id INTEGER,
        movement_id INTEGER,
        warehouse_id INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)',
    );

    final info = await db.rawQuery('PRAGMA table_info(stock_movements)');
    final columns = {
      for (final row in info) (row['name'] as String?) ?? '',
    };
    if (!columns.contains('order_id')) {
      await db.execute(
        'ALTER TABLE stock_movements ADD COLUMN order_id INTEGER '
        'REFERENCES orders(id)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_movements_order '
      'ON stock_movements(order_id)',
    );
  }
}
