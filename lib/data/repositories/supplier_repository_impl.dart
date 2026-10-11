import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../domain/repositories/supplier_repository.dart';
import 'sql_helpers.dart';
import '../models/report_models.dart';
import '../models/supplier_model.dart';

class SupplierRepositoryImpl implements SupplierRepository {
  Database get _db => AppDatabase.instance;

  static const _selectJoin = '''
    SELECT s.*,
           COUNT(p.id) AS product_count
    FROM suppliers s
    LEFT JOIN products p ON p.supplier_id = s.id AND p.is_archived = 0
  ''';

  @override
  Future<Result<PaginatedResult<SupplierModel>>> query({
    String? search,
    int page = 1,
    int pageSize = 20,
    bool includeArchived = false,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];

      if (!includeArchived) {
        where.add('s.is_archived = 0');
      }
      if (search != null && search.trim().isNotEmpty) {
        where.add('(s.name LIKE ? OR s.phone LIKE ? OR s.email LIKE ?)');
        final term = '%${search.trim()}%';
        args.addAll([term, term, term]);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final countRow = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM suppliers s $whereSql',
        args,
      );
      final total = (countRow.first['c'] as int?) ?? 0;

      final rows = await _db.rawQuery(
        '''
        $_selectJoin
        $whereSql
        GROUP BY s.id
        ORDER BY s.created_at DESC, s.id DESC
        LIMIT ? OFFSET ?
        ''',
        [...args, pageSize, (page - 1) * pageSize],
      );

      return Success(
        PaginatedResult(
          items: rows.map(SupplierModel.fromMap).toList(),
          total: total,
          page: page,
          pageSize: pageSize,
        ),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load suppliers: $e', cause: st));
    }
  }

  @override
  Future<Result<SupplierModel>> getById(int id) async {
    try {
      final rows = await _db.rawQuery(
        '$_selectJoin WHERE s.id = ? GROUP BY s.id',
        [id],
      );
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Supplier not found.'));
      }
      return Success(SupplierModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load supplier: $e', cause: st));
    }
  }

  @override
  Future<Result<SupplierModel>> create(SupplierModel supplier) async {
    try {
      if (supplier.name.trim().isEmpty) {
        return const FailureResult(ValidationFailure('Supplier name is required.'));
      }
      final now = DateTime.now();
      final toInsert = supplier.copyWith(
        id: 0,
        createdAt: now,
        updatedAt: now,
        isArchived: false,
      );
      final id = await _db.transaction((txn) async {
        final supplierId = await txn.insert(
          'suppliers',
          toInsert.toMap(includeId: false),
        );
        await txn.insert('audit_logs', {
          'entity_type': 'supplier',
          'entity_id': supplierId,
          'action': 'create',
          'summary': '${supplier.name.trim()} added',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        return supplierId;
      });
      final created = await getById(id);
      if (created is Success<SupplierModel>) {
        final s = created.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.companies,
          entityId: '${s.id}',
          operation: SyncOperation.create,
          data: {
            ...s.toMap(includeId: true).map((k, v) => MapEntry(k, v)),
            'id': s.id,
            'updatedAt': s.updatedAt.toIso8601String(),
            'createdAt': s.createdAt.toIso8601String(),
          },
        );
      }
      return created;
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to create supplier: $e', cause: st));
    }
  }

  @override
  Future<Result<SupplierModel>> update(SupplierModel supplier) async {
    try {
      if (supplier.name.trim().isEmpty) {
        return const FailureResult(ValidationFailure('Supplier name is required.'));
      }
      final now = DateTime.now();
      await _db.transaction((txn) async {
        final count = await txn.update(
          'suppliers',
          supplier.copyWith(updatedAt: now).toMap(includeId: false),
          where: 'id = ?',
          whereArgs: [supplier.id],
        );
        if (count == 0) {
          throw const NotFoundFailure('Supplier not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'supplier',
          'entity_id': supplier.id,
          'action': 'update',
          'summary': '${supplier.name.trim()} updated',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
      });
      final updated = await getById(supplier.id);
      if (updated is Success<SupplierModel>) {
        final s = updated.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.companies,
          entityId: '${s.id}',
          operation: SyncOperation.update,
          data: {
            ...s.toMap(includeId: true).map((k, v) => MapEntry(k, v)),
            'id': s.id,
            'updatedAt': s.updatedAt.toIso8601String(),
            'createdAt': s.createdAt.toIso8601String(),
          },
        );
      }
      return updated;
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to update supplier: $e', cause: st));
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
          'suppliers',
          {'is_archived': archived ? 1 : 0, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count == 0) {
          throw const NotFoundFailure('Supplier not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'supplier',
          'entity_id': id,
          'action': archived ? 'archive' : 'restore',
          'summary': archived ? 'Supplier archived' : 'Supplier restored',
          'created_by': 'system',
          'created_at': now,
        });
      });
      final rows = await _db.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.companies,
          entityId: '$id',
          operation: SyncOperation.update,
          data: {
            ...Map<String, dynamic>.from(rows.first),
            'id': id,
            'is_archived': archived ? 1 : 0,
            'updatedAt': now,
            'createdAt': rows.first['created_at'],
          },
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
      final productCount = firstIntValue(
            await _db.rawQuery(
              'SELECT COUNT(*) FROM products WHERE supplier_id = ?',
              [id],
            ),
          ) ??
          0;
      if (productCount > 0) {
        return archive(id);
      }

      await _db.transaction((txn) async {
        final count = await txn.delete('suppliers', where: 'id = ?', whereArgs: [id]);
        if (count == 0) {
          throw const NotFoundFailure('Supplier not found.');
        }
        await txn.insert('audit_logs', {
          'entity_type': 'supplier',
          'entity_id': id,
          'action': 'delete',
          'summary': 'Supplier permanently deleted',
          'created_by': 'system',
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.companies,
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
