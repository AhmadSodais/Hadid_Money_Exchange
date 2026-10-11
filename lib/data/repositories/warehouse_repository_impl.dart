import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../models/product_model.dart';
import '../models/stock_movement_model.dart';
import '../models/warehouse_model.dart';

class WarehouseRepositoryImpl implements WarehouseRepository {
  Database get _db => AppDatabase.instance;

  static const _productJoin = '''
    SELECT p.*,
           c.name AS category_name,
           c.color AS category_color,
           cur.code AS currency_code,
           s.name AS supplier_name,
           w.name AS warehouse_name
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    LEFT JOIN currencies cur ON cur.id = p.currency_id
    LEFT JOIN suppliers s ON s.id = p.supplier_id
    LEFT JOIN warehouses w ON w.id = p.warehouse_id
  ''';

  String _statsSelect({DateTime? from, DateTime? to}) {
    final fromArg = from?.toIso8601String();
    final toArg = to?.toIso8601String();
    final dateFilter = [
      if (fromArg != null) 'sm.created_at >= ?',
      if (toArg != null) 'sm.created_at <= ?',
    ].join(' AND ');
    final dateSql = dateFilter.isEmpty ? '' : ' AND $dateFilter';

    return '''
      SELECT w.*,
        COALESCE((
          SELECT COUNT(*) FROM products p
          WHERE p.warehouse_id = w.id AND p.is_archived = 0
        ), 0) AS product_count,
        COALESCE((
          SELECT SUM(p.current_stock) FROM products p
          WHERE p.warehouse_id = w.id AND p.is_archived = 0
        ), 0) AS stock_qty,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.warehouse_id = w.id
            AND sm.quantity > 0
            AND sm.movement_type IN ('purchase', 'return_in', 'initial')
            $dateSql
        ), 0) AS inbound_qty,
        COALESCE((
          SELECT COUNT(*) FROM stock_movements sm
          WHERE sm.warehouse_id = w.id
            AND sm.quantity < 0
            AND sm.movement_type IN ('sale', 'damage', 'waste', 'return_out', 'transfer')
            $dateSql
        ), 0) AS outbound_qty,
        COALESCE((
          SELECT SUM(
            ABS(sm.quantity) * COALESCE(sm.length_m, 0) * COALESCE(sm.width_m, 0)
          ) FROM stock_movements sm
          WHERE sm.warehouse_id = w.id
            AND sm.quantity > 0
            AND sm.movement_type IN ('purchase', 'return_in', 'initial')
            $dateSql
        ), 0) AS inbound_area,
        COALESCE((
          SELECT SUM(
            ABS(sm.quantity) * COALESCE(sm.length_m, 0) * COALESCE(sm.width_m, 0)
          ) FROM stock_movements sm
          WHERE sm.warehouse_id = w.id
            AND sm.quantity < 0
            AND sm.movement_type IN ('sale', 'damage', 'waste', 'return_out', 'transfer')
            $dateSql
        ), 0) AS outbound_area
      FROM warehouses w
    ''';
  }

  List<Object?> _dateArgs(DateTime? from, DateTime? to) {
    // Each subquery that uses date filter needs its own args pair.
    final args = <Object?>[];
    void addPair() {
      if (from != null) args.add(from.toIso8601String());
      if (to != null) args.add(to.toIso8601String());
    }

    addPair(); // inbound_qty
    addPair(); // outbound_qty
    addPair(); // inbound_area
    addPair(); // outbound_area
    return args;
  }

