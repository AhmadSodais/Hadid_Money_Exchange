import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import 'firebase_config.dart';
import 'firebase_exceptions.dart';
import 'sync_error_messages.dart';

/// Firebase Auth session for RTDB REST (`?auth=<idToken>`).
///
/// Uses Identity Toolkit REST (no `firebase_auth` package) so Windows
/// desktop works the same as the existing RTDB HTTP client.
abstract final class FirebaseAuthSession {
  static const _keyUid = 'firebase_auth_uid';
  static const _keyEmail = 'firebase_auth_email';
  static const _keyIdToken = 'firebase_id_token';
  static const _keyRefresh = 'firebase_refresh_token';
  static const _keyExpiresAt = 'firebase_token_expires_at_ms';

  static String? _uid;
  static String? _email;
  static String? _idToken;
  static String? _refreshToken;
  static int? _expiresAtMs;

  static String? get uid => _uid;
  static String? get email => _email;
  static bool get isSignedIn =>
      (_uid?.isNotEmpty == true) && (_idToken?.isNotEmpty == true);

  static Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final rows = await db.query(
        'app_settings',
        where: 'key IN (?, ?, ?, ?, ?)',
        whereArgs: [_keyUid, _keyEmail, _keyIdToken, _keyRefresh, _keyExpiresAt],
      );
      for (final row in rows) {
        final key = row['key'] as String?;
        final value = (row['value'] as String?)?.trim();
        if (value == null || value.isEmpty) continue;
        switch (key) {
          case _keyUid:
            _uid = value;
          case _keyEmail:
            _email = value;
          case _keyIdToken:
            _idToken = value;
          case _keyRefresh:
            _refreshToken = value;
          case _keyExpiresAt:
            _expiresAtMs = int.tryParse(value);
        }
      }
    } catch (e) {
      debugPrint('[FirebaseAuth] load failed: $e');
    }
  }

  /// Sign in with email/password. Requires [FirebaseConfig.apiKey].
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final apiKey = FirebaseConfig.apiKey;
    if (apiKey.isEmpty) {
      throw FirebaseSyncException('auth_config');
    }
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword'
      '?key=$apiKey',
    );
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    await _applyAuthResponse(res, fallbackEmail: email.trim());
  }

  /// Create account (email/password), then persist session.
  static Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final apiKey = FirebaseConfig.apiKey;
    if (apiKey.isEmpty) {
      throw FirebaseSyncException('auth_config');
    }
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
    );
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    await _applyAuthResponse(res, fallbackEmail: email.trim());
  }

  static Future<void> signOut() async {
    _uid = null;
    _email = null;
    _idToken = null;
    _refreshToken = null;
    _expiresAtMs = null;
    final db = AppDatabase.instance;
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?, ?, ?, ?)',
      whereArgs: [_keyUid, _keyEmail, _keyIdToken, _keyRefresh, _keyExpiresAt],
    );
  }

  /// Returns a valid ID token, refreshing when expired / near expiry.
  static Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (_idToken == null || _idToken!.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiringSoon =
        _expiresAtMs != null && now >= (_expiresAtMs! - 5 * 60 * 1000);
    if (forceRefresh || expiringSoon) {
      final ok = await _refresh();
      if (!ok) return null;
    }
    return _idToken;
  }

  static Future<bool> _refresh() async {
    final apiKey = FirebaseConfig.apiKey;
    final refresh = _refreshToken;
    if (apiKey.isEmpty || refresh == null || refresh.isEmpty) return false;
    try {
      final uri = Uri.parse(
        'https://securetoken.googleapis.com/v1/token?key=$apiKey',
      );
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=refresh_token&refresh_token='
                '${Uri.encodeQueryComponent(refresh)}',
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[FirebaseAuth] refresh failed: ${res.statusCode} ${res.body}');
        return false;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      _idToken = map['id_token'] as String?;
      _refreshToken = (map['refresh_token'] as String?) ?? _refreshToken;
      _uid = (map['user_id'] as String?) ?? _uid;
      final expiresIn = int.tryParse('${map['expires_in'] ?? 3600}') ?? 3600;
      _expiresAtMs =
          DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
      await _persist();
      return _idToken?.isNotEmpty == true;
    } catch (e) {
      debugPrint('[FirebaseAuth] refresh error: $e');
      return false;
    }
  }

  static Future<void> _applyAuthResponse(
    http.Response res, {
    required String fallbackEmail,
  }) async {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[FirebaseAuth] auth failed: ${res.statusCode} ${res.body}');
      throw FirebaseSyncException(_mapAuthHttpError(res));
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    _idToken = map['idToken'] as String?;
    _refreshToken = map['refreshToken'] as String?;
    _uid = map['localId'] as String?;
    _email = (map['email'] as String?) ?? fallbackEmail;
    final expiresIn = int.tryParse('${map['expiresIn'] ?? 3600}') ?? 3600;
    _expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
    if (_idToken == null || _uid == null) {
      throw FirebaseSyncException('auth');
    }
    await _persist();
  }

  static String _mapAuthHttpError(http.Response res) {
    try {
      final map = jsonDecode(res.body);
      final msg = (map is Map ? map['error'] : null);
      final message = msg is Map ? '${msg['message'] ?? ''}' : '';
      final m = message.toUpperCase();
      if (m.contains('INVALID_PASSWORD') ||
          m.contains('INVALID_LOGIN_CREDENTIALS') ||
          m.contains('EMAIL_NOT_FOUND') ||
          m.contains('INVALID_EMAIL')) {
        return 'auth_credentials';
      }
      if (m.contains('EMAIL_EXISTS')) return 'auth_email_exists';
      if (m.contains('WEAK_PASSWORD')) return 'auth_weak_password';
      if (m.contains('USER_DISABLED')) return 'auth_disabled';
      if (m.contains('TOO_MANY_ATTEMPTS')) return 'auth_rate_limited';
      if (m.contains('API_KEY') || m.contains('API key')) return 'auth_config';
    } catch (_) {}
    return SyncErrorMessages.codeForHttp(res.statusCode);
  }

  static Future<void> _persist() async {
    final db = AppDatabase.instance;
    final now = DateTime.now().toIso8601String();
    Future<void> put(String key, String? value) async {
      if (value == null || value.isEmpty) {
        await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
        return;
      }
      await db.insert(
        'app_settings',
        {'key': key, 'value': value, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await put(_keyUid, _uid);
    await put(_keyEmail, _email);
    await put(_keyIdToken, _idToken);
    await put(_keyRefresh, _refreshToken);
    await put(
      _keyExpiresAt,
      _expiresAtMs?.toString(),
    );
  }
}
