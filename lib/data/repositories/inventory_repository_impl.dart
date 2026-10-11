import 'package:easy_localization/easy_localization.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../core/utils/glass_cut_helper.dart';
import '../../core/utils/overview_chart_period.dart';
import '../../core/utils/product_alert_helper.dart';
import '../../core/utils/shamsi_dates.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../models/company_payment_model.dart';
import '../models/product_model.dart';
import '../models/report_models.dart';
import '../models/stock_movement_model.dart';
import 'customer_repository_impl.dart';
import 'remnant_stock_helper.dart';
import 'sql_helpers.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  Database get _db => AppDatabase.instance;

  static const _selectJoin = '''
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

  @override
  Future<Result<StockSummary>> getStockSummary() async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final rows = await _db.rawQuery('''
        SELECT
          COALESCE(SUM(current_stock * cost_price), 0) AS total_value,
          COALESCE(SUM(CASE WHEN track_stock_by_sheet = 1 THEN current_stock ELSE 0 END), 0) AS sheets,
          SUM(CASE WHEN current_stock > 0 AND current_stock <= minimum_stock_alert THEN 1 ELSE 0 END) AS low_stock
        FROM products
        WHERE is_archived = 0
      ''');
      final waste = await _db.rawQuery(
        '''
        SELECT COALESCE(SUM(ABS(quantity)), 0) AS waste
        FROM stock_movements
        WHERE movement_type = ? AND created_at >= ?
        ''',
        [StockMovementType.waste.dbValue, monthStart],
      );
      final r = rows.first;
      return Success(
        StockSummary(
          totalValue: (r['total_value'] as num?)?.toDouble() ?? 0,
          sheetCount: ((r['sheets'] as num?)?.toDouble() ?? 0).round(),
          lowStock: (r['low_stock'] as int?) ?? 0,
          wasteThisMonth: (waste.first['waste'] as num?)?.toDouble() ?? 0,
        ),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load stock summary: $e', cause: st));
    }
  }

  @override
  Future<Result<PaginatedResult<ProductModel>>> listStock(
    InventoryStockQuery query,
  ) async {
    try {
      final where = <String>['p.is_archived = 0'];
      final args = <Object?>[];

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
      // Remnant filter kept for legacy data only; general UI passes null.

      final whereSql = 'WHERE ${where.join(' AND ')}';
      final countRow = await _db.rawQuery(
        '''
        SELECT COUNT(*) AS c FROM products p
        LEFT JOIN suppliers s ON s.id = p.supplier_id
        $whereSql
        ''',
        args,
      );
      final total = (countRow.first['c'] as int?) ?? 0;
      final rows = await _db.rawQuery(
        '''
        $_selectJoin
        $whereSql
        ORDER BY p.created_at DESC, p.id DESC
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
      return FailureResult(DatabaseFailure('Failed to list inventory: $e', cause: st));
    }
  }

  @override
  Future<Result<List<StockMovementModel>>> getMovements({
    int? productId,
    StockMovementType? type,
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
    bool excludeOrderLinked = true,
    bool excludePurchaseLinked = true,
    String? partnerType,
    int? partnerId,
    String? partnerName,
  }) async {
    try {
      final where = <String>[];
      final args = <Object?>[];
      if (excludeOrderLinked) {
        where.add('sm.order_id IS NULL');
      }
      if (excludePurchaseLinked) {
        where.add('sm.purchase_id IS NULL');
      }
      if (productId != null) {
        where.add('sm.product_id = ?');
        args.add(productId);
      }
      if (type != null) {
        where.add('sm.movement_type = ?');
        args.add(type.dbValue);
      }
      if (from != null) {
        where.add('sm.created_at >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('sm.created_at <= ?');
        args.add(to.toIso8601String());
      }
      if (partnerType != null && partnerId != null) {
        final name = (partnerName ?? '').trim();
        if (name.isNotEmpty) {
          where.add(
            '((sm.reference_type = ? AND sm.reference_id = ?) OR '
            'LOWER(TRIM(IFNULL(sm.partner_name, \'\'))) = LOWER(?))',
          );
          args.addAll([partnerType, partnerId, name]);
        } else {
          where.add('sm.reference_type = ? AND sm.reference_id = ?');
          args.addAll([partnerType, partnerId]);
        }
      }
      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final safeLimit = limit < 1 ? 100 : limit;
      final safeOffset = offset < 0 ? 0 : offset;
      final rows = await _db.rawQuery(
        '''
        SELECT sm.*,
               p.name AS product_name,
               p.image_path AS product_image_path,
               p.thickness AS product_thickness,
               p.unit_weight AS product_unit_weight,
               p.weight_unit AS product_weight_unit,
               cur.code AS currency_code,
               cur.symbol AS currency_symbol,
               w.name AS warehouse_name,
               e.full_name AS employee_name
        FROM stock_movements sm
        JOIN products p ON p.id = sm.product_id
        LEFT JOIN currencies cur ON cur.id = sm.currency_id
        LEFT JOIN warehouses w ON w.id = sm.warehouse_id
        LEFT JOIN employees e ON e.id = sm.employee_id
        $whereSql
        ORDER BY sm.created_at DESC
        LIMIT ? OFFSET ?
        ''',
        [...args, safeLimit, safeOffset],
      );
      return Success(rows.map(StockMovementModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load movements: $e', cause: st));
    }
  }

  @override
  Future<Result<ProductModel>> recordMovement({
    required int productId,
    required StockMovementType type,
    required double quantity,
    String? notes,
    String? referenceType,
    int? referenceId,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    double paidAmount = 0,
    int? currencyId,
    int? warehouseId,
    int? employeeId,
    DateTime? createdAt,
  }) async {
    try {
      if (quantity == 0) {
        return const FailureResult(ValidationFailure('Quantity cannot be zero.'));
      }

      // Outgoing types should reduce stock.
      final outgoing = {
        StockMovementType.sale,
        StockMovementType.damage,
        StockMovementType.waste,
        StockMovementType.returnOut,
        StockMovementType.transfer,
      };
      var delta = quantity;
      if (outgoing.contains(type) && quantity > 0) {
        delta = -quantity;
      }
      if (type == StockMovementType.purchase ||
          type == StockMovementType.returnIn ||
          type == StockMovementType.initial) {
        delta = quantity.abs();
      }

      final now = DateTime.now();
      final movementAt = createdAt ?? now;
      int? remnantId;
      var syncedDelta = delta;
      String? syncedNotes = notes;
      double? syncedAreaM2;
      double? syncedParentLength;
      double? syncedParentWidth;
      double? syncedBalanceAfter;
      int? syncedWarehouseId;
      final movementId = await _db.transaction((txn) async {
        final rows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Product not found.');
        }
        final product = rows.first;
        final current = (product['current_stock'] as num).toDouble();
        final trackBySheet =
            (product['track_stock_by_sheet'] as int? ?? 0) == 1;

        // Cut-to-size: sales open whole sheets and may create remnants.
        var effectiveDelta = delta;
        var movementNotes = notes;
        if (type == StockMovementType.sale ||
            type == StockMovementType.returnOut) {
          final parentLength =
              (product['standard_height'] as num?)?.toDouble();
          final parentWidth =
              (product['standard_width'] as num?)?.toDouble();
          final cut = GlassCutHelper.plan(
            parentLength: parentLength,
            parentWidth: parentWidth,
            cutLength: lengthM,
            cutWidth: widthM,
            quantity: quantity.abs(),
            trackStockBySheet: trackBySheet,
          );
          effectiveDelta = -cut.sheetsConsumed;
          syncedDelta = effectiveDelta;
          final pieceArea = GlassCutHelper.pieceAreaM2(lengthM, widthM);
          syncedAreaM2 = pieceArea;
          syncedParentLength = parentLength;
          syncedParentWidth = parentWidth;
          final base = (notes == null || notes.trim().isEmpty)
              ? 'inventory.cutToSize'.tr()
              : notes.trim();
          if (cut.isPartialCut) {
            movementNotes = GlassCutHelper.saleCutNotes(
              base: base,
              cut: cut,
              cutLength: lengthM,
              cutWidth: widthM,
              parentLength: parentLength,
              parentWidth: parentWidth,
            );
            syncedNotes = movementNotes;
          }
          final nextStock = current + effectiveDelta;
          if (nextStock < 0) {
            throw const ValidationFailure('Stock cannot go below zero.');
          }
          syncedBalanceAfter = nextStock;
          final resolvedWarehouseId =
              warehouseId ?? product['warehouse_id'] as int?;
          syncedWarehouseId = resolvedWarehouseId;
          final productUpdate = <String, Object?>{
            'current_stock': nextStock,
            'updated_at': now.toIso8601String(),
          };
          if (warehouseId != null) {
            productUpdate['warehouse_id'] = warehouseId;
          }
          if (unitPrice != null && unitPrice > 0) {
            productUpdate['selling_price'] = unitPrice;
          }
          await txn.update(
            'products',
            productUpdate,
            where: 'id = ?',
            whereArgs: [productId],
          );
          final mid = await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': type.dbValue,
            'quantity': effectiveDelta,
            'balance_after': nextStock,
            'reference_type': referenceType,
            'reference_id': referenceId,
            'notes': movementNotes,
            'partner_name': partnerName,
            'length_m': lengthM,
            'width_m': widthM,
            'area_m2': pieceArea,
            'parent_length_m': parentLength,
            'parent_width_m': parentWidth,
            'broken_qty': brokenQty,
            'unit_price': unitPrice,
            'paid_amount': paidAmount < 0 ? 0 : paidAmount,
            'currency_id': currencyId,
            'warehouse_id': resolvedWarehouseId,
            'employee_id': employeeId,
            'created_by':
                employeeId != null ? 'employee:$employeeId' : 'system',
            'created_at': movementAt.toIso8601String(),
          });
          await txn.insert('audit_logs', {
            'entity_type': 'product',
            'entity_id': productId,
            'action': 'stock_movement',
            'summary':
                '${product['name']} ${type.label}: $effectiveDelta'
                '${partnerName != null ? ' · $partnerName' : ''}'
                '${unitPrice != null ? ' @ $unitPrice' : ''}',
            'created_by':
                employeeId != null ? 'employee:$employeeId' : 'system',
            'created_at': now.toIso8601String(),
          });
          if (cut.hasRemnant) {
            remnantId = await RemnantStockHelper.upsertRemnant(
              txn: txn,
              parent: product,
              remnantLengthM: cut.remnantLengthM!,
              remnantWidthM: cut.remnantWidthM!,
              quantity: cut.sheetsConsumed,
              now: now,
              warehouseId: resolvedWarehouseId,
              cutLengthM: lengthM,
              cutWidthM: widthM,
            );
          }
          return mid;
        }

        final next = current + delta;
        if (next < 0) {
          throw const ValidationFailure('Stock cannot go below zero.');
        }
        syncedBalanceAfter = next;
        syncedAreaM2 = GlassCutHelper.pieceAreaM2(lengthM, widthM);
        syncedParentLength =
            (product['standard_height'] as num?)?.toDouble();
        syncedParentWidth =
            (product['standard_width'] as num?)?.toDouble();
        final resolvedWarehouseId =
            warehouseId ?? product['warehouse_id'] as int?;
        syncedWarehouseId = resolvedWarehouseId;
        final productUpdate = <String, Object?>{
          'current_stock': next,
          'updated_at': now.toIso8601String(),
        };
        if (warehouseId != null) {
          productUpdate['warehouse_id'] = warehouseId;
        }
        // Keep catalog cost / sell in sync with latest transaction price.
        if (unitPrice != null && unitPrice > 0) {
          if (type == StockMovementType.purchase ||
              type == StockMovementType.returnIn ||
              type == StockMovementType.initial) {
            productUpdate['cost_price'] = unitPrice;
          }
        }
        await txn.update(
          'products',
          productUpdate,
          where: 'id = ?',
          whereArgs: [productId],
        );
        final mid = await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': type.dbValue,
          'quantity': delta,
          'balance_after': next,
          'reference_type': referenceType,
          'reference_id': referenceId,
          'notes': notes,
          'partner_name': partnerName,
          'length_m': lengthM,
          'width_m': widthM,
          'area_m2': syncedAreaM2,
          'parent_length_m': syncedParentLength,
          'parent_width_m': syncedParentWidth,
          'broken_qty': brokenQty,
          'unit_price': unitPrice,
          'paid_amount': paidAmount < 0 ? 0 : paidAmount,
          'currency_id': currencyId,
          'warehouse_id': resolvedWarehouseId,
          'employee_id': employeeId,
          'created_by': employeeId != null ? 'employee:$employeeId' : 'system',
          'created_at': movementAt.toIso8601String(),
        });
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': productId,
          'action': 'stock_movement',
          'summary':
              '${product['name']} ${type.label}: ${delta >= 0 ? '+' : ''}$delta'
              '${partnerName != null ? ' · $partnerName' : ''}'
              '${unitPrice != null ? ' @ $unitPrice' : ''}',
          'created_by': employeeId != null ? 'employee:$employeeId' : 'system',
          'created_at': now.toIso8601String(),
        });
        return mid;
      });

      await SyncOutbox.group(() async {
        final rid = remnantId;
        if (rid != null) {
          await RemnantStockHelper.enqueueRemnantProductSync(_db, rid);
        }
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.transactions,
          entityId: '$movementId',
          operation: SyncOperation.create,
          data: SyncPayloadBuilders.movement(
            id: movementId,
            productId: productId,
            movementType: type.dbValue,
            quantity: syncedDelta,
            notes: syncedNotes,
            referenceType: referenceType,
            referenceId: referenceId,
            partnerName: partnerName,
            lengthM: lengthM,
            widthM: widthM,
            areaM2: syncedAreaM2,
            parentLengthM: syncedParentLength,
            parentWidthM: syncedParentWidth,
            brokenQty: brokenQty,
            unitPrice: unitPrice,
            paidAmount: paidAmount < 0 ? 0 : paidAmount,
            currencyId: currencyId,
            warehouseId: syncedWarehouseId ?? warehouseId,
            employeeId: employeeId,
            orderId: null,
            purchaseId: null,
            balanceAfter: syncedBalanceAfter,
            createdBy: employeeId != null ? 'employee:$employeeId' : 'system',
            createdAt: movementAt.toIso8601String(),
            updatedAt: movementAt.toIso8601String(),
          ),
        );
        await SyncPayloadBuilders.enqueueProductSnapshot(_db, productId);
      });

      final productRows = await _db.rawQuery(
        '$_selectJoin WHERE p.id = ?',
        [productId],
      );
      return Success(ProductModel.fromMap(productRows.first));
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to record movement: $e', cause: st));
    }
  }

  @override
  Future<Result<void>> deleteMovement(int movementId) async {
    try {
      final now = DateTime.now();
      final productId = await _db.transaction((txn) async {
        final rows = await txn.query(
          'stock_movements',
          where: 'id = ?',
          whereArgs: [movementId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Movement not found.');
        }
        final map = rows.first;
        final productId = map['product_id'] as int;
        final qty = (map['quantity'] as num).toDouble();

        final products = await txn.query(
          'products',
          columns: ['current_stock', 'name'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (products.isEmpty) {
          throw const NotFoundFailure('Product not found.');
        }
        final current = (products.first['current_stock'] as num).toDouble();
        final next = current - qty;
        if (next < 0) {
          throw const ValidationFailure(
            'Cannot delete this movement — stock would go below zero.',
          );
        }
        await txn.update(
          'products',
          {
            'current_stock': next,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
        await txn.delete(
          'stock_movements',
          where: 'id = ?',
          whereArgs: [movementId],
        );
        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': productId,
          'action': 'stock_movement_delete',
          'summary':
              '${products.first['name']} movement #$movementId deleted (reversed ${qty >= 0 ? '+' : ''}$qty)',
          'created_by': 'system',
          'created_at': now.toIso8601String(),
        });
        return productId;
      });
      await SyncOutbox.group(() async {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.transactions,
          entityId: '$movementId',
          operation: SyncOperation.delete,
          data: {'id': movementId, 'deleted': true},
        );
        await SyncPayloadBuilders.enqueueProductSnapshot(_db, productId);
      });
      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete movement: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<StockMovementModel>> updateMovement({
    required int movementId,
    required double quantity,
    String? notes,
    String? partnerName,
    double? lengthM,
    double? widthM,
    double brokenQty = 0,
    double? unitPrice,
    double? paidAmount,
    int? currencyId,
    int? warehouseId,
    int? employeeId,
    DateTime? createdAt,
  }) async {
    try {
      if (quantity == 0) {
        return const FailureResult(
          ValidationFailure('Quantity cannot be zero.'),
        );
      }
      final now = DateTime.now();
      late StockMovementModel updated;
      int? orderId;
      int? purchaseId;
      await _db.transaction((txn) async {
        final rows = await txn.query(
          'stock_movements',
          where: 'id = ?',
          whereArgs: [movementId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Movement not found.');
        }
        final old = StockMovementModel.fromMap(rows.first);
        final productId = old.productId;
        // Keep the same sign as the original movement.
        final signedQty = old.quantity < 0 ? -quantity.abs() : quantity.abs();
        final stockDelta = signedQty - old.quantity;

        final products = await txn.query(
          'products',
          columns: [
            'current_stock',
            'name',
            'warehouse_id',
            'standard_height',
            'standard_width',
          ],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (products.isEmpty) {
          throw const NotFoundFailure('Product not found.');
        }
        final current = (products.first['current_stock'] as num).toDouble();
        final next = current + stockDelta;
        if (next < 0) {
          throw const ValidationFailure('Stock cannot go below zero.');
        }

        final resolvedWarehouseId = warehouseId ?? old.warehouseId;
        final productUpdate = <String, Object?>{
          'current_stock': next,
          'updated_at': now.toIso8601String(),
        };
        if (resolvedWarehouseId != null) {
          productUpdate['warehouse_id'] = resolvedWarehouseId;
        }
        if (lengthM != null && lengthM > 0) {
          productUpdate['standard_height'] = lengthM;
        }
        if (widthM != null && widthM > 0) {
          productUpdate['standard_width'] = widthM;
        }
        if (unitPrice != null && unitPrice > 0) {
          if (signedQty >= 0) {
            productUpdate['cost_price'] = unitPrice;
          } else {
            productUpdate['selling_price'] = unitPrice;
          }
        }
        await txn.update(
          'products',
          productUpdate,
          where: 'id = ?',
          whereArgs: [productId],
        );
        await txn.update(
          'stock_movements',
          {
            'quantity': signedQty,
            'notes': notes,
            'partner_name': partnerName,
            'length_m': lengthM,
            'width_m': widthM,
            'broken_qty': brokenQty,
            'unit_price': unitPrice,
            if (paidAmount != null)
              'paid_amount': paidAmount < 0 ? 0 : paidAmount,
            if (currencyId != null) 'currency_id': currencyId,
            if (resolvedWarehouseId != null) 'warehouse_id': resolvedWarehouseId,
            if (employeeId != null) 'employee_id': employeeId,
            if (createdAt != null) 'created_at': createdAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [movementId],
        );

        await _recomputeProductBalances(txn, productId);

        await txn.insert('audit_logs', {
          'entity_type': 'product',
          'entity_id': productId,
          'action': 'stock_movement_update',
          'summary':
              '${products.first['name']} movement #$movementId updated to ${signedQty >= 0 ? '+' : ''}$signedQty',
          'created_by': employeeId != null ? 'employee:$employeeId' : 'system',
          'created_at': now.toIso8601String(),
        });

        final refreshed = await txn.rawQuery(
          '''
          SELECT sm.*,
                 p.name AS product_name,
                 p.image_path AS product_image_path,
                 p.thickness AS product_thickness,
                 p.unit_weight AS product_unit_weight,
                 p.weight_unit AS product_weight_unit,
                 cur.code AS currency_code,
                 cur.symbol AS currency_symbol,
                 w.name AS warehouse_name,
                 e.full_name AS employee_name
          FROM stock_movements sm
          JOIN products p ON p.id = sm.product_id
          LEFT JOIN currencies cur ON cur.id = sm.currency_id
          LEFT JOIN warehouses w ON w.id = sm.warehouse_id
          LEFT JOIN employees e ON e.id = sm.employee_id
          WHERE sm.id = ?
          ''',
          [movementId],
        );
        updated = StockMovementModel.fromMap(refreshed.first);
        orderId = refreshed.first['order_id'] as int?;
        purchaseId = refreshed.first['purchase_id'] as int?;
      });
      await SyncOutbox.group(() async {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.transactions,
          entityId: '$movementId',
          operation: SyncOperation.update,
          data: SyncPayloadBuilders.movement(
            id: updated.id,
            productId: updated.productId,
            movementType: updated.movementType.dbValue,
            quantity: updated.quantity,
            notes: updated.notes,
            referenceType: updated.referenceType,
            referenceId: updated.referenceId,
            partnerName: updated.partnerName,
            lengthM: updated.lengthM,
            widthM: updated.widthM,
            areaM2: updated.pieceAreaM2,
            parentLengthM: updated.parentLengthM,
            parentWidthM: updated.parentWidthM,
            brokenQty: updated.brokenQty,
            unitPrice: updated.unitPrice,
            paidAmount: updated.paidAmount,
            currencyId: updated.currencyId,
            warehouseId: updated.warehouseId,
            employeeId: updated.employeeId,
            orderId: orderId,
            purchaseId: purchaseId,
            balanceAfter: updated.balanceAfter,
            createdBy: updated.createdBy,
            createdAt: updated.createdAt.toIso8601String(),
            updatedAt: now.toIso8601String(),
          ),
        );
        await SyncPayloadBuilders.enqueueProductSnapshot(
          _db,
          updated.productId,
        );
        final oid = orderId;
        final pid = purchaseId;
        if (oid != null) {
          await SyncPayloadBuilders.enqueueInvoiceSnapshot(
            _db,
            isOrder: true,
            id: oid,
          );
        }
        if (pid != null) {
          await SyncPayloadBuilders.enqueueInvoiceSnapshot(
            _db,
            isOrder: false,
            id: pid,
          );
        }
      });
      return Success(updated);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update movement: $e', cause: st),
      );
    }
  }

  /// Rebuilds [balance_after] for every movement of [productId] in time order.
  Future<void> _recomputeProductBalances(DatabaseExecutor txn, int productId) async {
    final products = await txn.query(
      'products',
      columns: ['current_stock'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (products.isEmpty) return;
    final current = (products.first['current_stock'] as num).toDouble();
    final moves = await txn.query(
      'stock_movements',
      columns: ['id', 'quantity'],
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at ASC, id ASC',
    );
    final totalDelta = moves.fold<double>(
      0,
      (sum, row) => sum + (row['quantity'] as num).toDouble(),
    );
    var balance = current - totalDelta;
    for (final row in moves) {
      balance += (row['quantity'] as num).toDouble();
      await txn.update(
        'stock_movements',
        {'balance_after': balance},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  @override
  Future<Result<List<StockMovementModel>>> getWasteRemnants({
    DateTime? from,
    DateTime? to,
  }) {
    return getMovements(
      type: StockMovementType.waste,
      from: from,
      to: to,
      limit: 50,
    );
  }

  @override
  Future<Result<WarehouseCapacity>> getWarehouseCapacity() async {
    try {
      final setting = await _db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['warehouse_capacity'],
        limit: 1,
      );
      final capacity = setting.isEmpty
          ? 1600.0
          : double.tryParse(setting.first['value'] as String? ?? '') ?? 1600;
      final usedRow = await _db.rawQuery('''
        SELECT COALESCE(SUM(current_stock), 0) AS used
        FROM products WHERE is_archived = 0 AND track_stock_by_sheet = 1
      ''');
      final used = (usedRow.first['used'] as num?)?.toDouble() ?? 0;
      return Success(WarehouseCapacity(used: used, capacity: capacity));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load warehouse capacity: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<OverviewStats>> getOverviewStats({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final now = DateTime.now();
      final todayStart = ShamsiDates.dateOnly(now);
      final weekRange = ShamsiDates.thisWeek(now);
      final weekStart = weekRange.$1;
      final monthRange = ShamsiDates.thisMonth(now);
      final rangeFrom = from ?? monthRange.$1;
      final rangeTo = to ?? monthRange.$2;

      final productAgg = await _db.rawQuery('''
        SELECT
          COUNT(*) AS total_products,
          SUM(CASE WHEN current_stock > 0 AND current_stock <= minimum_stock_alert THEN 1 ELSE 0 END) AS low_stock,
          SUM(CASE WHEN current_stock <= 0 THEN 1 ELSE 0 END) AS out_of_stock,
          COALESCE(SUM(current_stock * cost_price), 0) AS inventory_value
        FROM products WHERE is_archived = 0
      ''');

      final movementAgg = await _db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN quantity > 0 AND created_at >= ? THEN quantity ELSE 0 END), 0) AS today_in,
          COALESCE(SUM(CASE WHEN quantity < 0 AND created_at >= ? THEN ABS(quantity) ELSE 0 END), 0) AS today_out,
          COALESCE(SUM(CASE WHEN quantity > 0 AND created_at >= ? THEN quantity ELSE 0 END), 0) AS week_in,
          COALESCE(SUM(CASE WHEN quantity < 0 AND created_at >= ? THEN ABS(quantity) ELSE 0 END), 0) AS week_out
        FROM stock_movements
        ''',
        [
          todayStart.toIso8601String(),
          todayStart.toIso8601String(),
          weekStart.toIso8601String(),
          weekStart.toIso8601String(),
        ],
      );

      final warehouseCount = firstIntValue(
            await _db.rawQuery(
              'SELECT COUNT(*) FROM warehouses WHERE is_active = 1',
            ),
          ) ??
          0;

      final supplierCount = firstIntValue(
            await _db.rawQuery(
              'SELECT COUNT(*) FROM suppliers WHERE is_archived = 0',
            ),
          ) ??
          0;
      final customerCount = firstIntValue(
            await _db.rawQuery(
              '''
              SELECT COUNT(*) FROM customers
              WHERE is_archived = 0
                AND LOWER(name) != 'walk-in customer'
              ''',
            ),
          ) ??
          0;

      final movementTrend = await _buildWeeklyTrend(weekStart);

      final categoryRows = await _db.rawQuery('''
        SELECT c.name, c.color, COUNT(p.id) AS cnt
        FROM categories c
        LEFT JOIN products p ON p.category_id = c.id AND p.is_archived = 0
        WHERE c.is_active = 1
        GROUP BY c.id
        HAVING cnt > 0
        ORDER BY cnt DESC
        LIMIT 8
      ''');
      final catTotal =
          categoryRows.fold<int>(0, (s, r) => s + ((r['cnt'] as int?) ?? 0));

      final activityRows = await _db.query(
        'audit_logs',
        orderBy: 'created_at DESC',
        limit: 12,
      );

      final alertRows = await _db.rawQuery('''
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
        LIMIT 20
      ''');
      final overviewAlerts = <InventoryAlert>[];
      for (final r in alertRows) {
        overviewAlerts.addAll(ProductAlertHelper.fromProductRow(r));
      }
      overviewAlerts.sort(
        (a, b) => ProductAlertHelper.statusPriority(a.status)
            .compareTo(ProductAlertHelper.statusPriority(b.status)),
      );

      final topRows = await _db.rawQuery(
        '''
        SELECT p.id, p.name, p.image_path, c.name AS category_name,
               COALESCE(SUM(ABS(sm.quantity)), 0) AS units,
               COALESCE(SUM(CASE
                 WHEN sm.unit_price IS NOT NULL THEN ABS(sm.quantity) * sm.unit_price
                 ELSE 0 END), 0) AS revenue
        FROM stock_movements sm
        JOIN products p ON p.id = sm.product_id
        LEFT JOIN categories c ON c.id = p.category_id
        WHERE sm.quantity < 0
          AND sm.created_at >= ? AND sm.created_at <= ?
        GROUP BY p.id
        ORDER BY units DESC
        LIMIT 8
        ''',
        [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
      );

      final salesCurrencyRows = await _db.rawQuery(
        '''
        SELECT COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
               COALESCE(SUM(total), 0) AS total
        FROM orders
        WHERE status != 'void'
          AND created_at >= ? AND created_at <= ?
        GROUP BY currency_code
        HAVING total > 0
        ORDER BY total DESC
        ''',
        [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
      );
      final purchaseCurrencyRows = await _db.rawQuery(
        '''
        SELECT COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
               COALESCE(SUM(total), 0) AS total
        FROM purchases
        WHERE status != 'void'
          AND created_at >= ? AND created_at <= ?
        GROUP BY currency_code
        HAVING total > 0
        ORDER BY total DESC
        ''',
        [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
      );
      final expenseCurrencyRows = await _db.rawQuery(
        '''
        SELECT COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
               COALESCE(SUM(amount), 0) AS total
        FROM expenses
        WHERE expense_date >= ? AND expense_date <= ?
        GROUP BY currency_code
        HAVING total > 0
        ORDER BY total DESC
        ''',
        [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
      );
      final orderCount =
          firstIntValue(
            await _db.rawQuery(
              '''
              SELECT COUNT(*) FROM orders
              WHERE status != 'void'
                AND created_at >= ? AND created_at <= ?
              ''',
              [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
            ),
          ) ??
          0;
      final purchaseCount =
          firstIntValue(
            await _db.rawQuery(
              '''
              SELECT COUNT(*) FROM purchases
              WHERE status != 'void'
                AND created_at >= ? AND created_at <= ?
              ''',
              [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
            ),
          ) ??
          0;
      final employeeLiabilityRows = await _db.rawQuery('''
        SELECT COALESCE(NULLIF(TRIM(e.salary_currency), ''), 'AFN') AS currency_code,
               COALESCE(SUM(
                 e.base_salary - COALESCE((
                   SELECT SUM(es.amount) FROM employee_salaries es
                   WHERE es.employee_id = e.id
                 ), 0)
               ), 0) AS total
        FROM employees e
        WHERE e.is_active = 1
        GROUP BY currency_code
        HAVING total != 0
        ORDER BY total DESC
      ''');
      final employeeWithdrawalRows = await _db.rawQuery(
        '''
        SELECT COALESCE(NULLIF(TRIM(currency), ''), 'AFN') AS currency_code,
               COALESCE(SUM(amount), 0) AS total
        FROM employee_salaries
        WHERE paid_at >= ? AND paid_at <= ?
        GROUP BY currency_code
        HAVING total > 0
        ORDER BY total DESC
        ''',
        [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
      );

      final recentOrderRows = await _db.query(
        'orders',
        columns: [
          'id',
          'invoice_number',
          'partner_name',
          'total',
          'currency_code',
          'created_at',
        ],
        where: "status != 'void' AND created_at >= ? AND created_at <= ?",
        whereArgs: [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
        orderBy: 'created_at DESC',
        limit: 8,
      );
      final recentPurchaseRows = await _db.query(
        'purchases',
        columns: [
          'id',
          'invoice_number',
          'partner_name',
          'total',
          'currency_code',
          'created_at',
        ],
        where: "status != 'void' AND created_at >= ? AND created_at <= ?",
        whereArgs: [rangeFrom.toIso8601String(), rangeTo.toIso8601String()],
        orderBy: 'created_at DESC',
        limit: 8,
      );

      final outstandingRows = await _db.rawQuery('''
        SELECT
          'receivable' AS side,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(MAX(total - amount_paid, 0)), 0) AS outstanding
        FROM orders
        WHERE status != 'void'
          AND (total - amount_paid) > 0
        GROUP BY currency_code
        UNION ALL
        SELECT
          'payable' AS side,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(MAX(total - amount_paid, 0)), 0) AS outstanding
        FROM purchases
        WHERE status != 'void'
          AND (total - amount_paid) > 0
        GROUP BY currency_code
      ''');

      final customerLoanRows = await _db.rawQuery('''
        SELECT
          o.partner_id AS customer_id,
          COALESCE(
            NULLIF(TRIM(c.name), ''),
            NULLIF(TRIM(o.partner_name), ''),
            '—'
          ) AS name,
          c.phone AS phone,
          COALESCE(NULLIF(TRIM(o.currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(MAX(o.total - o.amount_paid, 0)), 0) AS outstanding
        FROM orders o
        LEFT JOIN customers c
          ON o.partner_type = 'customer' AND c.id = o.partner_id
        WHERE o.status != 'void'
          AND (o.total - o.amount_paid) > 0
        GROUP BY
          o.partner_id,
          COALESCE(
            NULLIF(TRIM(c.name), ''),
            NULLIF(TRIM(o.partner_name), ''),
            '—'
          ),
          c.phone,
          COALESCE(NULLIF(TRIM(o.currency_code), ''), 'AFN')
        ORDER BY outstanding DESC
        LIMIT 40
      ''');

      List<CurrencyMoneyTotal> parseSide(String side) {
        return outstandingRows
            .where((r) => r['side'] == side)
            .map(
              (r) => CurrencyMoneyTotal(
                currencyCode: r['currency_code'] as String,
                amount: (r['outstanding'] as num?)?.toDouble() ?? 0,
              ),
            )
            .where((t) => t.amount > 0)
            .toList();
      }

      final loanByCustomer = <String, OverviewCustomerLoan>{};
      for (final r in customerLoanRows) {
        final amount = (r['outstanding'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        final id = r['customer_id'] as int?;
        final name = (r['name'] as String?)?.trim().isNotEmpty == true
            ? (r['name'] as String).trim()
            : '—';
        final key = id != null ? 'id:$id' : 'name:${name.toLowerCase()}';
        final money = CurrencyMoneyTotal(
          currencyCode: r['currency_code'] as String,
          amount: amount,
        );
        final existing = loanByCustomer[key];
        if (existing == null) {
          loanByCustomer[key] = OverviewCustomerLoan(
            customerId: id,
            name: name,
            phone: r['phone'] as String?,
            outstanding: [money],
          );
        } else {
          loanByCustomer[key] = OverviewCustomerLoan(
            customerId: existing.customerId,
            name: existing.name,
            phone: existing.phone ?? r['phone'] as String?,
            outstanding: [...existing.outstanding, money],
          );
        }
      }
      final customerLoans = loanByCustomer.values.toList()
        ..sort((a, b) => b.outstandingTotal.compareTo(a.outstandingTotal));
      if (customerLoans.length > 12) {
        customerLoans.removeRange(12, customerLoans.length);
      }

      final pa = productAgg.first;
      final ma = movementAgg.first;
      final todayIn = (ma['today_in'] as num?)?.toDouble() ?? 0;
      final todayOut = (ma['today_out'] as num?)?.toDouble() ?? 0;
      final weekIn = (ma['week_in'] as num?)?.toDouble() ?? 0;
      final weekOut = (ma['week_out'] as num?)?.toDouble() ?? 0;

      List<CurrencyMoneyTotal> mapCurrencyRows(List<Map<String, Object?>> rows) {
        return rows
            .map(
              (r) => CurrencyMoneyTotal(
                currencyCode:
                    (r['currency_code'] as String?)?.trim().isNotEmpty == true
                        ? (r['currency_code'] as String).trim()
                        : 'AFN',
                amount: (r['total'] as num?)?.toDouble() ?? 0,
              ),
            )
            .where((t) => t.amount > 0)
            .toList();
      }

      final salesByCurrency = mapCurrencyRows(salesCurrencyRows);
      final purchasesByCurrency = mapCurrencyRows(purchaseCurrencyRows);
      final expensesByCurrency = mapCurrencyRows(expenseCurrencyRows);
      final employeeLiabilitiesByCurrency =
          mapCurrencyRows(employeeLiabilityRows);
      final employeeWithdrawalsByCurrency =
          mapCurrencyRows(employeeWithdrawalRows);
      final monthSales =
          salesByCurrency.fold<double>(0, (s, t) => s + t.amount);
      final monthPurchases =
          purchasesByCurrency.fold<double>(0, (s, t) => s + t.amount);
      final monthExpenses =
          expensesByCurrency.fold<double>(0, (s, t) => s + t.amount);
      final employeeLiabilities = employeeLiabilitiesByCurrency.fold<double>(
        0,
        (s, t) => s + t.amount,
      );
      final employeeWithdrawals = employeeWithdrawalsByCurrency.fold<double>(
        0,
        (s, t) => s + t.amount,
      );

      OverviewInvoiceStub mapInvoice(Map<String, Object?> r) {
        return OverviewInvoiceStub(
          id: r['id'] as int,
          invoiceNumber: (r['invoice_number'] as String?) ?? '',
          partnerName: r['partner_name'] as String?,
          total: (r['total'] as num?)?.toDouble() ?? 0,
          currencyCode: r['currency_code'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
        );
      }

      return Success(
        OverviewStats(
          todayInbound: todayIn,
          todayOutbound: todayOut,
          weekInbound: weekIn,
          weekOutbound: weekOut,
          salesByCurrency: salesByCurrency,
          purchasesByCurrency: purchasesByCurrency,
          expensesByCurrency: expensesByCurrency,
          monthSalesTotal: monthSales,
          monthPurchaseTotal: monthPurchases,
          monthExpensesTotal: monthExpenses,
          orderCount: orderCount,
          purchaseCount: purchaseCount,
          employeeLiabilities: employeeLiabilities,
          employeeLiabilitiesByCurrency: employeeLiabilitiesByCurrency,
          employeeWithdrawals: employeeWithdrawals,
          employeeWithdrawalsByCurrency: employeeWithdrawalsByCurrency,
          todaySales: monthSales,
          pendingOrders: orderCount,
          totalSales: monthSales,
          monthlyRevenue: monthSales,
          totalProducts: (pa['total_products'] as int?) ?? 0,
          lowStock: (pa['low_stock'] as int?) ?? 0,
          outOfStock: (pa['out_of_stock'] as int?) ?? 0,
          warehouseCount: warehouseCount,
          companyCount: supplierCount + customerCount,
          customerCount: customerCount,
          inventoryValue: (pa['inventory_value'] as num?)?.toDouble() ?? 0,
          receivableOutstanding: parseSide('receivable'),
          payableOutstanding: parseSide('payable'),
          customerLoans: customerLoans,
          movementTrend: movementTrend,
          salesTrend: movementTrend,
          categoryShares: categoryRows
              .map(
                (r) => CategoryShare(
                  name: r['name'] as String,
                  count: (r['cnt'] as int?) ?? 0,
                  percent: catTotal == 0
                      ? 0
                      : (((r['cnt'] as int?) ?? 0) / catTotal) * 100,
                  color: r['color'] as String?,
                ),
              )
              .toList(),
          recentActivity: activityRows
              .map(
                (r) => AuditLogModelStub(
                  summary: r['summary'] as String,
                  action: r['action'] as String,
                  createdAt: DateTime.parse(r['created_at'] as String),
                ),
              )
              .toList(),
          recentOrders: recentOrderRows.map(mapInvoice).toList(),
          recentPurchases: recentPurchaseRows.map(mapInvoice).toList(),
          alerts: overviewAlerts.take(10).toList(),
          topProducts: topRows
              .map(
                (r) => TopProductStat(
                  productId: r['id'] as int,
                  name: r['name'] as String,
                  categoryName: r['category_name'] as String?,
                  imagePath: r['image_path'] as String?,
                  unitsSold: (r['units'] as num?)?.toDouble() ?? 0,
                  revenue: (r['revenue'] as num?)?.toDouble() ?? 0,
                ),
              )
              .toList(),
        ),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load overview: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<Map<String, CompanyPartnerBalances>>> getCompanyBalances() async {
    try {
      final receivableRows = await _db.rawQuery('''
        SELECT
          partner_type,
          partner_id,
          LOWER(TRIM(COALESCE(partner_name, ''))) AS partner_key,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(MAX(total - amount_paid, 0)), 0) AS outstanding
        FROM orders
        WHERE status != 'void'
          AND (total - amount_paid) > 0
        GROUP BY partner_type, partner_id, partner_key, currency_code
      ''');
      final payableRows = await _db.rawQuery('''
        SELECT
          partner_type,
          partner_id,
          LOWER(TRIM(COALESCE(partner_name, ''))) AS partner_key,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(MAX(total - amount_paid, 0)), 0) AS outstanding
        FROM purchases
        WHERE status != 'void'
          AND (total - amount_paid) > 0
        GROUP BY partner_type, partner_id, partner_key, currency_code
      ''');
      final salesRows = await _db.rawQuery('''
        SELECT
          partner_type,
          partner_id,
          LOWER(TRIM(COALESCE(partner_name, ''))) AS partner_key,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(total), 0) AS amount
        FROM orders
        WHERE status != 'void'
        GROUP BY partner_type, partner_id, partner_key, currency_code
      ''');
      final purchaseRows = await _db.rawQuery('''
        SELECT
          partner_type,
          partner_id,
          LOWER(TRIM(COALESCE(partner_name, ''))) AS partner_key,
          COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN') AS currency_code,
          COALESCE(SUM(total), 0) AS amount
        FROM purchases
        WHERE status != 'void'
        GROUP BY partner_type, partner_id, partner_key, currency_code
      ''');

      final receivableMap = <String, List<CurrencyMoneyTotal>>{};
      final payableMap = <String, List<CurrencyMoneyTotal>>{};
      final salesMap = <String, List<CurrencyMoneyTotal>>{};
      final purchasesMap = <String, List<CurrencyMoneyTotal>>{};

      void addRows(
        List<Map<String, Object?>> rows,
        Map<String, List<CurrencyMoneyTotal>> target, {
        required String amountKey,
      }) {
        for (final r in rows) {
          final amount = (r[amountKey] as num?)?.toDouble() ?? 0;
          if (amount <= 0) continue;
          final refType = (r['partner_type'] as String?)?.trim() ?? '';
          final refId = r['partner_id'] as int?;
          final partnerKey = (r['partner_key'] as String?) ?? '';
          final keys = <String>[];
          if (refType.isNotEmpty && refId != null) {
            keys.add('$refType:$refId');
          }
          if (partnerKey.isNotEmpty) {
            keys.add('name:$partnerKey');
          }
          if (keys.isEmpty) continue;
          final total = CurrencyMoneyTotal(
            currencyCode: r['currency_code'] as String,
            amount: amount,
          );
          for (final key in keys) {
            target.putIfAbsent(key, () => []).add(total);
          }
        }
      }

      addRows(receivableRows, receivableMap, amountKey: 'outstanding');
      addRows(payableRows, payableMap, amountKey: 'outstanding');
      addRows(salesRows, salesMap, amountKey: 'amount');
      addRows(purchaseRows, purchasesMap, amountKey: 'amount');

      final allKeys = {
        ...receivableMap.keys,
        ...payableMap.keys,
        ...salesMap.keys,
        ...purchasesMap.keys,
      };
      final map = <String, CompanyPartnerBalances>{};
      for (final key in allKeys) {
        map[key] = CompanyPartnerBalances(
          receivable: receivableMap[key] ?? const [],
          payable: payableMap[key] ?? const [],
          purchases: purchasesMap[key] ?? const [],
          sales: salesMap[key] ?? const [],
        );
      }
      return Success(map);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load company balances: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<List<CompanyPaymentModel>>> getCompanyPayments({
    required String partnerType,
    required int partnerId,
  }) async {
    try {
      final rows = await _db.query(
        'company_payments',
        where: 'partner_type = ? AND partner_id = ? AND is_voided = 0',
        whereArgs: [partnerType, partnerId],
        orderBy: 'paid_at DESC, id DESC',
      );
      return Success(rows.map(CompanyPaymentModel.fromMap).toList());
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load company payments: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<CompanyPaymentModel>> addCompanyPayment({
    required String partnerType,
    required int partnerId,
    String? partnerName,
    required double amount,
    required String currency,
    required DateTime paidAt,
    required PaymentSettlementSide settlementSide,
    String? notes,
  }) async {
    try {
      if (amount <= 0) {
        return const FailureResult(
          ValidationFailure('Payment amount must be greater than zero.'),
        );
      }
      final code = currency.trim().isEmpty ? 'AFN' : currency.trim();
      final now = DateTime.now();
      late CompanyPaymentModel created;

      await _db.transaction((txn) async {
        final paymentId = await txn.insert('company_payments', {
          'partner_type': partnerType,
          'partner_id': partnerId,
          'partner_name': partnerName,
          'amount': amount,
          'currency': code,
          'paid_at': paidAt.toIso8601String(),
          'payment_method': 'cash',
          'settlement_side': settlementSide.dbValue,
          'notes': notes,
          'is_voided': 0,
          'created_at': now.toIso8601String(),
        });

        await _allocatePayment(
          txn,
          paymentId: paymentId,
          partnerType: partnerType,
          partnerId: partnerId,
          partnerName: partnerName,
          amount: amount,
          currency: code,
          settlementSide: settlementSide,
        );

        final refreshed = await txn.query(
          'company_payments',
          where: 'id = ?',
          whereArgs: [paymentId],
          limit: 1,
        );
        created = CompanyPaymentModel.fromMap(refreshed.first);
      });

      await SyncOutbox.group(() async {
        await _enqueueAllocatedMovementsSync(created.id);
        if (partnerType == 'customer' ||
            settlementSide == PaymentSettlementSide.receivable) {
          await CustomerRepositoryImpl.refreshBalancesFromOrders(_db);
          final rows = await _db.query(
            'customers',
            where: 'id = ?',
            whereArgs: [partnerId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            await SyncOutbox.enqueue(
              entityType: SyncEntityTypes.customers,
              entityId: '$partnerId',
              operation: SyncOperation.update,
              data: SyncPayloadBuilders.customerFromRow(rows.first),
            );
          }
        }
        await _enqueueCompanyPaymentSync(created, SyncOperation.create);
      });

      return Success(created);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to add company payment: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<CompanyPaymentModel>> updateCompanyPayment({
    required int paymentId,
    required double amount,
    required String currency,
    required DateTime paidAt,
    required PaymentSettlementSide settlementSide,
    String? notes,
  }) async {
    try {
      if (amount <= 0) {
        return const FailureResult(
          ValidationFailure('Payment amount must be greater than zero.'),
        );
      }
      final code = currency.trim().isEmpty ? 'AFN' : currency.trim();
      late CompanyPaymentModel updated;
      late Set<int> touchedMovementIds;

      await _db.transaction((txn) async {
        final rows = await txn.query(
          'company_payments',
          where: 'id = ?',
          whereArgs: [paymentId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Payment not found.');
        }
        final existing = CompanyPaymentModel.fromMap(rows.first);
        final before = await _allocationMovementIds(txn, paymentId);
        await _reversePaymentAllocations(txn, paymentId);

        await txn.update(
          'company_payments',
          {
            'amount': amount,
            'currency': code,
            'paid_at': paidAt.toIso8601String(),
            'payment_method': 'cash',
            'settlement_side': settlementSide.dbValue,
            'notes': notes,
            'is_voided': 0,
          },
          where: 'id = ?',
          whereArgs: [paymentId],
        );

        await _allocatePayment(
          txn,
          paymentId: paymentId,
          partnerType: existing.partnerType,
          partnerId: existing.partnerId,
          partnerName: existing.partnerName,
          amount: amount,
          currency: code,
          settlementSide: settlementSide,
        );

        final after = await _allocationMovementIds(txn, paymentId);
        touchedMovementIds = {...before, ...after};

        final refreshed = await txn.query(
          'company_payments',
          where: 'id = ?',
          whereArgs: [paymentId],
          limit: 1,
        );
        updated = CompanyPaymentModel.fromMap(refreshed.first);
      });

      await SyncOutbox.group(() async {
        await _enqueueMovementsPaidAmountSync(touchedMovementIds);
        await _enqueueCompanyPaymentSync(updated, SyncOperation.update);
      });

      return Success(updated);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update company payment: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> deleteCompanyPayment(int paymentId) async {
    try {
      late Set<int> touchedMovementIds;
      await _db.transaction((txn) async {
        final rows = await txn.query(
          'company_payments',
          where: 'id = ?',
          whereArgs: [paymentId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundFailure('Payment not found.');
        }
        touchedMovementIds = await _allocationMovementIds(txn, paymentId);
        await _reversePaymentAllocations(txn, paymentId);
        await txn.delete(
          'company_payment_allocations',
          where: 'payment_id = ?',
          whereArgs: [paymentId],
        );
        await txn.delete(
          'company_payments',
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      });
      await SyncOutbox.group(() async {
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.companyPayments,
          entityId: '$paymentId',
          operation: SyncOperation.delete,
          data: {'id': paymentId, 'deleted': true},
        );
        await _enqueueMovementsPaidAmountSync(touchedMovementIds);
      });
      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete company payment: $e', cause: st),
      );
    }
  }

  Future<Set<int>> _allocationMovementIds(
    DatabaseExecutor txn,
    int paymentId,
  ) async {
    final rows = await txn.query(
      'company_payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );
    final ids = <int>{};
    for (final r in rows) {
      final mid = r['movement_id'] as int?;
      if (mid != null) ids.add(mid);
      final purchaseId = r['purchase_id'] as int?;
      final orderId = r['order_id'] as int?;
      if (purchaseId != null) {
        final moves = await txn.query(
          'stock_movements',
          columns: ['id'],
          where: 'purchase_id = ?',
          whereArgs: [purchaseId],
        );
        for (final m in moves) {
          ids.add(m['id'] as int);
        }
      }
      if (orderId != null) {
        final moves = await txn.query(
          'stock_movements',
          columns: ['id'],
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        for (final m in moves) {
          ids.add(m['id'] as int);
        }
      }
    }
    return ids;
  }

  Future<void> _enqueueAllocatedMovementsSync(int paymentId) async {
    final ids = await _allocationMovementIds(_db, paymentId);
    await _enqueueMovementsPaidAmountSync(ids);
  }

  /// Queues the movements whose paid amount changed, then their invoices
  /// (whose amount_paid / payment_status changed with them).
  Future<void> _enqueueMovementsPaidAmountSync(Set<int> movementIds) async {
    if (movementIds.isEmpty) return;
    final orderIds = <int>{};
    final purchaseIds = <int>{};
    for (final id in movementIds.toList()..sort()) {
      final rows = await _db.query(
        'stock_movements',
        columns: ['order_id', 'purchase_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final orderId = rows.first['order_id'];
      final purchaseId = rows.first['purchase_id'];
      if (orderId is int) orderIds.add(orderId);
      if (purchaseId is int) purchaseIds.add(purchaseId);
      await SyncPayloadBuilders.enqueueMovementSnapshot(_db, id);
    }
    for (final id in orderIds) {
      await SyncPayloadBuilders.enqueueInvoiceSnapshot(
        _db,
        isOrder: true,
        id: id,
      );
    }
    for (final id in purchaseIds) {
      await SyncPayloadBuilders.enqueueInvoiceSnapshot(
        _db,
        isOrder: false,
        id: id,
      );
    }
  }

  Future<void> _enqueueCompanyPaymentSync(
    CompanyPaymentModel payment,
    SyncOperation operation,
  ) async {
    final rows = await _db.query(
      'company_payments',
      where: 'id = ?',
      whereArgs: [payment.id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final allocs = await _db.query(
      'company_payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [payment.id],
    );
    await SyncOutbox.enqueue(
      entityType: SyncEntityTypes.companyPayments,
      entityId: '${payment.id}',
      operation: operation,
      data: SyncPayloadBuilders.companyPaymentFromRow(rows.first, allocs),
    );
  }

  Future<void> _reversePaymentAllocations(
    DatabaseExecutor txn,
    int paymentId,
  ) async {
    final allocs = await txn.query(
      'company_payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );
    for (final a in allocs) {
      final amount = (a['amount'] as num).toDouble();
      final movementId = a['movement_id'] as int?;
      final purchaseId = a['purchase_id'] as int?;
      final orderId = a['order_id'] as int?;

      if (purchaseId != null) {
        await _adjustInvoicePaid(
          txn,
          table: 'purchases',
          id: purchaseId,
          delta: -amount,
        );
        await _adjustLinkedMovementsPaid(
          txn,
          purchaseId: purchaseId,
          delta: -amount,
        );
      } else if (orderId != null) {
        await _adjustInvoicePaid(
          txn,
          table: 'orders',
          id: orderId,
          delta: -amount,
        );
        await _adjustLinkedMovementsPaid(
          txn,
          orderId: orderId,
          delta: -amount,
        );
      } else if (movementId != null) {
        // Legacy allocation: movement-only.
        final moves = await txn.query(
          'stock_movements',
          columns: ['paid_amount'],
          where: 'id = ?',
          whereArgs: [movementId],
          limit: 1,
        );
        if (moves.isNotEmpty) {
          final current =
              (moves.first['paid_amount'] as num?)?.toDouble() ?? 0;
          final next = current - amount;
          await txn.update(
            'stock_movements',
            {'paid_amount': next < 0 ? 0 : next},
            where: 'id = ?',
            whereArgs: [movementId],
          );
        }
      }
    }
    await txn.delete(
      'company_payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );
  }

  Future<void> _adjustInvoicePaid(
    DatabaseExecutor txn, {
    required String table,
    required int id,
    required double delta,
  }) async {
    final rows = await txn.query(
      table,
      columns: ['total', 'amount_paid'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final total = (rows.first['total'] as num?)?.toDouble() ?? 0;
    final paid = (rows.first['amount_paid'] as num?)?.toDouble() ?? 0;
    var next = paid + delta;
    if (next < 0) next = 0;
    if (next > total) next = total;
    final status = next + 0.0001 >= total
        ? 'paid'
        : (next > 0 ? 'partial' : 'unpaid');
    await txn.update(
      table,
      {
        'amount_paid': next,
        'payment_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Applies [delta] to linked movements FIFO by outstanding (or reverse).
  Future<void> _adjustLinkedMovementsPaid(
    DatabaseExecutor txn, {
    int? purchaseId,
    int? orderId,
    required double delta,
  }) async {
    if (purchaseId == null && orderId == null) return;
    final where = purchaseId != null
        ? 'purchase_id = ?'
        : 'order_id = ?';
    final id = purchaseId ?? orderId!;
    final rows = await txn.query(
      'stock_movements',
      where: where,
      whereArgs: [id],
      orderBy: 'created_at ASC, id ASC',
    );
    if (delta >= 0) {
      var remaining = delta;
      for (final row in rows) {
        if (remaining <= 0) break;
        final m = StockMovementModel.fromMap(row);
        final due = m.outstanding;
        if (due <= 0) continue;
        final applied = remaining < due ? remaining : due;
        await txn.update(
          'stock_movements',
          {'paid_amount': m.paidAmount + applied},
          where: 'id = ?',
          whereArgs: [m.id],
        );
        remaining -= applied;
      }
    } else {
      var remaining = -delta;
      for (final row in rows.reversed) {
        if (remaining <= 0) break;
        final m = StockMovementModel.fromMap(row);
        if (m.paidAmount <= 0) continue;
        final take = remaining < m.paidAmount ? remaining : m.paidAmount;
        await txn.update(
          'stock_movements',
          {'paid_amount': m.paidAmount - take},
          where: 'id = ?',
          whereArgs: [m.id],
        );
        remaining -= take;
      }
    }
  }

  Future<void> _allocatePayment(
    DatabaseExecutor txn, {
    required int paymentId,
    required String partnerType,
    required int partnerId,
    String? partnerName,
    required double amount,
    required String currency,
    required PaymentSettlementSide settlementSide,
  }) async {
    // Payable → unpaid purchases; receivable → unpaid sales orders.
    final table = settlementSide == PaymentSettlementSide.payable
        ? 'purchases'
        : 'orders';
    final idColumn = settlementSide == PaymentSettlementSide.payable
        ? 'purchase_id'
        : 'order_id';

    final invoiceRows = await txn.rawQuery(
      '''
      SELECT *
      FROM $table
      WHERE status != 'void'
        AND (total - amount_paid) > 0
        AND UPPER(COALESCE(NULLIF(TRIM(currency_code), ''), 'AFN')) = UPPER(?)
        AND (
          (partner_type = ? AND partner_id = ?)
          OR (
            LENGTH(TRIM(?)) > 0
            AND LOWER(TRIM(COALESCE(partner_name, ''))) = LOWER(TRIM(?))
          )
        )
      ORDER BY created_at ASC, id ASC
      ''',
      [
        currency,
        partnerType,
        partnerId,
        partnerName ?? '',
        partnerName ?? '',
      ],
    );

    // Currency compare case-insensitive.
    var remaining = amount;
    for (final row in invoiceRows) {
      if (remaining <= 0) break;
      final code = ((row['currency_code'] as String?) ?? 'AFN').trim();
      if (code.toUpperCase() != currency.toUpperCase()) continue;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      final paid = (row['amount_paid'] as num?)?.toDouble() ?? 0;
      final due = total - paid;
      if (due <= 0) continue;
      final applied = remaining < due ? remaining : due;
      final invoiceId = row['id'] as int;

      await _adjustInvoicePaid(
        txn,
        table: table,
        id: invoiceId,
        delta: applied,
      );
      if (settlementSide == PaymentSettlementSide.payable) {
        await _adjustLinkedMovementsPaid(
          txn,
          purchaseId: invoiceId,
          delta: applied,
        );
      } else {
        await _adjustLinkedMovementsPaid(
          txn,
          orderId: invoiceId,
          delta: applied,
        );
      }

      await txn.insert('company_payment_allocations', {
        'payment_id': paymentId,
        'movement_id': null,
        idColumn: invoiceId,
        'amount': applied,
      });
      remaining -= applied;
    }
  }

  @override
  Future<Result<List<SalesTrendPoint>>> getMovementChartTrend(
    OverviewChartPeriod period,
  ) async {
    try {
      switch (period) {
        case OverviewChartPeriod.weekly:
          final weekStart = ShamsiDates.thisWeek().$1;
          return Success(await _buildWeeklyTrend(weekStart));
        case OverviewChartPeriod.monthly:
          return Success(await _buildMonthlyTrend());
        case OverviewChartPeriod.yearly:
          return Success(await _buildYearlyTrend());
      }
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load chart trend: $e', cause: st),
      );
    }
  }

  /// Saturday → Friday of the Shamsi week that contains [weekStart].
  Future<List<SalesTrendPoint>> _buildWeeklyTrend(DateTime weekStart) async {
    final weekEnd = ShamsiDates.endOfDay(weekStart.add(const Duration(days: 6)));
    final totals = await _sumMovementsByRange(
      from: weekStart,
      to: weekEnd,
      bucket: _TrendBucket.day,
    );

    return [
      for (var i = 0; i < 7; i++)
        () {
          final day = ShamsiDates.dateOnly(weekStart.add(Duration(days: i)));
          final key = _dayKey(day);
          final point = totals[key];
          final inbound = point?.inbound ?? 0;
          final outbound = point?.outbound ?? 0;
          return SalesTrendPoint(
            date: day,
            inbound: inbound,
            outbound: outbound,
            total: inbound + outbound,
          );
        }(),
    ];
  }

  /// Farvardin (1) → current Shamsi month of the current year; missing months = 0.
  Future<List<SalesTrendPoint>> _buildMonthlyTrend() async {
    final now = ShamsiDates.of(DateTime.now());
    final yearStart = Jalali(now.year, 1, 1).toDateTime();
    final yearEnd = ShamsiDates.endOfDay(
      Jalali(now.year, now.month, now.day).toDateTime(),
    );

    final totals = await _sumMovementsByRange(
      from: yearStart,
      to: yearEnd,
      bucket: _TrendBucket.month,
    );

    return [
      for (var month = 1; month <= now.month; month++)
        () {
          final monthStart = Jalali(now.year, month, 1).toDateTime();
          final key = _monthKey(now.year, month);
          final point = totals[key];
          final inbound = point?.inbound ?? 0;
          final outbound = point?.outbound ?? 0;
          return SalesTrendPoint(
            date: monthStart,
            inbound: inbound,
            outbound: outbound,
            total: inbound + outbound,
          );
        }(),
    ];
  }

  /// First Shamsi year with movement data → current Shamsi year; missing years = 0.
  Future<List<SalesTrendPoint>> _buildYearlyTrend() async {
    final now = ShamsiDates.of(DateTime.now());
    final earliestIso = await _db.rawQuery(
      'SELECT MIN(created_at) AS first_at FROM stock_movements',
    );
    final firstRaw = earliestIso.first['first_at'] as String?;
    final firstYear = firstRaw == null || firstRaw.isEmpty
        ? now.year
        : ShamsiDates.of(DateTime.parse(firstRaw)).year;

    final from = Jalali(firstYear, 1, 1).toDateTime();
    final to = ShamsiDates.endOfDay(
      Jalali(now.year, now.month, now.day).toDateTime(),
    );

    final totals = await _sumMovementsByRange(
      from: from,
      to: to,
      bucket: _TrendBucket.year,
    );

    return [
      for (var year = firstYear; year <= now.year; year++)
        () {
          final yearStart = Jalali(year, 1, 1).toDateTime();
          final key = '$year';
          final point = totals[key];
          final inbound = point?.inbound ?? 0;
          final outbound = point?.outbound ?? 0;
          return SalesTrendPoint(
            date: yearStart,
            inbound: inbound,
            outbound: outbound,
            total: inbound + outbound,
          );
        }(),
    ];
  }

  Future<Map<String, ({double inbound, double outbound})>> _sumMovementsByRange({
    required DateTime from,
    required DateTime to,
    required _TrendBucket bucket,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT created_at, quantity
      FROM stock_movements
      WHERE created_at >= ? AND created_at <= ?
      ''',
      [from.toIso8601String(), to.toIso8601String()],
    );

    final map = <String, ({double inbound, double outbound})>{};
    for (final row in rows) {
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (createdAt == null) continue;
      final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
      final j = ShamsiDates.of(createdAt);
      final key = switch (bucket) {
        _TrendBucket.day => _dayKey(ShamsiDates.dateOnly(createdAt)),
        _TrendBucket.month => _monthKey(j.year, j.month),
        _TrendBucket.year => '${j.year}',
      };
      final current = map[key] ?? (inbound: 0.0, outbound: 0.0);
      map[key] = qty >= 0
          ? (inbound: current.inbound + qty, outbound: current.outbound)
          : (inbound: current.inbound, outbound: current.outbound + qty.abs());
    }
    return map;
  }

  String _dayKey(DateTime day) {
    final local = day.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';
}

enum _TrendBucket { day, month, year }

