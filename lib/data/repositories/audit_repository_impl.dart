import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../domain/repositories/audit_repository.dart';
import '../models/audit_log_model.dart';

class AuditRepositoryImpl implements AuditRepository {
  Database get _db => AppDatabase.instance;

  @override
  Future<Result<void>> log({
    required String entityType,
    int? entityId,
    required String action,
    required String summary,
    String? metadata,
    String? createdBy,
  }) async {
    try {
      await _db.insert('audit_logs', {
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'summary': summary,
        'metadata': metadata,
        'created_by': createdBy ?? 'system',
        'created_at': DateTime.now().toIso8601String(),
      });
      return const Success(null);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to write audit log: $e', cause: st));
    }
  }

  @override
  Future<Result<List<AuditLogModel>>> getForEntity({
    required String entityType,
    required int entityId,
    int limit = 50,
  }) async {
    try {
      final rows = await _db.query(
        'audit_logs',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return Success(rows.map(AuditLogModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load audit logs: $e', cause: st));
    }
  }

  @override
  Future<Result<List<AuditLogModel>>> getRecent({int limit = 50}) async {
    try {
      final rows = await _db.query(
        'audit_logs',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return Success(rows.map(AuditLogModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load recent activity: $e', cause: st));
    }
  }
}
