import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Employees, salary history, and movement attribution.
abstract final class MigrationV9 {
  static Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        full_name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        role TEXT,
        department TEXT,
        hire_date TEXT,
        base_salary REAL NOT NULL DEFAULT 0,
        salary_currency TEXT NOT NULL DEFAULT 'AFN',
        payment_cycle TEXT NOT NULL DEFAULT 'monthly',
        bank_account TEXT,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_salaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL
          REFERENCES employees(id) ON DELETE CASCADE,
        period_label TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'AFN',
        paid_at TEXT NOT NULL,
        payment_method TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employees_name ON employees(full_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employee_salaries_emp '
      'ON employee_salaries(employee_id, paid_at)',
    );

    final info = await db.rawQuery('PRAGMA table_info(stock_movements)');
    final columns = {
      for (final row in info) (row['name'] as String?) ?? '',
    };
    if (!columns.contains('employee_id')) {
      await db.execute(
        'ALTER TABLE stock_movements ADD COLUMN employee_id INTEGER '
        'REFERENCES employees(id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_employee '
        'ON stock_movements(employee_id)',
      );
    }
  }
}
