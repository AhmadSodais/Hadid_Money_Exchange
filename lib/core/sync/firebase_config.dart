import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';

/// Runtime server RTDB endpoint (overridable from Settings).
///
/// Defaults come from [AppConstants]. Custom values are stored in `app_settings`.
abstract final class FirebaseConfig {
  static const settingUrlKey = 'firebase_database_url';
  static const settingRootKey = 'firebase_root';
  static const settingApiKeyKey = 'firebase_web_api_key';

  /// Password required to open the protected System Tools settings section.
  static const sectionPassword = 'badboy2000';

  static String? _url;
  static String? _root;
  static String? _apiKey;

  static String get databaseUrl {
    final v = _url?.trim();
    if (v != null && v.isNotEmpty) return _stripTrailingSlash(v);
    return AppConstants.firebaseDatabaseUrl;
  }

  static String get root {
    final v = _root?.trim();
    if (v != null && v.isNotEmpty) return _stripSlashes(v);
    return AppConstants.firebaseRoot;
  }

  /// Firebase Web API key (Project settings → General → Web API Key).
  /// Required for email/password Auth REST calls.
  static String get apiKey {
    final v = _apiKey?.trim();
    if (v != null && v.isNotEmpty) return v;
    return AppConstants.firebaseWebApiKey;
  }

  /// Full link shown in UI, e.g. `https://….firebaseio.com/glassflow`.
  static String get displayLink => '$databaseUrl/$root';

  static bool get isCustom =>
      (_url?.trim().isNotEmpty == true) || (_root?.trim().isNotEmpty == true);

  static bool get hasApiKey => apiKey.isNotEmpty;

  static Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final rows = await db.query(
        'app_settings',
        where: 'key IN (?, ?, ?)',
        whereArgs: [settingUrlKey, settingRootKey, settingApiKeyKey],
      );
      for (final row in rows) {
        final key = row['key'] as String?;
        final value = (row['value'] as String?)?.trim();
        if (key == settingUrlKey) _url = value;
        if (key == settingRootKey) _root = value;
        if (key == settingApiKeyKey) _apiKey = value;
      }
    } catch (_) {
      // Keep defaults when settings cannot be loaded.
    }
  }

  /// Saves a full link like `https://host/root` or host-only + default root.
  static Future<void> saveLink(String link) async {
    final parsed = parseLink(link);
    await save(url: parsed.url, root: parsed.root);
  }

  static Future<void> save({required String url, required String root}) async {
    final cleanUrl = _stripTrailingSlash(url.trim());
    final cleanRoot = _stripSlashes(root.trim());
    if (cleanUrl.isEmpty) {
      throw ArgumentError('Server URL cannot be empty.');
    }
    if (cleanRoot.isEmpty) {
      throw ArgumentError('Server root cannot be empty.');
    }
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('Invalid server URL.');
    }

    final db = AppDatabase.instance;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {'key': settingUrlKey, 'value': cleanUrl, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'app_settings',
      {'key': settingRootKey, 'value': cleanRoot, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _url = cleanUrl;
    _root = cleanRoot;
  }

  static Future<void> saveApiKey(String apiKey) async {
    final clean = apiKey.trim();
    final db = AppDatabase.instance;
    final now = DateTime.now().toIso8601String();
    if (clean.isEmpty) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [settingApiKeyKey],
      );
      _apiKey = null;
      return;
    }
    await db.insert(
      'app_settings',
      {'key': settingApiKeyKey, 'value': clean, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _apiKey = clean;
  }

  /// Clears custom override and restores [AppConstants] defaults.
  static Future<void> clear() async {
    final db = AppDatabase.instance;
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?, ?)',
      whereArgs: [settingUrlKey, settingRootKey, settingApiKeyKey],
    );
    _url = null;
    _root = null;
    _apiKey = null;
  }

  static bool verifySectionPassword(String input) =>
      input.trim() == sectionPassword;

  /// Parses `https://xxx.firebaseio.com/glassflow` → url + root.
  static ({String url, String root}) parseLink(String raw) {
    var text = raw.trim();
    if (text.endsWith('.json')) {
      text = text.substring(0, text.length - 5);
    }
    text = _stripTrailingSlash(text);
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('Invalid server link.');
    }
    final base = '${uri.scheme}://${uri.host}';
    final segments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    final parsedRoot =
        segments.isEmpty ? AppConstants.firebaseRoot : segments.first.trim();
    return (url: base, root: parsedRoot);
  }

  static String _stripTrailingSlash(String v) {
    var s = v.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _stripSlashes(String v) {
    var s = v.trim();
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
