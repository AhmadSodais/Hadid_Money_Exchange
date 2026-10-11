import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/repositories/customer_repository_impl.dart';
import '../database/app_database.dart';
import '../utils/glass_cut_helper.dart';
import 'sync_models.dart';
import 'sync_outbox.dart';
import 'sync_payload_builders.dart';
import 'sync_payload_sanitizer.dart';
import 'sync_queue_repository.dart';

/// Queues local business rows for server upload.
///
/// [runIfNeeded] runs once per DB (upgrade path).
/// [enqueueAllLocalData] can be called anytime for a full batch push
/// (e.g. after Excel import).
abstract final class SyncBackfill {
  /// v4: remnant unit_weight scaled by cut area + prior v3 payload completeness.
  static const _metaKey = 'business_sync_backfill_v4';
  static const _legacyMetaKey = 'business_sync_backfill_v3';

  /// Automatic one-time upload. Not forced (conflict checks still apply) and
  /// skips records whose last sent snapshot is identical.
  static Future<void> runIfNeeded() async {
    final queue = SyncQueueRepository();
    final done = await queue.metaValue(_metaKey);
    if (done == '1') return;

    try {
      await enqueueAllLocalData(
        notifyOutbox: false,
        forceLocal: false,
        skipUnchanged: true,
      );
      await queue.setMetaValue(_metaKey, '1');
      await queue.setMetaValue(_legacyMetaKey, '1');
      debugPrint('[SyncBackfill] queued full local business data for server');
    } catch (e, st) {
      debugPrint('[SyncBackfill] failed: $e\n$st');
    }
  }

  /// "Push everything": queue a fresh full snapshot of every business record.
  /// Returns how many jobs were queued.
  ///
  /// With [forceLocal] the snapshots deliberately override the server copy.
  /// With [skipUnchanged] records whose last sent snapshot is identical (and
  /// that have no unsent change) are skipped.
  static Future<int> enqueueAllLocalData({
    bool notifyOutbox = true,
    bool forceLocal = true,
    bool skipUnchanged = false,
  }) async {
    final db = AppDatabase.instance;
    final queue = SyncQueueRepository();
    final jobs = <SyncJobRequest>[];

    try {
      final fixed = await _repairRemnantWeights(db);
      if (fixed > 0) {
        debugPrint('[SyncBackfill] repaired unit_weight on $fixed remnants');
      }
    } catch (e, st) {
      debugPrint('[SyncBackfill] remnant weight repair failed: $e\n$st');
    }

    Future<void> put(
      String entityType,
      Object id,
      Map<String, dynamic> data,
    ) async {
      final entityId = '$id';
      if (skipUnchanged) {
        final snapshot = SyncPayloadSanitizer.sanitize(data);
        final lastSent = await queue.lastSentHash(entityType, entityId);
        if (lastSent == SyncQueueRepository.snapshotHash(snapshot) &&
            !await queue.hasOpenJob(entityType, entityId)) {
          return;
        }
      }
      jobs.add(
        SyncJobRequest(
          entityType: entityType,
          entityId: entityId,
          operation: SyncOperation.update,
          data: {
            ...data,
            if (forceLocal) 'forceLocal': true,
          },
        ),
      );
    }

    Future<void> enqueueTable({
      required String table,
      required String entityType,
      required Map<String, dynamic> Function(Map<String, Object?> row) mapRow,
      String? where,
    }) async {
      final rows = await db.query(table, where: where);
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        await put(entityType, id, mapRow(row));
      }
    }

    await enqueueTable(
      table: 'categories',
      entityType: SyncEntityTypes.categories,
      mapRow: (r) => Map<String, dynamic>.from(r),
    );
    await enqueueTable(
      table: 'warehouses',
      entityType: SyncEntityTypes.warehouses,
      mapRow: (r) => Map<String, dynamic>.from(r),
    );
    await enqueueTable(
      table: 'suppliers',
      entityType: SyncEntityTypes.companies,
      mapRow: (r) => Map<String, dynamic>.from(r),
    );
    // Keep loan / purchase totals current before pushing customers.
    await CustomerRepositoryImpl.refreshBalancesFromOrders(db);
    await enqueueTable(
      table: 'customers',
      entityType: SyncEntityTypes.customers,
      mapRow: SyncPayloadBuilders.customerFromRow,
    );
    await enqueueTable(
      table: 'products',
      entityType: SyncEntityTypes.products,
      mapRow: SyncPayloadBuilders.productFromRow,
    );
    await enqueueTable(
      table: 'stock_movements',
      entityType: SyncEntityTypes.transactions,
      mapRow: SyncPayloadBuilders.movementFromRow,
    );

    final payments = await db.query('company_payments', where: 'is_voided = 0');
    for (final row in payments) {
      final id = row['id'];
      if (id == null) continue;
      final allocs = await db.query(
        'company_payment_allocations',
        where: 'payment_id = ?',
        whereArgs: [id],
      );
      await put(
        SyncEntityTypes.companyPayments,
        id,
        SyncPayloadBuilders.companyPaymentFromRow(row, allocs),
      );
    }

