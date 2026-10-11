import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Shared sync/auth exception — [message] is a stable error code.
///
/// [temporary] errors (offline, timeout, server busy, expired login, rate
/// limit) leave the job PENDING and stop the run; permanent ones mean the
/// server rejected the data itself.
class FirebaseSyncException implements Exception {
  FirebaseSyncException(this.message, {this.temporary = false});

  final String message;
  final bool temporary;

  @override
  String toString() => message;

  /// Whether [error] is a temporary problem worth retrying later.
  static bool isTemporary(Object error) {
    if (error is FirebaseSyncException) return error.temporary;
    return error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is http.ClientException;
  }
}
