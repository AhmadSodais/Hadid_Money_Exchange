import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/security/permissions.dart';
import 'read_models.dart';

/// Appends audit events. The table is append-only (enforced by triggers).
///
/// Never pass passwords, passcodes, recovery codes, or keys in [before] /
/// [after].
abstract final class AuditWriter {
  static Future<void> write(
    DatabaseExecutor db, {
    required Actor? actor,
    required String action,
    required String entityType,
    String? entityId,
    int? transactionId,
    bool success = true,
    String? reason,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? message,
  }) async {
    await db.insert('audit_logs', {
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'actor_user_id': actor?.userId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'transaction_id': transactionId,
      'outcome': success ? 'success' : 'failure',
      'reason': reason,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'message': message,
    });
  }

  static Future<List<AuditEntry>> list(
    DatabaseExecutor db, {
    int limit = 200,
    int offset = 0,
    String? entityType,
  }) async {
    final rows = await db.rawQuery('''
      SELECT a.*, u.display_name AS actor_name
      FROM audit_logs a LEFT JOIN users u ON u.id = a.actor_user_id
      ${entityType == null ? '' : 'WHERE a.entity_type = ?'}
      ORDER BY a.id DESC LIMIT ? OFFSET ?
    ''', [?entityType, limit, offset]);
    return rows.map(AuditEntry.fromRow).toList();
  }

  static Future<int> count(DatabaseExecutor db, {String? entityType}) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM audit_logs ${entityType == null ? '' : 'WHERE entity_type = ?'}',
      [?entityType],
    );
    return rows.first['n'] as int;
  }
}
