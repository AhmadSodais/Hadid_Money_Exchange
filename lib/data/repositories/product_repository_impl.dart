import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../core/utils/product_alert_helper.dart';
import '../../core/utils/product_identity.dart';
import '../../domain/repositories/product_repository.dart';
import 'sql_helpers.dart';
import '../models/product_model.dart';
import '../models/report_models.dart';
import '../models/stock_movement_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  Database get _db => AppDatabase.instance;

  static const _selectJoin = '''
    SELECT p.*,
           c.name AS category_name,
           c.color AS category_color,
           cur.code AS currency_code,
           ccur.code AS cost_currency_code,
           s.name AS supplier_name,
           w.name AS warehouse_name
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    LEFT JOIN currencies cur ON cur.id = p.currency_id
    LEFT JOIN currencies ccur ON ccur.id = p.cost_currency_id
    LEFT JOIN suppliers s ON s.id = p.supplier_id
    LEFT JOIN warehouses w ON w.id = p.warehouse_id
  ''';

  @override
  Future<Result<PaginatedResult<ProductModel>>> query(
    ProductQuery query,
  ) async {
    try {
      final where = <String>[];
      final args = <Object?>[];

      if (!query.includeArchived) {
        where.add('p.is_archived = 0');
      }
      if (query.search != null && query.search!.trim().isNotEmpty) {
        where.add(
          "(p.name LIKE ? OR p.sku LIKE ? OR IFNULL(p.barcode, '') LIKE ? "
          "OR IFNULL(p.brand, '') LIKE ? OR IFNULL(s.name, '') LIKE ?)",
        );
        final term = '%${query.search!.trim()}%';
        args.addAll([term, term, term, term, term]);
      }
      if (query.categoryId != null) {
        where.add('p.category_id = ?');
        args.add(query.categoryId);
      }
      if (query.brand != null && query.brand!.trim().isNotEmpty) {
        where.add("IFNULL(p.brand, '') LIKE ?");
        args.add('%${query.brand!.trim()}%');
      }
      if (query.supplierId != null) {
        where.add('p.supplier_id = ?');
        args.add(query.supplierId);
      }
      if (query.categoryName != null &&
          query.categoryName!.isNotEmpty &&
          query.categoryName != 'All Products') {
        where.add('c.name = ?');
        args.add(query.categoryName);
      }
      if (query.status != null) {
        switch (query.status!) {
          case ProductStockStatus.outOfStock:
            where.add('p.current_stock <= 0');
          case ProductStockStatus.lowStock:
            where.add(
              'p.current_stock > 0 AND p.current_stock <= p.minimum_stock_alert',
            );
          case ProductStockStatus.inStock:
            where.add('p.current_stock > p.minimum_stock_alert');
        }
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final allowedSort = {
        'name',
        'sku',
        'current_stock',
        'selling_price',
        'updated_at',
        'created_at',
      };
      final sortCol = allowedSort.contains(query.sortBy)
          ? query.sortBy
          : 'updated_at';
      final dir = query.ascending ? 'ASC' : 'DESC';

      final countRow = await _db.rawQuery('''
        SELECT COUNT(*) AS c
        FROM products p
        LEFT JOIN categories c ON c.id = p.category_id
        LEFT JOIN suppliers s ON s.id = p.supplier_id
        $whereSql
        ''', args);
      final total = (countRow.first['c'] as int?) ?? 0;

      final rows = await _db.rawQuery(
        '''
        $_selectJoin
        $whereSql
        ORDER BY p.$sortCol $dir
        LIMIT ? OFFSET ?
        ''',
        [...args, query.pageSize, query.offset],
      );

      return Success(
        PaginatedResult(
          items: rows.map(ProductModel.fromMap).toList(),
          total: total,
          page: query.page,
          pageSize: query.pageSize,
        ),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load products: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ProductModel>> getById(int id) async {
    try {
      final rows = await _db.rawQuery('$_selectJoin WHERE p.id = ?', [id]);
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Product not found.'));
      }
      return Success(ProductModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load product: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ProductModel?>> getBySku(String sku) async {
    try {
      final rows = await _db.rawQuery(
        '$_selectJoin WHERE p.sku = ? AND p.is_archived = 0 LIMIT 1',
        [sku.trim()],
      );
      if (rows.isEmpty) return const Success(null);
      return Success(ProductModel.fromMap(rows.first));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('SKU lookup failed: $e', cause: st));
    }
  }

  @override
  Future<Result<ProductStats>> getStats() async {
    try {
      final rows = await _db.rawQuery('''
        SELECT
          COUNT(*) AS total,
          SUM(CASE WHEN is_active = 1 AND is_archived = 0 THEN 1 ELSE 0 END) AS active,
          SUM(CASE WHEN is_archived = 0 AND current_stock > 0
                   AND current_stock <= minimum_stock_alert THEN 1 ELSE 0 END) AS low_stock,
          SUM(CASE WHEN is_archived = 0 AND current_stock <= 0 THEN 1 ELSE 0 END) AS out_of_stock
        FROM products
        WHERE is_archived = 0
      ''');
      final r = rows.first;
      return Success(
        ProductStats(
          total: (r['total'] as int?) ?? 0,
          active: (r['active'] as int?) ?? 0,
          lowStock: (r['low_stock'] as int?) ?? 0,
          outOfStock: (r['out_of_stock'] as int?) ?? 0,
        ),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load product stats: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<bool>> isSkuAvailable(String sku, {int? excludeId}) async {
    if (sku.trim().isEmpty) return const Success(true);
    try {
      final args = <Object?>[sku.trim().toUpperCase()];
      var sql =
          'SELECT id FROM products WHERE UPPER(TRIM(sku)) = ? AND is_archived = 0';
      if (excludeId != null) {
        sql += ' AND id != ?';
        args.add(excludeId);
      }
      final rows = await _db.rawQuery('$sql LIMIT 1', args);
      return Success(rows.isEmpty);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('SKU check failed: $e', cause: st));
    }
  }

  static ProductModel _normalized(ProductModel product) {
    final sku = product.sku.trim().toUpperCase();
    final barcode = product.barcode?.trim();
    final blankBarcode = barcode == null || barcode.isEmpty;
    return product.copyWith(
      sku: sku,
      barcode: blankBarcode ? null : barcode,
      clearBarcode: blankBarcode,
    );
  }

  static String _variantKeyOf(ProductModel product) => ProductIdentity.variantKey(
        name: product.name,
        brand: product.brand,
        unitWeight: product.unitWeight,
        weightUnit: product.weightUnit,
        height: product.standardHeight,
        width: product.standardWidth,
        thickness: product.thickness,
      );

  /// Rejects [product] if an active product already has the same code,
  /// barcode, or name + brand + pack + sheet size. On update, only fields
  /// that changed are checked so legacy duplicates stay editable.
  ///
  /// A different sheet size is a different product. This check never moves
  /// stock from one product onto another.
  Future<ValidationFailure?> _findDuplicate(
    DatabaseExecutor db,
    ProductModel product, {
    Map<String, Object?>? previous,
  }) async {
    final sku = ProductIdentity.text(product.sku);
    final barcode = ProductIdentity.text(product.barcode);
    final key = _variantKeyOf(product);

    final checkSku =
        sku.isNotEmpty &&
        (previous == null || ProductIdentity.text(previous['sku'] as String?) != sku);
    final checkBarcode =
        barcode.isNotEmpty &&
        (previous == null ||
            ProductIdentity.text(previous['barcode'] as String?) != barcode);
    final checkName =
        previous == null || ProductIdentity.keyOfRow(previous) != key;
    if (!checkSku && !checkBarcode && !checkName) return null;

    final rows = await db.query(
      'products',
      columns: [
        'id',
        'name',
        'sku',
        'barcode',
        'brand',
        'unit_weight',
        'weight_unit',
        'standard_height',
        'standard_width',
        'thickness',
        'is_remnant',
      ],
      where: 'is_archived = 0 AND id != ?',
      whereArgs: [product.id],
    );
    for (final r in rows) {
      final existingName = r['name'] as String? ?? '';
      if (checkSku && ProductIdentity.text(r['sku'] as String?) == sku) {
        return ValidationFailure(
          'errors.skuExistsOn'.tr(namedArgs: {'name': existingName}),
          fieldErrors: const {'sku': 'duplicate'},
        );
      }
      if (checkBarcode && ProductIdentity.text(r['barcode'] as String?) == barcode) {
        return ValidationFailure(
          'errors.barcodeExists'.tr(namedArgs: {'name': existingName}),
          fieldErrors: const {'barcode': 'duplicate'},
        );
      }
      if (checkName &&
          (r['is_remnant'] as int? ?? 0) == 0 &&
          ProductIdentity.keyOfRow(r) == key) {
        final code = (r['sku'] as String? ?? '').trim();
        return ValidationFailure(
          'errors.productExists'.tr(
            namedArgs: {
              'name': existingName,
              'code': code.isEmpty ? '#${r['id']}' : code,
            },
          ),
          fieldErrors: const {'name': 'duplicate'},
        );
      }
    }
    return null;
  }

  @override
  Future<Result<ProductModel>> create(ProductModel product) async {
    try {
      final now = DateTime.now();
      final toInsert = _normalized(product).copyWith(
        currentStock: product.initialStock,
        createdAt: now,
        updatedAt: now,
      );

      final id = await _db.transaction((txn) async {
        final duplicate = await _findDuplicate(txn, toInsert);
        if (duplicate != null) throw duplicate;
        final productId = await txn.insert('products', toInsert.toInsertMap());
        int? initialMovementId;
        if (product.initialStock > 0) {
          String? partnerName = product.supplierName;
          if (partnerName == null && product.supplierId != null) {
            final sRows = await txn.query(
              'suppliers',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [product.supplierId],
              limit: 1,
            );
            if (sRows.isNotEmpty) {
              partnerName = sRows.first['name'] as String?;
            }
          }
          initialMovementId = await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': StockMovementType.initial.dbValue,
            'quantity': product.initialStock,
            'balance_after': product.initialStock,
            'reference_type': product.supplierId != null
                ? 'supplier'
                : 'product',
            'reference_id': product.supplierId ?? productId,
            'partner_name': partnerName,
            'length_m': product.standardHeight,
            'width_m': product.standardWidth,
            'area_m2':
                (product.standardHeight != null &&
                    product.standardWidth != null &&
                    product.standardHeight! > 0 &&
                    product.standardWidth! > 0)
                ? product.standardHeight! * product.standardWidth!
                : null,
            'parent_length_m': product.standardHeight,
            'parent_width_m': product.standardWidth,
            'broken_qty': 0,
            'notes': product.notes ?? 'movementTypes.initial'.tr(),
            'warehouse_id': product.warehouseId,
            'created_by': 'system',
            'created_at': now.toIso8601String(),
          });
        }
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': productId,
          'action': 'create',
          'summary': '${product.name} added',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        return (productId, initialMovementId);
      });

      final created = await getById(id.$1);
      if (created is Success<ProductModel>) {
        final p = created.value;
        await SyncOutbox.group(() async {
          if (id.$2 != null) {
            final area =
                (p.standardHeight != null &&
                    p.standardWidth != null &&
                    p.standardHeight! > 0 &&
                    p.standardWidth! > 0)
                ? p.standardHeight! * p.standardWidth!
                : null;
            await SyncOutbox.enqueue(
              entityType: SyncEntityTypes.transactions,
              entityId: '${id.$2}',
              operation: SyncOperation.create,
              data: SyncPayloadBuilders.movement(
                id: id.$2,
                productId: p.id,
                movementType: StockMovementType.initial.dbValue,
                quantity: p.initialStock,
                notes: p.notes ?? 'movementTypes.initial'.tr(),
                referenceType: p.supplierId != null ? 'supplier' : 'product',
                referenceId: p.supplierId ?? p.id,
                partnerName: p.supplierName,
                lengthM: p.standardHeight,
                widthM: p.standardWidth,
                areaM2: area,
                parentLengthM: p.standardHeight,
                parentWidthM: p.standardWidth,
                brokenQty: 0,
                warehouseId: p.warehouseId,
                balanceAfter: p.initialStock,
                createdBy: 'system',
                createdAt: now.toIso8601String(),
                updatedAt: now.toIso8601String(),
              ),
            );
          }
          await SyncPayloadBuilders.enqueueProductSnapshot(
            _db,
            p.id,
            operation: SyncOperation.create,
          );
        });
      }
      return created;
    } on AppFailure catch (e) {
      return FailureResult(e);
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return FailureResult(ConflictFailure('errors.skuExists'.tr()));
      }
      return FailureResult(
        DatabaseFailure('Failed to create product: $e', cause: st),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create product: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ProductModel>> update(ProductModel product) async {
    try {
      final now = DateTime.now();
      await _db.transaction((txn) async {
        final previous = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [product.id],
          limit: 1,
        );
        if (previous.isEmpty) {
          throw NotFoundFailure('errors.productNotFound'.tr());
        }
        final normalized = _normalized(product);
        final duplicate = await _findDuplicate(
          txn,
          normalized,
          previous: (previous.first['is_archived'] as int? ?? 0) == 1
              ? null
              : previous.first,
        );
        if (duplicate != null) throw duplicate;
        // Catalog edits must not rewrite inventory. Stock lives on this
        // product id only and is changed by movements, never by saving the form.
        final values = normalized.copyWith(updatedAt: now).toInsertMap()
          ..remove('current_stock')
          ..remove('initial_stock');
        await txn.update(
          'products',
          values,
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': product.id,
          'action': 'update',
          'summary': '${product.name} updated',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
      });
      final updated = await getById(product.id);
      if (updated is Success<ProductModel>) {
        await SyncPayloadBuilders.enqueueProductSnapshot(
          _db,
          updated.value.id,
          operation: SyncOperation.update,
        );
      }
      return updated;
    } on AppFailure catch (e) {
      return FailureResult(e);
    } on DatabaseException catch (e, st) {
      if (e.isUniqueConstraintError()) {
        return FailureResult(ConflictFailure('errors.skuExists'.tr()));
      }
      return FailureResult(
        DatabaseFailure('Failed to update product: $e', cause: st),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update product: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<ProductModel>> duplicate(int id) async {
    final existing = await getById(id);
    if (existing is FailureResult) return FailureResult(existing.failure);
    final source = (existing as Success<ProductModel>).value;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final copy = source.copyWith(
      id: 0,
      name: '${source.name} (Copy)',
      sku: '${source.sku}-$stamp',
      clearBarcode: true,
      initialStock: 0,
      currentStock: 0,
      imagePath: null,
      clearImage: true,
    );
    return create(copy);
  }

  @override
  Future<Result<void>> archive(int id) async {
    return _setArchived(id, true);
  }

  @override
  Future<Result<void>> restore(int id) async {
    return _setArchived(id, false);
  }

  Future<Result<void>> _setArchived(int id, bool archived) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _db.transaction((txn) async {
        if (!archived) {
          final rows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final duplicate = await _findDuplicate(
              txn,
              ProductModel.fromMap(rows.first),
            );
            if (duplicate != null) throw duplicate;
          }
        }
        await txn.update(
          'products',
          {
            'is_archived': archived ? 1 : 0,
            'is_active': archived ? 0 : 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': id,
          'action': archived ? 'archive' : 'restore',
          'summary': archived ? 'Product archived' : 'Product restored',
          'created_by': 'system',
          'created_at': now,
        });
      });
      await SyncPayloadBuilders.enqueueProductSnapshot(
        _db,
        id,
        operation: SyncOperation.update,
      );
      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Archive/restore failed: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final movementCount =
          firstIntValue(
            await _db.rawQuery(
              'SELECT COUNT(*) FROM stock_movements WHERE product_id = ?',
              [id],
            ),
          ) ??
          0;

      if (movementCount > 1) {
        return archive(id);
      }

      final movementIds = await _db.transaction((txn) async {
        final moves = await txn.query(
          'stock_movements',
          columns: ['id'],
          where: 'product_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'stock_movements',
          where: 'product_id = ?',
          whereArgs: [id],
        );
        await txn.delete('products', where: 'id = ?', whereArgs: [id]);
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': id,
          'action': 'delete',
          'summary': 'Product permanently deleted',
          'created_by': 'system',
          'created_at': DateTime.now().toIso8601String(),
        });
        return [for (final m in moves) m['id'] as int];
      });
      await SyncOutbox.group(() async {
        for (final mid in movementIds) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '$mid',
            operation: SyncOperation.delete,
            data: {'id': mid},
          );
        }
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.products,
          entityId: '$id',
          operation: SyncOperation.delete,
          data: {'id': id, 'deleted': true},
        );
      });
      return const Success(null);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Delete failed: $e', cause: st));
    }
  }

  @override
  Future<Result<ProductModel>> adjustStock({
    required int productId,
    required double quantityDelta,
    required StockMovementType type,
    String? notes,
    String? referenceType,
    int? referenceId,
  }) async {
    try {
      final now = DateTime.now();
      late final int movementId;
      await _db.transaction((txn) async {
        final rows = await txn.query(
          'products',
          columns: [
            'current_stock',
            'name',
            'standard_height',
            'standard_width',
          ],
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Product not found.');
        }
        final current = (rows.first['current_stock'] as num).toDouble();
        final next = current + quantityDelta;
        if (next < 0) {
          throw const ValidationFailure('Stock cannot go below zero.');
        }
        await txn.update(
          'products',
          {'current_stock': next, 'updated_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [productId],
        );
        final lengthM = (rows.first['standard_height'] as num?)?.toDouble();
        final widthM = (rows.first['standard_width'] as num?)?.toDouble();
        movementId = await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': type.dbValue,
          'quantity': quantityDelta,
          'balance_after': next,
          'reference_type': referenceType,
          'reference_id': referenceId,
          'notes': notes,
          'length_m': lengthM,
          'width_m': widthM,
          'area_m2':
              (lengthM != null && widthM != null && lengthM > 0 && widthM > 0)
              ? lengthM * widthM
              : null,
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': productId,
          'action': 'stock_adjust',
          'summary':
              '${rows.first['name']} stock ${quantityDelta >= 0 ? '+' : ''}$quantityDelta',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
      });
      final moveRows = await _db.query(
        'stock_movements',
        where: 'id = ?',
        whereArgs: [movementId],
        limit: 1,
      );
      await SyncOutbox.group(() async {
        if (moveRows.isNotEmpty) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '$movementId',
            operation: SyncOperation.create,
            data: SyncPayloadBuilders.movementFromRow(moveRows.first),
          );
        }
        await SyncPayloadBuilders.enqueueProductSnapshot(_db, productId);
      });
      return getById(productId);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Stock adjustment failed: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<StockMovementModel>>> getMovements(int productId) async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT sm.*, p.name AS product_name
        FROM stock_movements sm
        JOIN products p ON p.id = sm.product_id
        WHERE sm.product_id = ?
        ORDER BY sm.created_at DESC
        LIMIT 100
        ''',
        [productId],
      );
      return Success(rows.map(StockMovementModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load movements: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<InventoryAlert>>> getAlerts({int limit = 20}) async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT p.id, p.name, p.sku, p.barcode, p.brand, p.current_stock,
               p.minimum_stock_alert, p.expiration_date,
               p.expiry_alert_value, p.expiry_alert_unit,
               c.name AS category_name
        FROM products p
        LEFT JOIN categories c ON c.id = p.category_id
        WHERE p.is_archived = 0
          AND (
            p.current_stock <= 0
            OR p.current_stock <= p.minimum_stock_alert
            OR (${ProductAlertHelper.sqlExpiringSoonPredicate()})
          )
        ORDER BY
          CASE
            WHEN p.expiration_date IS NOT NULL
              AND date(p.expiration_date) < date('now') THEN 0
            WHEN p.current_stock <= 0 THEN 1
            WHEN ${ProductAlertHelper.sqlExpiringSoonPredicate()} THEN 2
            ELSE 3
          END,
          p.current_stock ASC
        LIMIT ?
        ''',
        [limit * 2],
      );
      final alerts = <InventoryAlert>[];
      for (final r in rows) {
        alerts.addAll(ProductAlertHelper.fromProductRow(r));
      }
      alerts.sort(
        (a, b) => ProductAlertHelper.statusPriority(
          a.status,
        ).compareTo(ProductAlertHelper.statusPriority(b.status)),
      );
      return Success(alerts.take(limit).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load alerts: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<CategoryShare>>> getCategoryShares() async {
    try {
      final rows = await _db.rawQuery('''
        SELECT c.name, c.color, COUNT(p.id) AS cnt
        FROM categories c
        LEFT JOIN products p ON p.category_id = c.id AND p.is_archived = 0
        GROUP BY c.id
        HAVING cnt > 0
        ORDER BY cnt DESC
      ''');
      final total = rows.fold<int>(0, (s, r) => s + ((r['cnt'] as int?) ?? 0));
      return Success(
        rows
            .map(
              (r) => CategoryShare(
                name: r['name'] as String,
                count: (r['cnt'] as int?) ?? 0,
                percent: total == 0
                    ? 0
                    : (((r['cnt'] as int?) ?? 0) / total) * 100,
                color: r['color'] as String?,
              ),
            )
            .toList(),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load category shares: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<ProductModel>>> searchForPos(
    String query, {
    int? categoryId,
  }) async {
    try {
      final where = <String>['p.is_archived = 0', 'p.is_active = 1'];
      final args = <Object?>[];
      if (query.trim().isNotEmpty) {
        where.add(
          "(p.name LIKE ? OR p.sku LIKE ? OR IFNULL(p.barcode, '') LIKE ? "
          "OR IFNULL(p.brand, '') LIKE ?)",
        );
        final term = '%${query.trim()}%';
        args.addAll([term, term, term, term]);
      }
      if (categoryId != null) {
        where.add('p.category_id = ?');
        args.add(categoryId);
      }
      final rows = await _db.rawQuery('''
        $_selectJoin
        WHERE ${where.join(' AND ')}
        ORDER BY p.created_at DESC, p.id DESC
        LIMIT 48
        ''', args);
      return Success(rows.map(ProductModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('POS search failed: $e', cause: st));
    }
  }
}
