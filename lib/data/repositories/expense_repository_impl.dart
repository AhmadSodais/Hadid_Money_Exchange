import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../domain/repositories/expense_repository.dart';
import '../models/expense_model.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  Database get _db => AppDatabase.instance;

  Map<String, dynamic> _syncPayload(ExpenseModel e) {
    return {
      'id': e.id,
      'category': e.category,
      'amount': e.amount,
      'currency_id': e.currencyId,
      'currencyId': e.currencyId,
      'currency_code': e.currencyCode,
      'currencyCode': e.currencyCode,
      'exchange_rate': e.exchangeRate,
      'exchangeRate': e.exchangeRate,
      'payee': e.payee,
      'expense_date': e.expenseDate.toIso8601String(),
      'expenseDate': e.expenseDate.toIso8601String(),
      'note': e.note,
      'created_at': e.createdAt.toIso8601String(),
      'createdAt': e.createdAt.toIso8601String(),
      'updated_at': e.updatedAt.toIso8601String(),
      'updatedAt': e.updatedAt.toIso8601String(),
    };
  }

  @override
  Future<Result<List<ExpenseModel>>> list({
    String? search,
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];

      final q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where.add(
          "(category LIKE ? OR IFNULL(payee, '') LIKE ? OR IFNULL(note, '') LIKE ?)",
        );
        final like = '%$q%';
        args.addAll([like, like, like]);
      }
      if (from != null) {
        where.add('expense_date >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('expense_date <= ?');
        args.add(to.toIso8601String());
      }
      final cat = category?.trim();
      if (cat != null && cat.isNotEmpty) {
        where.add('category = ?');
        args.add(cat);
      }

      final rows = await _db.query(
        'expenses',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'expense_date DESC, id DESC',
        limit: 1000,
      );
      return Success(rows.map(ExpenseModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load expenses: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ExpenseModel>> getById(int id) async {
    try {
      final rows = await _db.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Expense not found'));
      }
      return Success(ExpenseModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load expense: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ExpenseModel>> create(ExpenseModel expense) async {
    try {
      final now = DateTime.now();
      final map = expense
          .copyWith(id: 0, createdAt: now, updatedAt: now)
          .toMap()
        ..remove('id');
      final id = await _db.insert('expenses', map);
      final created = expense.copyWith(id: id, createdAt: now, updatedAt: now);
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.expenses,
        entityId: '$id',
        operation: SyncOperation.create,
        data: _syncPayload(created),
      );
      return Success(created);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create expense: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ExpenseModel>> update(ExpenseModel expense) async {
    try {
      final updated = expense.copyWith(updatedAt: DateTime.now());
      final map = updated.toMap()..remove('id');
      final n = await _db.update(
        'expenses',
        map,
        where: 'id = ?',
        whereArgs: [expense.id],
      );
      if (n == 0) {
        return const FailureResult(NotFoundFailure('Expense not found'));
      }
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.expenses,
        entityId: '${updated.id}',
        operation: SyncOperation.update,
        data: _syncPayload(updated),
      );
      return Success(updated);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update expense: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final n = await _db.delete('expenses', where: 'id = ?', whereArgs: [id]);
      if (n == 0) {
        return const FailureResult(NotFoundFailure('Expense not found'));
      }
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.expenses,
        entityId: '$id',
        operation: SyncOperation.delete,
        data: {'id': id, 'deleted': true},
      );
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete expense: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<ExpenseCategoryTotal>>> totalsByCategory({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];
      if (from != null) {
        where.add('expense_date >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('expense_date <= ?');
        args.add(to.toIso8601String());
      }
      final rows = await _db.rawQuery(
        '''
        SELECT category, COALESCE(SUM(amount), 0) AS total
        FROM expenses
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY category
        ORDER BY total DESC
        ''',
        args,
      );
      return Success(
        rows
            .map(
              (r) => ExpenseCategoryTotal(
                category: (r['category'] as String?) ?? '',
                amount: (r['total'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList(),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to summarize expenses: $e', cause: st),
      );
    }
  }
}
