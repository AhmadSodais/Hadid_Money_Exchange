import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/security/app_lock_crypto.dart';
import '../domain/errors/domain_errors.dart';
import '../domain/security/permissions.dart';
import '../domain/money/decimal.dart';
import 'audit_writer.dart';
import 'ledger_events.dart';

/// Staff accounts, password verification, and permission resolution.
///
/// Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes with a per-user
/// iteration count; plaintext is never stored or logged.
final class SecurityService {
  SecurityService(this._db, this._events);

  final Database _db;
  final LedgerEvents _events;

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

  Future<({String displayName, String? phone})> profile(int userId) async {
    final rows = await _db.query('users', columns: ['display_name', 'phone'], where: 'id = ?', whereArgs: [userId]);
    if (rows.isEmpty) throw const NotFoundError('user.notFound', 'کاربر پیدا نشد.');
    return (displayName: rows.first['display_name'] as String, phone: rows.first['phone'] as String?);
  }

  /// Updates the name shown in the app and the user's own phone number.
  Future<void> updateProfile(int userId, {required String displayName, String? phone, required Actor actor}) async {
    if (actor.userId != userId && !actor.can(Permissions.settingsManage)) {
      throw const AuthorizationError('auth.denied', 'اجازه ویرایش مشخصات این کاربر را ندارید.');
    }
    final name = displayName.trim();
    if (name.isEmpty) {
      throw const ValidationError('user.name', 'نام کاربری الزامی است.', field: 'displayName');
    }
    if (name.length > 60) {
      throw const ValidationError('user.name', 'نام کاربری حداکثر ۶۰ حرف باشد.', field: 'displayName');
    }
    final cleanPhone = phone == null || phone.trim().isEmpty ? null : Decimal.normalizeDigits(phone.trim());
    if (cleanPhone != null && !RegExp(r'^\+?[0-9 \-]{6,20}$').hasMatch(cleanPhone)) {
      throw const ValidationError('user.phone', 'شماره تماس معتبر نیست.', field: 'phone');
    }
    await _db.transaction((txn) async {
      final rows = await txn.query('users', columns: ['display_name', 'phone'], where: 'id = ?', whereArgs: [userId]);
      if (rows.isEmpty) throw const NotFoundError('user.notFound', 'کاربر پیدا نشد.');
      await txn.update(
        'users',
        {'display_name': name, 'phone': cleanPhone, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [userId],
      );
      await AuditWriter.write(txn,
          actor: actor,
          action: 'user.profileUpdate',
          entityType: 'user',
          entityId: '$userId',
          before: {'display_name': rows.first['display_name'], 'phone': rows.first['phone']},
          after: {'display_name': name, 'phone': cleanPhone});
    });
    _events.notify(LedgerChange.reference);
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
