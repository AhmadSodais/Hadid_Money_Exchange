import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../constants/app_constants.dart';
import '../../security/app_permissions.dart';
import '../../../data/repositories/auth_repository_impl.dart';

/// Opt-in local login: auth disabled by default; clear default admin seed.
abstract final class MigrationV26 {
  static const authEnabledKey = AppConstants.settingAuthEnabled;
  static const recoveryHashKey = AppConstants.settingAuthRecoveryHash;

  static Future<void> up(Database db) async {
    final now = DateTime.now().toIso8601String();

    final enabled = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [authEnabledKey],
      limit: 1,
    );
    if (enabled.isEmpty) {
      await db.insert('app_settings', {
        'key': authEnabledKey,
        'value': '0',
        'updated_at': now,
      });
    }

    // Remove the well-known default admin/admin if still present.
    try {
      final defaultHash = AuthRepositoryImpl.hashPassword('admin');
      await db.delete(
        'app_users',
        where: 'LOWER(username) = ? AND password_hash = ?',
        whereArgs: ['admin', defaultHash],
      );
    } catch (_) {}

    // Ensure Administrator role exists (no user until auth is enabled).
    final roles = await db.query(
      'roles',
      where: 'name = ?',
      whereArgs: ['Administrator'],
      limit: 1,
    );
    int roleId;
    if (roles.isEmpty) {
      roleId = await db.insert('roles', {
        'name': 'Administrator',
        'description': 'Full access to all sections',
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      roleId = roles.first['id'] as int;
    }
    for (final key in AppPermissions.all) {
      await db.insert(
        'role_permissions',
        {'role_id': roleId, 'permission_key': key},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
