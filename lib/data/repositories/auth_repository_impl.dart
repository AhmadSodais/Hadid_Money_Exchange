import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/security/app_permissions.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/auth_models.dart';

class AuthRepositoryImpl implements AuthRepository {
  Database get _db => AppDatabase.instance;

  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  Future<List<String>> _permissionsForRole(int roleId) async {
    final rows = await _db.query(
      'role_permissions',
      columns: ['permission_key'],
      where: 'role_id = ?',
      whereArgs: [roleId],
    );
    return rows.map((r) => r['permission_key'] as String).toList();
  }

  Future<AppUserModel> _userFromRow(Map<String, Object?> row) async {
    final roleId = row['role_id'] as int;
    final perms = await _permissionsForRole(roleId);
    return AppUserModel.fromMap(row, permissions: perms);
  }

  Future<RoleModel> _roleFromRow(Map<String, Object?> row) async {
    final id = row['id'] as int;
    final perms = await _permissionsForRole(id);
    return RoleModel.fromMap(row, permissions: perms);
  }

  @override
  Future<Result<AppUserModel?>> login(String username, String password) async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT u.*, r.name AS role_name
        FROM app_users u
        LEFT JOIN roles r ON r.id = u.role_id
        WHERE LOWER(u.username) = LOWER(?) AND u.is_active = 1
        LIMIT 1
        ''',
        [username.trim()],
      );
      if (rows.isEmpty) return const Success(null);
      final hash = rows.first['password_hash'] as String;
      if (hash != hashPassword(password)) return const Success(null);
      return Success(await _userFromRow(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Login failed: $e', cause: st));
    }
  }

  @override
  Future<Result<AppUserModel?>> getUserById(int id) async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT u.*, r.name AS role_name
        FROM app_users u
        LEFT JOIN roles r ON r.id = u.role_id
        WHERE u.id = ?
        LIMIT 1
        ''',
        [id],
      );
      if (rows.isEmpty) return const Success(null);
      return Success(await _userFromRow(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load user: $e', cause: st));
    }
  }

  @override
  Future<Result<List<AppUserModel>>> listUsers() async {
    try {
      final rows = await _db.rawQuery('''
        SELECT u.*, r.name AS role_name
        FROM app_users u
        LEFT JOIN roles r ON r.id = u.role_id
        ORDER BY u.display_name COLLATE NOCASE
      ''');
      final users = <AppUserModel>[];
      for (final row in rows) {
        users.add(await _userFromRow(row));
      }
      return Success(users);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to list users: $e', cause: st));
    }
  }

  @override
  Future<Result<AppUserModel>> createUser({
    required String username,
    required String password,
    required String displayName,
    required int roleId,
    int? employeeId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final id = await _db.insert('app_users', {
        'username': username.trim(),
        'password_hash': hashPassword(password),
        'display_name': displayName.trim(),
        'role_id': roleId,
        'employee_id': employeeId,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      final user = await getUserById(id);
      return user.when(
        success: (u) => Success(u!),
        failure: (f) => FailureResult(f),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to create user: $e', cause: st));
    }
  }

  @override
  Future<Result<AppUserModel>> updateUser({
    required int id,
    String? username,
    String? password,
    String? displayName,
    int? roleId,
    int? employeeId,
    bool? isActive,
  }) async {
    try {
      final map = <String, Object?>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (username != null) map['username'] = username.trim();
      if (password != null && password.trim().isNotEmpty) {
        map['password_hash'] = hashPassword(password);
      }
      if (displayName != null) map['display_name'] = displayName.trim();
      if (roleId != null) map['role_id'] = roleId;
      if (employeeId != null) map['employee_id'] = employeeId;
      if (isActive != null) map['is_active'] = isActive ? 1 : 0;

      await _db.update('app_users', map, where: 'id = ?', whereArgs: [id]);
      final user = await getUserById(id);
      return user.when(
        success: (u) {
          if (u == null) {
            return const FailureResult(NotFoundFailure('User not found.'));
          }
          return Success(u);
        },
        failure: (f) => FailureResult(f),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to update user: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> deleteUser(int id) async {
    try {
      await _db.delete('app_users', where: 'id = ?', whereArgs: [id]);
      return const Success(null);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to delete user: $e', cause: st));
    }
  }

  @override
  Future<Result<List<RoleModel>>> listRoles() async {
    try {
      final rows = await _db.query('roles', orderBy: 'name COLLATE NOCASE');
      final roles = <RoleModel>[];
      for (final row in rows) {
        roles.add(await _roleFromRow(row));
      }
      return Success(roles);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to list roles: $e', cause: st));
    }
  }

  @override
  Future<Result<RoleModel>> getRoleById(int id) async {
    try {
      final rows = await _db.query('roles', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Role not found.'));
      }
      return Success(await _roleFromRow(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load role: $e', cause: st));
    }
  }

  @override
  Future<Result<RoleModel>> createRole({
    required String name,
    String? description,
    List<String>? permissions,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final id = await _db.insert('roles', {
        'name': name.trim(),
        'description': description?.trim(),
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });
      // Default: full access for new roles.
      final keys = permissions ?? AppPermissions.all;
      await setRolePermissions(id, keys);
      return getRoleById(id);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to create role: $e', cause: st));
    }
  }

  @override
  Future<Result<RoleModel>> updateRole({
    required int id,
    String? name,
    String? description,
    List<String>? permissions,
  }) async {
    try {
      final map = <String, Object?>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (name != null) map['name'] = name.trim();
      if (description != null) map['description'] = description.trim();
      await _db.update('roles', map, where: 'id = ?', whereArgs: [id]);
      if (permissions != null) {
        await setRolePermissions(id, permissions);
      }
      return getRoleById(id);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to update role: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> deleteRole(int id) async {
    try {
      final role = await getRoleById(id);
      if (role is FailureResult<RoleModel>) return FailureResult(role.failure);
      final r = (role as Success<RoleModel>).value;
      if (r.isSystem) {
        return const FailureResult(
          ValidationFailure('System roles cannot be deleted.'),
        );
      }
      final users = await _db.query(
        'app_users',
        where: 'role_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (users.isNotEmpty) {
        return const FailureResult(
          ValidationFailure('Role is assigned to users and cannot be deleted.'),
        );
      }
      await _db.delete('roles', where: 'id = ?', whereArgs: [id]);
      return const Success(null);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to delete role: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> setRolePermissions(
    int roleId,
    List<String> permissions,
  ) async {
    try {
      await _db.delete(
        'role_permissions',
        where: 'role_id = ?',
        whereArgs: [roleId],
      );
      final batch = _db.batch();
      for (final key in permissions.toSet()) {
        batch.insert('role_permissions', {
          'role_id': roleId,
          'permission_key': key,
        });
      }
      await batch.commit(noResult: true);
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update permissions: $e', cause: st),
      );
    }
  }

  Future<String?> _setting(String key) async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['value'] as String?)?.trim();
  }

  Future<void> _putSetting(String key, String value) async {
    final now = DateTime.now().toIso8601String();
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _administratorRoleId() async {
    final roles = await _db.query(
      'roles',
      where: 'name = ?',
      whereArgs: ['Administrator'],
      limit: 1,
    );
    if (roles.isNotEmpty) return roles.first['id'] as int;
    final now = DateTime.now().toIso8601String();
    final id = await _db.insert('roles', {
      'name': 'Administrator',
      'description': 'Full access to all sections',
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    });
    await setRolePermissions(id, AppPermissions.all);
    return id;
  }

  @override
  Future<bool> isAuthEnabled() async {
    final v = await _setting(AppConstants.settingAuthEnabled);
    return v == '1' || v?.toLowerCase() == 'true';
  }

  @override
  Future<Result<AppUserModel>> enableAuth({
    required String username,
    required String password,
    required String displayName,
    required String recoveryCode,
    int? roleId,
  }) async {
    try {
      final u = username.trim();
      final p = password.trim();
      final d = displayName.trim().isEmpty ? u : displayName.trim();
      final recovery = recoveryCode.trim();
      if (u.isEmpty || p.isEmpty || recovery.isEmpty) {
        return const FailureResult(
          ValidationFailure('auth.setupIncomplete'),
        );
      }
      if (p.length < 4) {
        return const FailureResult(
          ValidationFailure('auth.passwordTooShort'),
        );
      }
      if (recovery.length < 4) {
        return const FailureResult(
          ValidationFailure('auth.recoveryTooShort'),
        );
      }

      final resolvedRoleId = roleId ?? await _administratorRoleId();
      final existing = await _db.query(
        'app_users',
        where: 'LOWER(username) = LOWER(?)',
        whereArgs: [u],
        limit: 1,
      );

      late int userId;
      final now = DateTime.now().toIso8601String();
      if (existing.isEmpty) {
        userId = await _db.insert('app_users', {
          'username': u,
          'password_hash': hashPassword(p),
          'display_name': d,
          'role_id': resolvedRoleId,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        userId = existing.first['id'] as int;
        await _db.update(
          'app_users',
          {
            'password_hash': hashPassword(p),
            'display_name': d,
            'role_id': resolvedRoleId,
            'is_active': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
      }

      await _putSetting(AppConstants.settingAuthEnabled, '1');
      await _putSetting(
        AppConstants.settingAuthRecoveryHash,
        hashPassword(recovery),
      );

      final user = await getUserById(userId);
      if (user is FailureResult<AppUserModel?>) {
        return FailureResult(user.failure);
      }
      final created = (user as Success<AppUserModel?>).value;
      if (created == null) {
        return const FailureResult(
          DatabaseFailure('Failed to load admin user.'),
        );
      }
      return Success(created);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to enable auth: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<AppUserModel>> enableAuthForExistingUser({
    required int userId,
    required String recoveryCode,
    int? roleId,
    String? newPassword,
  }) async {
    try {
      final recovery = recoveryCode.trim();
      if (recovery.isEmpty) {
        return const FailureResult(
          ValidationFailure('auth.setupIncomplete'),
        );
      }
      if (recovery.length < 4) {
        return const FailureResult(
          ValidationFailure('auth.recoveryTooShort'),
        );
      }
      final pwd = newPassword?.trim();
      if (pwd != null && pwd.isNotEmpty && pwd.length < 4) {
        return const FailureResult(
          ValidationFailure('auth.passwordTooShort'),
        );
      }

      final rows = await _db.query(
        'app_users',
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const FailureResult(
          ValidationFailure('auth.userNotFound'),
        );
      }

      final resolvedRoleId = roleId ?? await _administratorRoleId();
      final now = DateTime.now().toIso8601String();
      final updates = <String, Object?>{
        'role_id': resolvedRoleId,
        'is_active': 1,
        'updated_at': now,
      };
      if (pwd != null && pwd.isNotEmpty) {
        updates['password_hash'] = hashPassword(pwd);
      }
      await _db.update(
        'app_users',
        updates,
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _putSetting(AppConstants.settingAuthEnabled, '1');
      await _putSetting(
        AppConstants.settingAuthRecoveryHash,
        hashPassword(recovery),
      );

      final user = await getUserById(userId);
      if (user is FailureResult<AppUserModel?>) {
        return FailureResult(user.failure);
      }
      final loaded = (user as Success<AppUserModel?>).value;
      if (loaded == null) {
        return const FailureResult(
          DatabaseFailure('Failed to load user.'),
        );
      }
      return Success(loaded);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to enable auth: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> disableAuth() async {
    try {
      await _putSetting(AppConstants.settingAuthEnabled, '0');
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to disable auth: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> resetPasswordWithRecovery({
    required String recoveryCode,
    required String newPassword,
    String? username,
  }) async {
    try {
      if (!await isAuthEnabled()) {
        return const FailureResult(
          ValidationFailure('auth.notEnabled'),
        );
      }
      final stored = await _setting(AppConstants.settingAuthRecoveryHash);
      if (stored == null || stored.isEmpty) {
        return const FailureResult(
          ValidationFailure('auth.recoveryNotSet'),
        );
      }
      if (stored != hashPassword(recoveryCode.trim())) {
        return const FailureResult(
          ValidationFailure('auth.recoveryInvalid'),
        );
      }
      final pwd = newPassword.trim();
      if (pwd.length < 4) {
        return const FailureResult(
          ValidationFailure('auth.passwordTooShort'),
        );
      }

      Map<String, Object?>? row;
      if (username != null && username.trim().isNotEmpty) {
        final rows = await _db.query(
          'app_users',
          where: 'LOWER(username) = LOWER(?)',
          whereArgs: [username.trim()],
          limit: 1,
        );
        if (rows.isNotEmpty) row = rows.first;
      }
      if (row == null) {
        // Prefer Administrator role user, else first active user.
        final rows = await _db.rawQuery('''
          SELECT u.* FROM app_users u
          LEFT JOIN roles r ON r.id = u.role_id
          WHERE u.is_active = 1
          ORDER BY CASE WHEN r.name = 'Administrator' THEN 0 ELSE 1 END, u.id
          LIMIT 1
        ''');
        if (rows.isEmpty) {
          return const FailureResult(
            NotFoundFailure('auth.noUsers'),
          );
        }
        row = rows.first;
      }

      await _db.update(
        'app_users',
        {
          'password_hash': hashPassword(pwd),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to reset password: $e', cause: st),
      );
    }
  }
}