    await enqueueTable(
      table: 'expenses',
      entityType: SyncEntityTypes.expenses,
      mapRow: _expensePayload,
    );
    await enqueueTable(
      table: 'employees',
      entityType: SyncEntityTypes.employees,
      mapRow: _employeePayload,
    );
    await enqueueTable(
      table: 'employee_salaries',
      entityType: SyncEntityTypes.employeeWithdrawals,
      mapRow: _withdrawalPayload,
    );

    for (final spec in [
      (table: 'orders', type: SyncEntityTypes.orders, fk: 'order_id'),
      (table: 'purchases', type: SyncEntityTypes.purchases, fk: 'purchase_id'),
    ]) {
      final rows = await db.query(spec.table, where: "status != 'void'");
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final moves = await db.query(
          'stock_movements',
          columns: ['id'],
          where: '${spec.fk} = ?',
          whereArgs: [id],
        );
        final movementIds = [
          for (final m in moves)
            if (m['id'] != null) m['id'] as int,
        ];
        await put(
          spec.type,
          id,
          SyncPayloadBuilders.invoiceFromRow(row, movementIds),
        );
      }
    }

    final ids = await queue.enqueueAll(jobs);
    if (notifyOutbox && ids.isNotEmpty) {
      SyncOutbox.revision.value = SyncOutbox.revision.value + 1;
    }
    debugPrint('[SyncBackfill] enqueued ${ids.length} local rows for batch push');
    return ids.length;
  }

  static Map<String, dynamic> _expensePayload(Map<String, Object?> r) => {
        'id': r['id'],
        'category': r['category'],
        'amount': r['amount'],
        'currency_id': r['currency_id'],
        'currencyId': r['currency_id'],
        'currency_code': r['currency_code'],
        'currencyCode': r['currency_code'],
        'exchange_rate': r['exchange_rate'],
        'payee': r['payee'],
        'expense_date': r['expense_date'],
        'expenseDate': r['expense_date'],
        'note': r['note'],
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
      };

  static Map<String, dynamic> _employeePayload(Map<String, Object?> r) => {
        'id': r['id'],
        'code': r['code'],
        'full_name': r['full_name'],
        'fullName': r['full_name'],
        'phone': r['phone'],
        'email': r['email'],
        'role': r['role'],
        'department': r['department'],
        'hire_date': r['hire_date'],
        'base_salary': r['base_salary'],
        'salary_currency': r['salary_currency'],
        'payment_cycle': r['payment_cycle'],
        'bank_account': r['bank_account'],
        'address': r['address'],
        'notes': r['notes'],
        'is_active': r['is_active'],
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
      };

  static Map<String, dynamic> _withdrawalPayload(Map<String, Object?> r) => {
        'id': r['id'],
        'employee_id': r['employee_id'],
        'employeeId': r['employee_id'],
        'period_label': r['period_label'],
        'label': r['period_label'],
        'amount': r['amount'],
        'currency': r['currency'],
        'paid_at': r['paid_at'],
        'withdrawnAt': r['paid_at'],
        'payment_method': r['payment_method'],
        'notes': r['notes'],
        'created_at': r['created_at'],
      };

  /// Fix remnant products that still carry the parent sheet's full weight.
  static Future<int> _repairRemnantWeights(DatabaseExecutor db) async {
    final remnants = await db.query(
      'products',
      where: 'is_remnant = 1 AND parent_product_id IS NOT NULL',
    );
    if (remnants.isEmpty) return 0;
    var n = 0;
    final now = DateTime.now().toIso8601String();
    for (final rem in remnants) {
      final id = rem['id'] as int?;
      final parentId = rem['parent_product_id'] as int?;
      if (id == null || parentId == null) continue;
      final parents = await db.query(
        'products',
        columns: [
          'unit_weight',
          'weight_unit',
          'standard_height',
          'standard_width',
        ],
        where: 'id = ?',
        whereArgs: [parentId],
        limit: 1,
      );
      if (parents.isEmpty) continue;
      final parent = parents.first;
      final nextWeight = GlassCutHelper.proportionalWeight(
        parentWeight: (parent['unit_weight'] as num?)?.toDouble(),
        parentLength: (parent['standard_height'] as num?)?.toDouble(),
        parentWidth: (parent['standard_width'] as num?)?.toDouble(),
        pieceLength: (rem['standard_height'] as num?)?.toDouble(),
        pieceWidth: (rem['standard_width'] as num?)?.toDouble(),
      );
      if (nextWeight == null) continue;
      final current = (rem['unit_weight'] as num?)?.toDouble();
      final weightUnit =
          (parent['weight_unit'] as String?)?.trim().isNotEmpty == true
              ? (parent['weight_unit'] as String).trim()
              : ((rem['weight_unit'] as String?)?.trim().isNotEmpty == true
                  ? (rem['weight_unit'] as String).trim()
                  : 'kg');
      if (current != null &&
          (current - nextWeight).abs() < 0.0005 &&
          (rem['weight_unit'] as String?) == weightUnit) {
        continue;
      }
      await db.update(
        'products',
        {
          'unit_weight': nextWeight,
          'weight_unit': weightUnit,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      n++;
    }
    return n;
  }
}