  @override
  Future<Result<List<WarehouseModel>>> list({
    bool includeInactive = false,
    String? search,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[..._dateArgs(from, to)];

      if (!includeInactive) where.add('w.is_active = 1');
      if (search != null && search.trim().isNotEmpty) {
        where.add('(w.name LIKE ? OR IFNULL(w.address, \'\') LIKE ?)');
        final term = '%${search.trim()}%';
        args.addAll([term, term]);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final rows = await _db.rawQuery(
        '${_statsSelect(from: from, to: to)} $whereSql ORDER BY w.created_at DESC, w.id DESC',
        args,
      );
      return Success(rows.map(WarehouseModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load warehouses: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<WarehouseModel>> getById(
    int id, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final rows = await _db.rawQuery(
        '${_statsSelect(from: from, to: to)} WHERE w.id = ?',
        [..._dateArgs(from, to), id],
      );
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Warehouse not found.'));
      }
      return Success(WarehouseModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load warehouse: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<WarehouseModel>> create(WarehouseModel warehouse) async {
    try {
      final name = warehouse.name.trim();
      if (name.isEmpty) {
        return const FailureResult(
          ValidationFailure('Warehouse name is required.'),
        );
      }
      final id = await _db.insert('warehouses', warehouse.toInsertMap());
      final created = await getById(id);
      if (created is Success<WarehouseModel>) {
        final w = created.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.warehouses,
          entityId: '${w.id}',
          operation: SyncOperation.create,
          data: Map<String, dynamic>.from(w.toInsertMap())
            ..['id'] = w.id
            ..['updatedAt'] = w.updatedAt.toIso8601String()
            ..['createdAt'] = w.createdAt.toIso8601String(),
        );
      }
      return created;
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return const FailureResult(
          ConflictFailure('A warehouse with this name already exists.'),
        );
      }
      return FailureResult(
        DatabaseFailure('Failed to create warehouse: $e', cause: st),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create warehouse: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<WarehouseModel>> update(WarehouseModel warehouse) async {
    try {
      final name = warehouse.name.trim();
      if (name.isEmpty) {
        return const FailureResult(
          ValidationFailure('Warehouse name is required.'),
        );
      }
      final updated = await _db.update(
        'warehouses',
        {
          'name': name,
          'address': warehouse.address?.trim().isEmpty == true
              ? null
              : warehouse.address?.trim(),
          'notes': warehouse.notes?.trim().isEmpty == true
              ? null
              : warehouse.notes?.trim(),
          'is_active': warehouse.isActive ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [warehouse.id],
      );
      if (updated == 0) {
        return const FailureResult(NotFoundFailure('Warehouse not found.'));
      }
      final result = await getById(warehouse.id);
      if (result is Success<WarehouseModel>) {
        final w = result.value;
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.warehouses,
          entityId: '${w.id}',
          operation: SyncOperation.update,
          data: Map<String, dynamic>.from(w.toInsertMap())
            ..['id'] = w.id
            ..['updatedAt'] = w.updatedAt.toIso8601String()
            ..['createdAt'] = w.createdAt.toIso8601String(),
        );
      }
      return result;
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return const FailureResult(
          ConflictFailure('A warehouse with this name already exists.'),
        );
      }
      return FailureResult(
        DatabaseFailure('Failed to update warehouse: $e', cause: st),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update warehouse: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final usedProducts = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE warehouse_id = ?',
        [id],
      );
      final usedMoves = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM stock_movements WHERE warehouse_id = ?',
        [id],
      );
      final pCount = (usedProducts.first['c'] as num?)?.toInt() ?? 0;
      final mCount = (usedMoves.first['c'] as num?)?.toInt() ?? 0;
      if (pCount > 0 || mCount > 0) {
        // Soft-delete when referenced.
        final now = DateTime.now().toIso8601String();
        await _db.update(
          'warehouses',
          {
            'is_active': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        final rows = await _db.query(
          'warehouses',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.warehouses,
            entityId: '$id',
            operation: SyncOperation.update,
            data: {
              ...Map<String, dynamic>.from(rows.first),
              'id': id,
              'updatedAt': now,
              'createdAt': rows.first['created_at'],
            },
          );
        }
        return const Success(null);
      }
      final deleted = await _db.delete(
        'warehouses',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted == 0) {
        return const FailureResult(NotFoundFailure('Warehouse not found.'));
      }
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.warehouses,
        entityId: '$id',
        operation: SyncOperation.delete,
        data: {'id': id, 'deleted': true},
      );
      return const Success(null);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete warehouse: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<StockMovementModel>>> getMovements(
    int warehouseId, {
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
    String? direction,
  }) async {
    try {
      final where = <String>['sm.warehouse_id = ?'];
      final args = <Object?>[warehouseId];
      if (from != null) {
        where.add('sm.created_at >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('sm.created_at <= ?');
        args.add(to.toIso8601String());
      }
      if (direction == 'inbound') {
        where.add("sm.movement_type IN ('purchase', 'return_in')");
      } else if (direction == 'outbound') {
        where.add("sm.movement_type IN ('sale', 'return_out')");
      }
      final safeLimit = limit < 1 ? 200 : limit;
      final safeOffset = offset < 0 ? 0 : offset;
      args.addAll([safeLimit, safeOffset]);
      final rows = await _db.rawQuery(
        '''
        SELECT sm.*,
               p.name AS product_name,
               p.image_path AS product_image_path,
               cur.code AS currency_code,
               cur.symbol AS currency_symbol,
               w.name AS warehouse_name
        FROM stock_movements sm
        LEFT JOIN products p ON p.id = sm.product_id
        LEFT JOIN currencies cur ON cur.id = sm.currency_id
        LEFT JOIN warehouses w ON w.id = sm.warehouse_id
        WHERE ${where.join(' AND ')}
        ORDER BY sm.created_at DESC
        LIMIT ? OFFSET ?
        ''',
        args,
      );
      return Success(rows.map(StockMovementModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load warehouse movements: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<int>> countMovements(
    int warehouseId, {
    DateTime? from,
    DateTime? to,
    String? direction,
  }) async {
    try {
      final where = <String>['warehouse_id = ?'];
      final args = <Object?>[warehouseId];
      if (from != null) {
        where.add('created_at >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('created_at <= ?');
        args.add(to.toIso8601String());
      }
      if (direction == 'inbound') {
        where.add("movement_type IN ('purchase', 'return_in')");
      } else if (direction == 'outbound') {
        where.add("movement_type IN ('sale', 'return_out')");
      }
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM stock_movements WHERE ${where.join(' AND ')}',
        args,
      );
      return Success((rows.first['c'] as num?)?.toInt() ?? 0);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to count warehouse movements: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<ProductModel>>> getProducts(
    int warehouseId, {
    int limit = 500,
  }) async {
    try {
      final safeLimit = limit < 1 ? 500 : limit;
      final rows = await _db.rawQuery(
        '''
        $_productJoin
        WHERE p.is_archived = 0 AND p.warehouse_id = ?
        ORDER BY p.created_at DESC, p.id DESC
        LIMIT ?
        ''',
        [warehouseId, safeLimit],
      );
      return Success(rows.map(ProductModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load warehouse products: $e', cause: st),
      );
    }
  }
}
