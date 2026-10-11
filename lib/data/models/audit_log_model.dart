import 'package:equatable/equatable.dart';

class AuditLogModel extends Equatable {
  const AuditLogModel({
    required this.id,
    required this.entityType,
    this.entityId,
    required this.action,
    required this.summary,
    this.metadata,
    this.createdBy,
    required this.createdAt,
  });

  final int id;
  final String entityType;
  final int? entityId;
  final String action;
  final String summary;
  final String? metadata;
  final String? createdBy;
  final DateTime createdAt;

  factory AuditLogModel.fromMap(Map<String, Object?> map) {
    return AuditLogModel(
      id: map['id'] as int,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int?,
      action: map['action'] as String,
      summary: map['summary'] as String,
      metadata: map['metadata'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'summary': summary,
        'metadata': metadata,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, entityType, action, createdAt];
}
