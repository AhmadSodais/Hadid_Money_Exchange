import 'package:easy_localization/easy_localization.dart';

/// Maps raw sync / server errors to short, user-facing messages.
///
/// Technical details stay in logs; the UI only shows predefined copy.
abstract final class SyncErrorMessages {
  /// Localized message for a stored or live error string.
  static String display(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'sync.errors.generic'.tr();
    }
    return messageKey(raw).tr();
  }

  /// Translation key for [raw] (for banners that call `.tr()` themselves).
  static String messageKey(String? raw) => _translationKey(codeFor(raw));

  /// Stable short code stored in the queue / lastError.
  static String codeFor(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'generic';
    final t = raw.toLowerCase().trim();

    switch (t) {
      case 'permission':
      case 'permission_denied':
      case 'permissiondenied':
        return 'permission';
      case 'forbidden':
        return 'forbidden';
      case 'offline':
      case 'unreachable':
        return 'unreachable';
      case 'timeout':
        return 'timeout';
      case 'conflict':
        return 'conflict';
      case 'server':
      case 'server_error':
        return 'server';
      case 'not_found':
      case 'notfound':
        return 'not_found';
      case 'request_rejected':
      case 'requestrejected':
        return 'request_rejected';
      case 'busy':
        return 'busy';
      case 'disabled':
        return 'disabled';
      case 'auth':
      case 'auth_required':
      case 'authrequired':
        return 'auth_required';
      case 'auth_credentials':
      case 'authcredentials':
        return 'auth_credentials';
      case 'auth_email_exists':
      case 'authemailexists':
        return 'auth_email_exists';
      case 'auth_weak_password':
      case 'authweakpassword':
        return 'auth_weak_password';
      case 'auth_disabled':
      case 'authdisabled':
        return 'auth_disabled';
      case 'auth_rate_limited':
      case 'authratelimited':
        return 'auth_rate_limited';
      case 'auth_config':
      case 'authconfig':
        return 'auth_config';
      case 'auth_expired':
        return 'auth_expired';
      case 'rate_limited':
        return 'rate_limited';
      case 'other_device':
        return 'other_device';
      case 'pending_jobs':
        return 'pending_jobs';
      case 'unknown':
      case 'generic':
        return 'generic';
    }

    if (t.contains('permission denied') ||
        t.contains('permission_denied') ||
        t.contains('http 401') ||
        t.contains('unauthorized') ||
        (RegExp(r'\b401\b').hasMatch(t) && t.contains('permission'))) {
      return 'permission';
    }
    if (t.contains('http 403') || t.contains('forbidden')) {
      return 'forbidden';
    }
    if (t.contains('http 404') || t.contains('not found')) {
      return 'not_found';
    }
    if (RegExp(r'http 5\d\d').hasMatch(t) ||
        t.contains('internal server') ||
        t.contains('bad gateway') ||
        t.contains('service unavailable')) {
      return 'server';
    }
    if (RegExp(r'http 4\d\d').hasMatch(t)) {
      return 'request_rejected';
    }
    if (t.contains('remote record changed') || t.contains('conflict')) {
      return 'conflict';
    }
    if (t.contains('socket') ||
        t.contains('failed host lookup') ||
        t.contains('network is unreachable') ||
        t.contains('connection refused') ||
        t.contains('connection reset') ||
        t.contains('no address associated') ||
        t.contains('clientexception') ||
        t.contains('server unreachable') ||
        t.contains('offline') ||
        t.contains('unreachable')) {
      return 'unreachable';
    }
    if (t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('deadline exceeded')) {
      return 'timeout';
    }
    if (t.contains('permission')) return 'permission';
    if (t.contains('unknown sync failure')) return 'generic';
    return 'generic';
  }

  static String _translationKey(String code) => switch (code) {
        'permission' => 'sync.errors.permissionDenied',
        'forbidden' => 'sync.errors.forbidden',
        'unreachable' => 'sync.errors.unreachable',
        'timeout' => 'sync.errors.timeout',
        'conflict' => 'sync.errors.conflict',
        'server' => 'sync.errors.server',
        'not_found' => 'sync.errors.notFound',
        'request_rejected' => 'sync.errors.requestRejected',
        'busy' => 'sync.errors.busy',
        'disabled' => 'sync.errors.disabled',
        'auth_required' => 'sync.errors.authRequired',
        'auth_credentials' => 'sync.errors.authCredentials',
        'auth_email_exists' => 'sync.errors.authEmailExists',
        'auth_weak_password' => 'sync.errors.authWeakPassword',
        'auth_disabled' => 'sync.errors.authDisabled',
        'auth_rate_limited' => 'sync.errors.authRateLimited',
        'auth_config' => 'sync.errors.authConfig',
        'auth_expired' => 'sync.errors.authExpired',
        'rate_limited' => 'sync.errors.rateLimited',
        'other_device' => 'sync.errors.otherDevice',
        'pending_jobs' => 'sync.errors.pendingJobs',
        _ => 'sync.errors.generic',
      };

  /// Maps an HTTP status from ping/REST into a stable stored code.
  static String codeForHttp(int status) {
    if (status == 401) return 'permission';
    if (status == 403) return 'forbidden';
    if (status == 404) return 'not_found';
    if (status == 408) return 'timeout';
    if (status == 429) return 'rate_limited';
    if (status >= 500) return 'server';
    if (status >= 400) return 'request_rejected';
    return 'generic';
  }

  /// Timeouts, rate limits and server-side failures are worth retrying;
  /// other 4xx answers mean the server rejected the data itself.
  static bool isTemporaryHttp(int status) =>
      status == 408 || status == 423 || status == 429 || status >= 500;

  /// Removes login tokens from text before it is logged or shown.
  static String redact(String text) => text
      .replaceAll(RegExp(r'auth=[^&\s"\x27]+'), 'auth=***')
      .replaceAllMapped(
        RegExp(
          r'(id_?token|refresh_?token)("?\s*[:=]\s*"?)[^&\s",}]+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}${m[2]}***',
      );
}
