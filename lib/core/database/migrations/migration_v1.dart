import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initial schema migration — creates all GlassFlow tables.
abstract final class MigrationV1 {
  static Future<void> up(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE currencies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        is_base INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE units_of_measure (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        abbreviation TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        outstanding_balance REAL NOT NULL DEFAULT 0,
        total_purchases REAL NOT NULL DEFAULT 0,
        last_purchase_at TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        category_id INTEGER REFERENCES categories(id),
        thickness REAL,
        standard_width REAL,
        standard_height REAL,
        unit_of_measure TEXT,
        initial_stock REAL NOT NULL DEFAULT 0,
        current_stock REAL NOT NULL DEFAULT 0,
        minimum_stock_alert REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL DEFAULT 0,
        currency_id INTEGER REFERENCES currencies(id),
        supplier_id INTEGER REFERENCES suppliers(id),
        image_path TEXT,
        track_stock_by_sheet INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_archived INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX idx_products_sku ON products(sku) WHERE is_archived = 0',
    );
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute(
      'CREATE INDEX idx_products_category ON products(category_id)',
    );
    await db.execute(
      'CREATE INDEX idx_products_supplier ON products(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX idx_products_currency ON products(currency_id)',
    );
    await db.execute(
      'CREATE INDEX idx_products_stock ON products(current_stock)',
    );
    await db.execute(
      'CREATE INDEX idx_products_created ON products(created_at)',
    );

    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id),
        movement_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        balance_after REAL NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        notes TEXT,
        partner_name TEXT,
        length_m REAL,
        width_m REAL,
        broken_qty REAL NOT NULL DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)',
    );
    await db.execute(
      'CREATE INDEX idx_stock_movements_created ON stock_movements(created_at)',
    );

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER REFERENCES customers(id),
        currency_id INTEGER REFERENCES currencies(id),
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        change_amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        status TEXT NOT NULL DEFAULT 'completed',
        notes TEXT,
        is_held INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
        product_id INTEGER REFERENCES products(id),
        product_name TEXT NOT NULL,
        sku TEXT,
        width REAL,
        height REAL,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER REFERENCES customers(id),
        currency_id INTEGER REFERENCES currencies(id),
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        status TEXT NOT NULL DEFAULT 'draft',
        required_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id INTEGER REFERENCES products(id),
        product_name TEXT NOT NULL,
        glass_type TEXT,
        width REAL,
        height REAL,
        thickness REAL,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        status TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cutting_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER REFERENCES customers(id),
        product_id INTEGER REFERENCES products(id),
        glass_type TEXT,
        thickness REAL,
        width REAL,
        height REAL,
        quantity REAL NOT NULL DEFAULT 1,
        waste REAL NOT NULL DEFAULT 0,
        pattern_notes TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        assigned_to TEXT,
        required_date TEXT,
        progress REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        currency_id INTEGER REFERENCES currencies(id),
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        payee TEXT,
        supplier_id INTEGER REFERENCES suppliers(id),
        expense_date TEXT NOT NULL,
        note TEXT,
        receipt_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER,
        action TEXT NOT NULL,
        summary TEXT NOT NULL,
        metadata TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX idx_audit_logs_created ON audit_logs(created_at)',
    );

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}
