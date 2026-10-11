import 'dart:convert';

import 'package:equatable/equatable.dart';

enum SyncOperation { create, update, delete }

/// [superseded]: replaced by a newer job for the same record before it was
/// sent. Never sent and never shown to the user.
enum SyncItemStatus { pending, synced, failed, conflict, superseded }

/// Statuses that mean "this record still has an unsent local change".
const openSyncStatuses = <SyncItemStatus>[
  SyncItemStatus.pending,
  SyncItemStatus.failed,
  SyncItemStatus.conflict,
];

extension SyncOperationX on SyncOperation {
  String get dbValue => name.toUpperCase();

  static SyncOperation fromDb(String raw) {
    switch (raw.toUpperCase()) {
      case 'CREATE':
        return SyncOperation.create;
      case 'DELETE':
        return SyncOperation.delete;
      default:
        return SyncOperation.update;
    }
  }
}

extension SyncItemStatusX on SyncItemStatus {
  String get dbValue => name;

  static SyncItemStatus fromDb(String raw) {
    switch (raw) {
      case 'synced':
        return SyncItemStatus.synced;
      case 'failed':
        return SyncItemStatus.failed;
      case 'conflict':
        return SyncItemStatus.conflict;
      case 'superseded':
        return SyncItemStatus.superseded;
      default:
        return SyncItemStatus.pending;
    }
  }
}

/// Local outbox row waiting for (or finished) Firebase sync.
class SyncQueueItem extends Equatable {
  const SyncQueueItem({
    required this.id,
    required this.syncId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    required this.changedAt,
    this.lastError,
    this.groupId,
  });

  final int id;
  final String syncId;
  final String entityType;
  final String entityId;
  final SyncOperation operation;

  /// Full snapshot of the record (never a partial diff).
  final Map<String, dynamic> payload;
  final SyncItemStatus status;
  final int retryCount;
  final String? lastError;

  /// When the job was queued.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When the record itself was last changed locally.
  final DateTime changedAt;

  /// Jobs queued by one business action share this id and are uploaded in
  /// the same write. Null for jobs queued before groups existed.
  final String? groupId;

  bool get forceLocal => payload['forceLocal'] == true;

  factory SyncQueueItem.fromMap(Map<String, Object?> map) {
    final rawPayload = map['payload'] as String? ?? '{}';
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(rawPayload);
      payload = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      payload = <String, dynamic>{};
    }

    final createdAt =
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse(map['updated_at'] as String? ?? '') ?? createdAt;
    return SyncQueueItem(
      id: map['id'] as int,
      syncId: map['sync_id'] as String,
      entityType: map['entity_type'] as String,
      entityId: '${map['entity_id']}',
      operation: SyncOperationX.fromDb(map['operation'] as String? ?? 'UPDATE'),
      payload: payload,
      status: SyncItemStatusX.fromDb(map['status'] as String? ?? 'pending'),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      changedAt:
          DateTime.tryParse(map['changed_at'] as String? ?? '') ?? updatedAt,
      groupId: map['group_id'] as String?,
    );
  }

  Map<String, Object?> toInsertMap() => {
        'sync_id': syncId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation.dbValue,
        'payload': jsonEncode(payload),
        'status': status.dbValue,
        'retry_count': retryCount,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'changed_at': changedAt.toIso8601String(),
        'group_id': groupId,
      };

  @override
  List<Object?> get props => [id, syncId, entityType, entityId, status];
}

/// Entity type constants used in the outbox / server paths.
abstract final class SyncEntityTypes {
  static const products = 'products';
  static const transactions = 'transactions';
  static const companies = 'companies';
  static const customers = 'customers';
  static const warehouses = 'warehouses';
  static const categories = 'categories';
  static const expenses = 'expenses';
  /// Trading-company settlements (payable / receivable) + allocations.
  static const companyPayments = 'company_payments';
  static const orders = 'orders';
  static const purchases = 'purchases';
  static const employees = 'employees';
  /// Employee salary-account withdrawals (local table: employee_salaries).
  static const employeeWithdrawals = 'employee_withdrawals';

  /// Collections that participate in bidirectional sync / wipe.
  static const List<String> allBusiness = [
    products,
    transactions,
    companyPayments,
    companies,
    customers,
    warehouses,
    categories,
    expenses,
    employees,
    employeeWithdrawals,
    orders,
    purchases,
  ];
}
