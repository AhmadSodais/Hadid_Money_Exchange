import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/security/app_lock_crypto.dart';
import '../domain/errors/domain_errors.dart';
import '../domain/security/permissions.dart';
import 'audit_writer.dart';

/// Staff accounts, password verification, and permission resolution.
///
/// Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes with a per-user
/// iteration count; plaintext is never stored or logged.
final class SecurityService {
  SecurityService(this._db);

  final Database _db;

  static const int passwordIterations = 120000;
  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 5);
  static const int ownerUserId = 1;

  Future<Actor> actorFor(int userId) async {
    final rows = await _db.rawQuery('''
      SELECT u.id, u.display_name, u.is_active, rp.permission_code
      FROM users u LEFT JOIN role_permissions rp ON rp.role_id = u.role_id
      WHERE u.id = ?
    ''', [userId]);
    if (rows.isEmpty || rows.first['is_active'] != 1) {
      throw const AuthorizationError('auth.inactiveUser', 'کاربر فعال نیست.');
    }
    return Actor(
      userId: userId,
      displayName: rows.first['display_name'] as String,
      permissions: {
        for (final r in rows)
          if (r['permission_code'] != null) r['permission_code'] as String,
      },
    );
  }

  Future<void> setPassword(int userId, String password, Actor actor) async {
    if (actor.userId != userId && !actor.can(Permissions.settingsManage)) {
      throw const AuthorizationError('auth.denied', 'اجازه تغییر رمز این کاربر را ندارید.');
    }
    if (password.length < 6) {
      throw const ValidationError('password.short', 'رمز عبور باید حداقل ۶ کاراکتر باشد.',
          field: 'password');
    }
    final salt = AppLockCrypto.newSalt();
    final hash = await _hash(password, salt, passwordIterations);
    await _db.transaction((txn) async {
      await txn.update('users', {
        'password_hash': hash,
        'password_salt': salt,
        'password_iterations': passwordIterations,
        'failed_attempts': 0,
        'locked_until': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ?', whereArgs: [userId]);
      await AuditWriter.write(txn,
          actor: actor, action: 'user.passwordChange', entityType: 'user', entityId: '$userId');
    });
  }

  /// Returns the actor on success; throws on invalid credentials or lockout.
  Future<Actor> login(String username, String password) async {
    final rows = await _db.query('users',
        where: 'username = ? AND is_active = 1', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) {
      throw const AuthorizationError('auth.invalid', 'نام کاربری یا رمز عبور نادرست است.');
    }
    final u = rows.first;
    final id = u['id'] as int;
    final lockedUntil = u['locked_until'] as String?;
    if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(DateTime.now().toUtc())) {
      throw const AuthorizationError('auth.locked', 'به دلیل تلاش‌های ناموفق، حساب موقتاً قفل است.');
    }
    final salt = u['password_salt'] as String?;
    final stored = u['password_hash'] as String?;
    if (salt == null || stored == null) {
      throw const AuthorizationError('auth.noPassword', 'برای این کاربر رمز تعیین نشده است.');
    }
    final hash = await _hash(password, salt, u['password_iterations'] as int);
    if (!AppLockCrypto.constantTimeEquals(hash, stored)) {
      final failures = (u['failed_attempts'] as int) + 1;
      await _db.update('users', {
        'failed_attempts': failures >= maxFailedAttempts ? 0 : failures,
        'locked_until': failures >= maxFailedAttempts
            ? DateTime.now().toUtc().add(lockoutDuration).toIso8601String()
            : null,
      }, where: 'id = ?', whereArgs: [id]);
      await AuditWriter.write(_db,
          actor: null,
          action: 'user.login',
          entityType: 'user',
          entityId: '$id',
          success: false);
      throw const AuthorizationError('auth.invalid', 'نام کاربری یا رمز عبور نادرست است.');
    }
    await _db.update('users', {'failed_attempts': 0, 'locked_until': null},
        where: 'id = ?', whereArgs: [id]);
    final actor = await actorFor(id);
    await AuditWriter.write(_db,
        actor: actor, action: 'user.login', entityType: 'user', entityId: '$id');
    return actor;
  }

  static Future<String> _hash(String secret, String salt, int iterations) =>
      Isolate.run(() => AppLockCrypto.hash(secret, salt, iterationCount: iterations));
}
