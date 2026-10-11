import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../domain/repositories/employee_repository.dart';
import '../models/employee_model.dart';
import '../models/stock_movement_model.dart';

class EmployeeRepositoryImpl implements EmployeeRepository {
  Database get _db => AppDatabase.instance;

  Map<String, dynamic> _employeeSyncPayload(EmployeeModel e) => {
        'id': e.id,
        'code': e.code,
        'fullName': e.fullName,
        'full_name': e.fullName,
        'phone': e.phone,
        'email': e.email,
        'role': e.role,
        'department': e.department,
        'hireDate': e.hireDate?.toIso8601String(),
        'hire_date': e.hireDate?.toIso8601String(),
        'baseSalary': e.baseSalary,
        'base_salary': e.baseSalary,
        'salaryCurrency': e.salaryCurrency,
        'salary_currency': e.salaryCurrency,
        'paymentCycle': e.paymentCycle,
        'payment_cycle': e.paymentCycle,
        'bankAccount': e.bankAccount,
        'bank_account': e.bankAccount,
        'address': e.address,
        'notes': e.notes,
        'isActive': e.isActive,
        'is_active': e.isActive ? 1 : 0,
        'createdAt': e.createdAt.toIso8601String(),
        'created_at': e.createdAt.toIso8601String(),
        'updatedAt': e.updatedAt.toIso8601String(),
        'updated_at': e.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _withdrawalSyncPayload(EmployeeWithdrawalModel w) => {
        'id': w.id,
        'employeeId': w.employeeId,
        'employee_id': w.employeeId,
        'label': w.label,
        'period_label': w.label,
        'amount': w.amount,
        'currency': w.currency,
        'withdrawnAt': w.withdrawnAt.toIso8601String(),
        'paid_at': w.withdrawnAt.toIso8601String(),
        'paymentMethod': w.paymentMethod,
        'payment_method': w.paymentMethod,
        'notes': w.notes,
        'createdAt': w.createdAt.toIso8601String(),
        'created_at': w.createdAt.toIso8601String(),
      };

  static const _movementJoin = '''
    SELECT sm.*,
           p.name AS product_name,
           p.image_path AS product_image_path,
           p.thickness AS product_thickness,
           p.unit_weight AS product_unit_weight,
           p.weight_unit AS product_weight_unit,
           cur.code AS currency_code,
           cur.symbol AS currency_symbol,
           w.name AS warehouse_name
    FROM stock_movements sm
    LEFT JOIN products p ON p.id = sm.product_id
    LEFT JOIN currencies cur ON cur.id = sm.currency_id
    LEFT JOIN warehouses w ON w.id = sm.warehouse_id
  ''';

  String _statsSelect({DateTime? from, DateTime? to}) {
    // List views only need withdrawal totals; movement fan-out is for detail.
    return '''
      SELECT e.*,
        0 AS movement_count,
        0 AS receipt_count,
        0 AS receipt_total,
        0 AS inbound_count,
        0 AS outbound_count,
        COALESCE((
          SELECT SUM(es.amount) FROM employee_salaries es
          WHERE es.employee_id = e.id
        ), 0) AS withdrawal_total
      FROM employees e
    ''';
  }

  String _detailStatsSelect({DateTime? from, DateTime? to}) {
    final fromArg = from?.toIso8601String();
    final toArg = to?.toIso8601String();
    final dateFilter = [
      if (fromArg != null) 'sm.created_at >= ?',
      if (toArg != null) 'sm.created_at <= ?',
    ].join(' AND ');
    final dateSql = dateFilter.isEmpty ? '' : ' AND $dateFilter';

    return '''
      SELECT e.*,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.employee_id = e.id $dateSql
        ), 0) AS movement_count,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.employee_id = e.id
            AND sm.quantity < 0
            AND sm.movement_type IN ('sale', 'return_out', 'transfer')
            $dateSql
        ), 0) AS receipt_count,
        COALESCE((
          SELECT SUM(
            ABS(sm.quantity) * COALESCE(sm.unit_price, 0)
          ) FROM stock_movements sm
          WHERE sm.employee_id = e.id
            AND sm.quantity < 0
            AND sm.movement_type IN ('sale', 'return_out', 'transfer')
            $dateSql
        ), 0) AS receipt_total,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.employee_id = e.id
            AND sm.quantity > 0
            $dateSql
        ), 0) AS inbound_count,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.employee_id = e.id
            AND sm.quantity < 0
            $dateSql
        ), 0) AS outbound_count,
        COALESCE((
          SELECT SUM(es.amount) FROM employee_salaries es
          WHERE es.employee_id = e.id
        ), 0) AS withdrawal_total
      FROM employees e
    ''';
  }

  List<Object?> _dateArgs(DateTime? from, DateTime? to) {
    final args = <Object?>[];
    void addPair() {
      if (from != null) args.add(from.toIso8601String());
      if (to != null) args.add(to.toIso8601String());
    }

    addPair();
    addPair();
    addPair();
    addPair();
    addPair();
    return args;
  }

  @override
  Future<Result<List<EmployeeModel>>> list({
    bool includeInactive = false,
    String? search,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];

      if (!includeInactive) where.add('e.is_active = 1');
      if (search != null && search.trim().isNotEmpty) {
        where.add(
          '(e.full_name LIKE ? OR IFNULL(e.code, \'\') LIKE ? '
          'OR IFNULL(e.phone, \'\') LIKE ? OR IFNULL(e.role, \'\') LIKE ? '
          'OR IFNULL(e.department, \'\') LIKE ?)',
        );
        final term = '%${search.trim()}%';
        args.addAll([term, term, term, term, term]);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final rows = await _db.rawQuery(
        '${_statsSelect(from: from, to: to)} $whereSql '
        'ORDER BY e.full_name COLLATE NOCASE ASC, e.id DESC',
        args,
      );
      return Success(rows.map(EmployeeModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load employees: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<EmployeeModel>> getById(
    int id, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final rows = await _db.rawQuery(
        '${_detailStatsSelect(from: from, to: to)} WHERE e.id = ?',
        [..._dateArgs(from, to), id],
      );
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Employee not found.'));
      }
      return Success(EmployeeModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load employee: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<EmployeeModel>> create(EmployeeModel employee) async {
    try {
      final id = await _db.insert('employees', employee.toInsertMap());
      final created = await getById(id);
      final value = created.valueOrNull;
      if (value != null) {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.employees,
          entityId: '$id',
          operation: SyncOperation.create,
          data: _employeeSyncPayload(value),
        );
      }
      return created;
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create employee: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<EmployeeModel>> update(EmployeeModel employee) async {
    try {
      final n = await _db.update(
        'employees',
        employee.toInsertMap(),
        where: 'id = ?',
        whereArgs: [employee.id],
      );
      if (n == 0) {
        return const FailureResult(NotFoundFailure('Employee not found.'));
      }
      final updated = await getById(employee.id);
      final value = updated.valueOrNull;
      if (value != null) {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.employees,
          entityId: '${value.id}',
          operation: SyncOperation.update,
          data: _employeeSyncPayload(value),
        );
      }
      return updated;
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update employee: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final withdrawalRows = await _db.query(
        'employee_salaries',
        columns: ['id'],
        where: 'employee_id = ?',
        whereArgs: [id],
      );
      final linkedMoves = await _db.transaction((txn) async {
        final moves = await txn.query(
          'stock_movements',
          columns: ['id'],
          where: 'employee_id = ?',
          whereArgs: [id],
          orderBy: 'id ASC',
        );
        await txn.update(
          'stock_movements',
          {'employee_id': null},
          where: 'employee_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'employee_salaries',
          where: 'employee_id = ?',
          whereArgs: [id],
        );
        final n = await txn.delete(
          'employees',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) {
          throw const NotFoundFailure('Employee not found.');
        }
        return [for (final m in moves) m['id'] as int];
      });
      await SyncOutbox.group(() async {
        for (final row in withdrawalRows) {
          final wid = row['id'] as int?;
          if (wid == null) continue;
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.employeeWithdrawals,
            entityId: '$wid',
            operation: SyncOperation.delete,
            data: {'id': wid, 'deleted': true},
          );
        }
        for (final mid in linkedMoves) {
          await SyncPayloadBuilders.enqueueMovementSnapshot(_db, mid);
        }
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.employees,
          entityId: '$id',
          operation: SyncOperation.delete,
          data: {'id': id, 'deleted': true},
        );
      });
      return const Success(null);
    } on AppFailure catch (f) {
      return FailureResult(f);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete employee: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<StockMovementModel>>> getMovements(
    int employeeId, {
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    try {
      final where = <String>['sm.employee_id = ?'];
      final args = <Object?>[employeeId];
      if (from != null) {
        where.add('sm.created_at >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('sm.created_at <= ?');
        args.add(to.toIso8601String());
      }
      final rows = await _db.rawQuery(
        '$_movementJoin WHERE ${where.join(' AND ')} '
        'ORDER BY sm.created_at DESC, sm.id DESC LIMIT ?',
        [...args, limit],
      );
      return Success(rows.map(StockMovementModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load employee movements: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<EmployeeWithdrawalModel>>> getWithdrawals(
    int employeeId,
  ) async {
    try {
      final rows = await _db.query(
        'employee_salaries',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'paid_at DESC, id DESC',
      );
      return Success(rows.map(EmployeeWithdrawalModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load withdrawals: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<EmployeeWithdrawalModel>> addWithdrawal(
    EmployeeWithdrawalModel withdrawal,
  ) async {
    try {
      final id =
          await _db.insert('employee_salaries', withdrawal.toInsertMap());
      final rows = await _db.query(
        'employee_salaries',
        where: 'id = ?',
        whereArgs: [id],
      );
      final created = EmployeeWithdrawalModel.fromMap(rows.first);
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.employeeWithdrawals,
        entityId: '$id',
        operation: SyncOperation.create,
        data: _withdrawalSyncPayload(created),
      );
      return Success(created);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to record withdrawal: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> deleteWithdrawal(int withdrawalId) async {
    try {
      final n = await _db.delete(
        'employee_salaries',
        where: 'id = ?',
        whereArgs: [withdrawalId],
      );
      if (n == 0) {
        return const FailureResult(
          NotFoundFailure('Withdrawal record not found.'),
        );
      }
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.employeeWithdrawals,
        entityId: '$withdrawalId',
        operation: SyncOperation.delete,
        data: {'id': withdrawalId, 'deleted': true},
      );
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete withdrawal: $e', cause: st),
      );
    }
  }
}
