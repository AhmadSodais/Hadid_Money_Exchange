import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_auth_session.dart';
import 'firebase_config.dart';
import 'firebase_exceptions.dart';
import 'sync_error_messages.dart';

/// Thin REST client for the remote Realtime Database (Windows-friendly).
///
/// Paths are scoped to `users/{uid}/{root}/...` and every request includes
/// `?auth=<Firebase ID token>` so RTDB Security Rules can enforce ownership.
/// The token is renewed before it expires and never appears in errors/logs.
class FirebaseRtdbClient {
  FirebaseRtdbClient({
    http.Client? client,
    String? databaseUrl,
    String? root,
  })  : _client = client ?? http.Client(),
        databaseUrl = databaseUrl ?? FirebaseConfig.databaseUrl,
        root = root ?? FirebaseConfig.root;

  final http.Client _client;
  final String databaseUrl;
  final String root;

  static const _writeTimeout = Duration(seconds: 20);

  Future<Uri> _uri(
    String path, {
    bool forceRefresh = false,
    Map<String, String> query = const {},
  }) async {
    final uid = FirebaseAuthSession.uid;
    if (uid == null || uid.isEmpty || !FirebaseAuthSession.isSignedIn) {
      throw FirebaseSyncException('auth_required', temporary: true);
    }
    final token =
        await FirebaseAuthSession.getIdToken(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) {
      throw FirebaseSyncException('auth_expired', temporary: true);
    }
    final cleaned = path.startsWith('/') ? path.substring(1) : path;
    final basePath = cleaned.isEmpty
        ? '$databaseUrl/users/$uid/$root.json'
        : '$databaseUrl/users/$uid/$root/$cleaned.json';
    return Uri.parse(basePath)
        .replace(queryParameters: {...query, 'auth': token});
  }

  /// Sends a request; on an expired-login 401 renews the token and retries
  /// once. Throws [FirebaseSyncException] for any non-2xx answer.
  Future<http.Response> _send(
    String method,
    String path,
    Future<http.Response> Function(Uri uri) request, {
    Duration timeout = _writeTimeout,
    Map<String, String> query = const {},
  }) async {
    var res = await _guard(
      () async => request(await _uri(path, query: query)).timeout(timeout),
    );
    if (res.statusCode == 401 && _isAuthTokenProblem(res.body)) {
      res = await _guard(
        () async => request(
          await _uri(path, forceRefresh: true, query: query),
        ).timeout(timeout),
      );
    }
    _ensureOk(method, path.isEmpty ? root : path, res);
    return res;
  }

  /// Re-throws transport errors with any token stripped from the message.
  Future<http.Response> _guard(Future<http.Response> Function() run) async {
    try {
      return await run();
    } on FirebaseSyncException {
      rethrow;
    } catch (e) {
      if (FirebaseSyncException.isTemporary(e)) {
        debugPrint('[Sync] network: ${SyncErrorMessages.redact('$e')}');
        throw FirebaseSyncException(
          e is TimeoutException ? 'timeout' : 'unreachable',
          temporary: true,
        );
      }
      rethrow;
    }
  }

  /// GET that accepts both object maps and array collections from RTDB.
  Future<Object?> getRaw(
    String path, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final res = await _send('GET', path, _client.get, timeout: timeout);
    if (res.body.isEmpty || res.body == 'null') return null;
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>?> get(String path) async {
    final decoded = await getRaw(path, timeout: _writeTimeout);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> put(String path, Map<String, dynamic> data) async {
    final body = jsonEncode(data);
    await _send(
      'PUT',
      path,
      (uri) => _client.put(uri, headers: _json, body: body),
    );
  }

  Future<void> patch(String path, Map<String, dynamic> data) async {
    final body = jsonEncode(data);
    await _send(
      'PATCH',
      path,
      (uri) => _client.patch(uri, headers: _json, body: body),
    );
  }

  /// Multi-path update at the app root: every `path → value` in [updates]
  /// is applied in one all-or-nothing write (`null` deletes the path).
  Future<void> updateMany(
    Map<String, Object?> updates, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = jsonEncode(updates);
    await _send(
      'PATCH',
      '',
      (uri) => _client.patch(uri, headers: _json, body: body),
      timeout: timeout,
    );
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path, _client.delete);
  }

  /// Deletes this user's app root (`/users/{uid}/{root}.json`).
  Future<void> deleteRoot() async {
    await _send(
      'DELETE',
      '',
      _client.delete,
      timeout: const Duration(seconds: 60),
    );
  }

  /// Null when signed in and the server is reachable; otherwise an error code.
  Future<String?> pingError() async {
    try {
      await _send(
        'GET',
        '',
        _client.get,
        timeout: const Duration(seconds: 8),
        query: const {'shallow': 'true'},
      );
      return null;
    } on FirebaseSyncException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('[Sync] ping failed: ${SyncErrorMessages.redact('$e')}');
      return 'unreachable';
    }
  }

  Future<bool> ping() async => (await pingError()) == null;

  static const _json = {'Content-Type': 'application/json'};

  static bool _isAuthTokenProblem(String body) {
    final b = body.toLowerCase();
    return b.contains('expired') ||
        b.contains('invalid token') ||
        b.contains('could not parse auth token') ||
        b.contains('unauthorized request');
  }

  void _ensureOk(String method, String path, http.Response res) {
    final status = res.statusCode;
    if (status >= 200 && status < 300) return;
    debugPrint(
      '[Sync] $method $path HTTP $status: '
      '${SyncErrorMessages.redact(_trimBody(res.body))}',
    );
    if (status == 401 && _isAuthTokenProblem(res.body)) {
      throw FirebaseSyncException('auth_expired', temporary: true);
    }
    throw FirebaseSyncException(
      SyncErrorMessages.codeForHttp(status),
      temporary: SyncErrorMessages.isTemporaryHttp(status),
    );
  }

  static String _trimBody(String body) {
    final t = body.trim();
    if (t.length <= 240) return t;
    return '${t.substring(0, 240)}…';
  }

  void dispose() => _client.close();
}
