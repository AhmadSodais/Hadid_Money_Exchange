import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/database/migrations/migration_v22.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../domain/repositories/lookup_repository.dart';
import 'sql_helpers.dart';
import '../models/category_model.dart';
import '../models/currency_model.dart';

class LookupRepositoryImpl implements LookupRepository {
  Database get _db => AppDatabase.instance;

  static const paymentMethods = [
    'Cash',
    'Bank Transfer',
    'Card',
    'Credit',
  ];

  @override
  Future<Result<List<CategoryModel>>> getCategories({
    bool includeInactive = false,
  }) async {
    try {
      final rows = await _db.query(
        'categories',
        where: includeInactive ? null : 'is_active = 1',
        orderBy: 'created_at DESC, id DESC',
      );
      return Success(rows.map(CategoryModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load categories: $e', cause: st));
    }
  }

  @override
  Future<Result<CategoryModel>> createCategory(String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return const FailureResult(ValidationFailure('Category name is required.'));
      }
      final now = DateTime.now().toIso8601String();
      final minOrder = firstIntValue(
            await _db.rawQuery('SELECT MIN(sort_order) FROM categories'),
          ) ??
          0;
      final id = await _db.insert('categories', {
        'name': trimmed,
        'color': null,
        'sort_order': minOrder - 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      final rows = await _db.query('categories', where: 'id = ?', whereArgs: [id]);
      final category = CategoryModel.fromMap(rows.first);
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.categories,
        entityId: '$id',
        operation: SyncOperation.create,
        data: {
          ...category.toMap().map((k, v) => MapEntry(k, v)),
          'updatedAt': now,
          'createdAt': now,
        },
      );
      return Success(category);
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return const FailureResult(ConflictFailure('Category already exists.'));
      }
      return FailureResult(DatabaseFailure('Failed to create category: $e', cause: st));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to create category: $e', cause: st));
    }
  }

  @override
  Future<Result<CategoryModel>> updateCategory(int id, String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return const FailureResult(ValidationFailure('Category name is required.'));
      }
      final now = DateTime.now().toIso8601String();
      final updated = await _db.update(
        'categories',
        {
          'name': trimmed,
          'is_active': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        return const FailureResult(NotFoundFailure('Category not found.'));
      }
      final rows = await _db.query('categories', where: 'id = ?', whereArgs: [id]);
      final category = CategoryModel.fromMap(rows.first);
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.categories,
        entityId: '$id',
        operation: SyncOperation.update,
        data: {
          ...category.toMap().map((k, v) => MapEntry(k, v)),
          'updatedAt': now,
          'createdAt': category.createdAt.toIso8601String(),
        },
      );
      return Success(category);
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return const FailureResult(ConflictFailure('Category already exists.'));
      }
      return FailureResult(DatabaseFailure('Failed to update category: $e', cause: st));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to update category: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> deleteCategory(int id) async {
    try {
      final now = DateTime.now().toIso8601String();
      final productIds = await _db.transaction((txn) async {
        final updated = await txn.update(
          'categories',
          {
            'is_active': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (updated == 0) {
          throw const NotFoundFailure('Category not found.');
        }
        final linked = await txn.query(
          'products',
          columns: ['id'],
          where: 'category_id = ?',
          whereArgs: [id],
        );
        // Keep product history; clear inactive category links.
        await txn.update(
          'products',
          {'category_id': null, 'updated_at': now},
          where: 'category_id = ?',
          whereArgs: [id],
        );
        return [for (final p in linked) p['id'] as int];
      });
      final rows = await _db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await SyncOutbox.group(() async {
        for (final pid in productIds) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        if (rows.isNotEmpty) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.categories,
            entityId: '$id',
            operation: SyncOperation.update,
            data: {
              ...Map<String, dynamic>.from(rows.first),
              'id': id,
              'is_active': 0,
              'updatedAt': now,
              'createdAt': rows.first['created_at'],
            },
          );
        }
      });
      return const Success(null);
    } on AppFailure catch (f) {
      return FailureResult(f);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to delete category: $e', cause: st));
    }
  }

  @override
  Future<Result<List<CurrencyModel>>> getCurrencies() async {
    try {
      var rows = await _db.query(
        'currencies',
        where: 'is_active = 1',
        orderBy: 'is_base DESC, code ASC',
      );
      if (rows.isEmpty) {
        // Safety net if V20 wiped currencies before V22 could reseed.
        await MigrationV22.up(_db);
        rows = await _db.query(
          'currencies',
          where: 'is_active = 1',
          orderBy: 'is_base DESC, code ASC',
        );
      }
      return Success(rows.map(CurrencyModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load currencies: $e', cause: st));
    }
  }

  @override
  Future<Result<CurrencyModel>> updateExchangeRate(int id, double rate) async {
    try {
      if (rate <= 0) {
        return const FailureResult(ValidationFailure('Exchange rate must be positive.'));
      }
      final now = DateTime.now().toIso8601String();
      final updated = await _db.update(
        'currencies',
        {'exchange_rate': rate, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        return const FailureResult(NotFoundFailure('Currency not found.'));
      }
      final rows = await _db.query('currencies', where: 'id = ?', whereArgs: [id]);
      return Success(CurrencyModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update exchange rate: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<UnitOfMeasureModel>>> getUnitsOfMeasure() async {
    try {
      final rows = await _db.query(
        'units_of_measure',
        where: 'is_active = 1',
        orderBy: 'name ASC',
      );
      return Success(rows.map(UnitOfMeasureModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load units: $e', cause: st));
    }
  }

  @override
  Future<Result<String?>> getSetting(String key) async {
    try {
      final rows = await _db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return const Success(null);
      return Success(rows.first['value'] as String);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load setting: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> setSetting(String key, String value) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _db.insert(
        'app_settings',
        {'key': key, 'value': value, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return const Success(null);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to save setting: $e', cause: st));
    }
  }

  @override
  Future<Result<Map<String, String>>> getAllSettings() async {
    try {
      final rows = await _db.query('app_settings');
      final map = <String, String>{
        for (final r in rows) r['key'] as String: r['value'] as String,
      };
      return Success(map);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load settings: $e', cause: st));
    }
  }

  @override
  Future<Result<List<String>>> getPaymentMethods() async {
    return const Success(paymentMethods);
  }
}
