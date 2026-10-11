import '../../core/errors/result.dart';
import '../../data/models/audit_log_model.dart';

abstract class AuditRepository {
  Future<Result<void>> log({
    required String entityType,
    int? entityId,
    required String action,
    required String summary,
    String? metadata,
    String? createdBy,
  });

  Future<Result<List<AuditLogModel>>> getForEntity({
    required String entityType,
    required int entityId,
    int limit = 50,
  });

  Future<Result<List<AuditLogModel>>> getRecent({int limit = 50});
}
