import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../security/app_permissions.dart';

/// General-store product fields + roles / users / permissions.
abstract final class MigrationV24 {
  static Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db,
      'products',
      'barcode',
      'ALTER TABLE products ADD COLUMN barcode TEXT',
    );
    await _addColumnIfMissing(
      db,
      'products',
      'brand',
      'ALTER TABLE products ADD COLUMN brand TEXT',
    );
    await _addColumnIfMissing(
      db,
      'products',
      'description',
      'ALTER TABLE products ADD COLUMN description TEXT',
    );
    await _addColumnIfMissing(
      db,
      'products',
      'expiration_date',
      'ALTER TABLE products ADD COLUMN expiration_date TEXT',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_expiration '
      'ON products(expiration_date)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS role_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        permission_key TEXT NOT NULL,
        UNIQUE(role_id, permission_key)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        display_name TEXT NOT NULL,
        role_id INTEGER NOT NULL REFERENCES roles(id),
        employee_id INTEGER REFERENCES employees(id),
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_role_permissions_role '
      'ON role_permissions(role_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_app_users_username '
      'ON app_users(username)',
    );

    final now = DateTime.now().toIso8601String();

    final existingRoles = await db.query(
      'roles',
      where: 'name = ?',
      whereArgs: ['Administrator'],
      limit: 1,
    );
    int roleId;
    if (existingRoles.isEmpty) {
      roleId = await db.insert('roles', {
        'name': 'Administrator',
        'description': 'Full access to all sections',
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      roleId = existingRoles.first['id'] as int;
    }

    for (final key in AppPermissions.all) {
      await db.insert(
        'role_permissions',
        {'role_id': roleId, 'permission_key': key},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Admin user is created only when the store owner enables login (Settings).
    // Do not seed username/password here.

    final settings = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['store_type'],
      limit: 1,
    );
    if (settings.isEmpty) {
      try {
        await db.insert('app_settings', {
          'key': 'store_type',
          'value': StoreTypes.general,
          'updated_at': now,
        });
      } catch (_) {
        // Ignore if schema differs.
      }
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String sql,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final names = {for (final r in cols) r['name'] as String};
    if (!names.contains(column)) {
      await db.execute(sql);
    }
  }
}
