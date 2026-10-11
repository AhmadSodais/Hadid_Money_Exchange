import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../domain/repositories/customer_repository.dart';
import 'sql_helpers.dart';
import '../models/customer_model.dart';
import '../models/report_models.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  Database get _db => AppDatabase.instance;

  /// Rebuild loan / purchase totals on [customers] from unpaid/paid sales orders.
  static Future<void> refreshBalancesFromOrders(DatabaseExecutor db) async {
    await db.rawUpdate('''
      UPDATE customers SET
        outstanding_balance = COALESCE((
          SELECT SUM(MAX(o.total - o.amount_paid, 0))
          FROM orders o
          WHERE o.status != 'void'
            AND o.partner_type = 'customer'
            AND o.partner_id = customers.id
        ), 0),
        total_purchases = COALESCE((
          SELECT SUM(o.total)
          FROM orders o
          WHERE o.status != 'void'
            AND o.partner_type = 'customer'
            AND o.partner_id = customers.id
        ), 0),
        last_purchase_at = (
          SELECT MAX(o.created_at)
          FROM orders o
          WHERE o.status != 'void'
            AND o.partner_type = 'customer'
            AND o.partner_id = customers.id
        ),
        updated_at = datetime('now')
    ''');
  }

  Map<String, dynamic> _syncPayload(CustomerModel c) {
    return SyncPayloadBuilders.customerFromRow(c.toMap(includeId: true));
  }

  @override
  Future<Result<PaginatedResult<CustomerModel>>> query({
    String? search,
    int page = 1,
    int pageSize = 20,
    bool includeArchived = false,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];

      if (!includeArchived) {
        where.add('is_archived = 0');
      }
      if (search != null && search.trim().isNotEmpty) {
        where.add('(name LIKE ? OR phone LIKE ? OR email LIKE ?)');
        final term = '%${search.trim()}%';
        args.addAll([term, term, term]);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final countRow = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM customers $whereSql',
        args,
      );
      final total = (countRow.first['c'] as int?) ?? 0;

      final rows = await _db.rawQuery(
        '''
        SELECT * FROM customers
        $whereSql
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
        ''',
        [...args, pageSize, (page - 1) * pageSize],
      );

      return Success(
        PaginatedResult(
          items: rows.map(CustomerModel.fromMap).toList(),
          total: total,
          page: page,
          pageSize: pageSize,
        ),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load customers: $e', cause: st));
    }
  }

  @override
  Future<Result<CustomerModel>> getById(int id) async {
    try {
      final rows = await _db.query('customers', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Customer not found.'));
      }
      return Success(CustomerModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load customer: $e', cause: st));
    }
  }

  @override
  Future<Result<CustomerModel>> create(CustomerModel customer) async {
    try {
      if (customer.name.trim().isEmpty) {
        return const FailureResult(ValidationFailure('Customer name is required.'));
      }
      final now = DateTime.now();
      final toInsert = customer.copyWith(
        id: 0,
        createdAt: now,
        updatedAt: now,
        isArchived: false,
      );
      final id = await _db.transaction((txn) async {
        final customerId = await txn.insert(
          'customers',
          toInsert.toMap(includeId: false),
        );
        await txn.insert('audit_logs', {
          'entity_type': 'customer',
          'entity_id': customerId,
          'action': 'create',
          'summary': '${customer.name.trim()} added',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        return customerId;
      });
      final created = await getById(id);
      if (created is Success<CustomerModel>) {
        final c = created.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.customers,
          entityId: '${c.id}',
          operation: SyncOperation.create,
          data: _syncPayload(c),
        );
      }
      return created;
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to create customer: $e', cause: st));
    }
  }

  @override
  Future<Result<CustomerModel>> update(CustomerModel customer) async {
    try {
      if (customer.name.trim().isEmpty) {
        return const FailureResult(ValidationFailure('Customer name is required.'));
      }
      final now = DateTime.now();
      final updated = await _db.transaction((txn) async {
        final count = await txn.update(
          'customers',
          customer.copyWith(updatedAt: now).toMap(includeId: false),
          where: 'id = ?',
          whereArgs: [customer.id],
        );
        if (count == 0) {
          throw const NotFoundFailure('Customer not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'customer',
          'entity_id': customer.id,
          'action': 'update',
          'summary': '${customer.name.trim()} updated',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        return count;
      });
      if (updated == 0) {
        return const FailureResult(NotFoundFailure('Customer not found.'));
      }
      final result = await getById(customer.id);
      if (result is Success<CustomerModel>) {
        final c = result.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.customers,
          entityId: '${c.id}',
          operation: SyncOperation.update,
          data: _syncPayload(c),
        );
      }
      return result;
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to update customer: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> archive(int id) => _setArchived(id, true);

  @override
  Future<Result<void>> restore(int id) => _setArchived(id, false);

  Future<Result<void>> _setArchived(int id, bool archived) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _db.transaction((txn) async {
        final count = await txn.update(
          'customers',
          {'is_archived': archived ? 1 : 0, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count == 0) {
          throw const NotFoundFailure('Customer not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'customer',
          'entity_id': id,
          'action': archived ? 'archive' : 'restore',
          'summary': archived ? 'Customer archived' : 'Customer restored',
          'created_by': 'system',
          'created_at': now,
        });
      });
      final rows = await _db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.customers,
          entityId: '$id',
          operation: SyncOperation.update,
          data: SyncPayloadBuilders.customerFromRow({
            ...rows.first,
            'is_archived': archived ? 1 : 0,
            'updated_at': now,
          }),
        );
      }
      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Archive/restore failed: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final orderCount = firstIntValue(
            await _db.rawQuery(
              '''
              SELECT COUNT(*) FROM orders
              WHERE partner_type = 'customer' AND partner_id = ?
              ''',
              [id],
            ),
          ) ??
          0;
      final movementCount = firstIntValue(
            await _db.rawQuery(
              '''
              SELECT COUNT(*) FROM stock_movements
              WHERE reference_type = 'customer' AND reference_id = ?
              ''',
              [id],
            ),
          ) ??
          0;

      if (orderCount > 0 || movementCount > 0) {
        return archive(id);
      }

      await _db.transaction((txn) async {
        final count = await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
        if (count == 0) {
          throw const NotFoundFailure('Customer not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'customer',
          'entity_id': id,
          'action': 'delete',
          'summary': 'Customer permanently deleted',
          'created_by': 'system',
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.customers,
        entityId: '$id',
        operation: SyncOperation.delete,
        data: {'id': id, 'deleted': true},
      );
      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Delete failed: $e', cause: st));
    }
  }
}
