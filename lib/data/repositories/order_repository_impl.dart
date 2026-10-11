import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/database/invoice_numbers.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../core/utils/glass_cut_helper.dart';
import '../../domain/repositories/order_repository.dart';
import '../models/order_model.dart';
import '../models/report_models.dart';
import 'customer_repository_impl.dart';
import 'remnant_stock_helper.dart';

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl();

  Database get _db => AppDatabase.instance;

  Future<void> _syncCustomerBalancesAfterOrder({
    String? partnerType,
    int? partnerId,
  }) async {
    await CustomerRepositoryImpl.refreshBalancesFromOrders(_db);
    if (partnerType == 'customer' && partnerId != null) {
      final rows = await _db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [partnerId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.customers,
        entityId: '$partnerId',
        operation: SyncOperation.update,
        data: SyncPayloadBuilders.customerFromRow(rows.first),
      );
    }
  }

  @override
  Future<Result<PaginatedResult<OrderModel>>> list({
    String? search,
    DateTime? from,
    DateTime? to,
    String? paymentStatus,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int page = 1,
    int pageSize = 50,
    bool includeItems = false,
  }) async {
    try {
      final where = <String>["status != 'void'"];
      final args = <Object?>[];
      final q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where.add(
          '(invoice_number LIKE ? OR IFNULL(partner_name, \'\') LIKE ?)',
        );
        args.add('%$q%');
        args.add('%$q%');
      }
      if (from != null) {
        where.add('created_at >= ?');
        args.add(from.toIso8601String());
      }
      if (to != null) {
        where.add('created_at <= ?');
        args.add(to.toIso8601String());
      }
      if (paymentStatus != null && paymentStatus.isNotEmpty) {
        where.add('payment_status = ?');
        args.add(paymentStatus);
      }
      if (partnerType != null && partnerId != null) {
        final name = (partnerName ?? '').trim();
        if (name.isNotEmpty) {
          where.add(
            '((partner_type = ? AND partner_id = ?) OR '
            'LOWER(TRIM(IFNULL(partner_name, \'\'))) = LOWER(?))',
          );
          args.addAll([partnerType, partnerId, name]);
        } else {
          where.add('partner_type = ? AND partner_id = ?');
          args.addAll([partnerType, partnerId]);
        }
      }
      final whereSql = where.join(' AND ');
      final countRows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM orders WHERE $whereSql',
        args,
      );
      final total = (countRows.first['c'] as num?)?.toInt() ?? 0;
      final safePageSize = pageSize < 1 ? 50 : pageSize;
      final safePage = page < 1 ? 1 : page;
      final offset = (safePage - 1) * safePageSize;

      final rows = await _db.rawQuery(
        '''
        SELECT o.*,
          (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id)
            AS line_count
        FROM orders o
        WHERE $whereSql
        ORDER BY o.created_at DESC
        LIMIT ? OFFSET ?
        ''',
        [...args, safePageSize, offset],
      );

      final orders = <OrderModel>[];
      for (final row in rows) {
        final items = includeItems
            ? await _loadItems(row['id'] as int)
            : const <OrderItemModel>[];
        orders.add(OrderModel.fromMap(row, items: items));
      }
      return Success(
        PaginatedResult(
          items: orders,
          total: total,
          page: safePage,
          pageSize: safePageSize,
        ),
      );
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to list orders: $e', cause: st));
    }
  }

  @override
  Future<Result<OrderModel>> getById(int id) async {
    try {
      final rows = await _db.query('orders', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Order not found.'));
      }
      final items = await _loadItems(id);
      return Success(OrderModel.fromMap(rows.first, items: items));
    } catch (e, st) {
      return FailureResult(DatabaseFailure('Failed to load order: $e', cause: st));
    }
  }

  Future<List<OrderItemModel>> _loadItems(int orderId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT oi.*, p.image_path AS product_image_path
      FROM order_items oi
      LEFT JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = ?
      ORDER BY oi.id ASC
      ''',
      [orderId],
    );
    return rows.map(OrderItemModel.fromMap).toList();
  }

  Future<String> _nextInvoiceNumber(DatabaseExecutor db) {
    return nextSequentialInvoiceNumber(db, table: 'orders');
  }

  @override
  Future<Result<OrderModel>> createOutboundOrder({
    required List<OutboundOrderLineInput> lines,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    String? currencyCode,
    double discount = 0,
    required double amountPaid,
    String? notes,
    DateTime? createdAt,
  }) async {
    if (lines.isEmpty) {
      return const FailureResult(ValidationFailure('Cart is empty.'));
    }
    try {
      final now = createdAt ?? DateTime.now();
      final subtotal =
          lines.fold<double>(0, (s, l) => s + l.lineTotal);
      final disc = discount < 0 ? 0.0 : discount;
      final total = (subtotal - disc) < 0 ? 0.0 : (subtotal - disc);
      final paid = amountPaid < 0 ? 0.0 : amountPaid;
      final paymentStatus = paid + 0.0001 >= total
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');

      late String invoiceNumber;
      final syncMovements = <Map<String, dynamic>>[];
      final remnantIds = <int>[];
      final orderId = await _db.transaction((txn) async {
        invoiceNumber = await _nextInvoiceNumber(txn);
        final oid = await txn.insert('orders', {
          'invoice_number': invoiceNumber,
          'partner_type': partnerType,
          'partner_id': partnerId,
          'partner_name': partnerName,
          'currency_id': currencyId,
          'currency_code': currencyCode,
          'subtotal': subtotal,
          'discount': disc,
          'total': total,
          'amount_paid': paid,
          'payment_status': paymentStatus,
          'status': 'completed',
          'notes': notes,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });

        for (final line in lines) {
          final qty = line.quantity.abs();
          if (qty <= 0) {
            throw const ValidationFailure('Quantity must be positive.');
          }
          final productRows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [line.productId],
          );
          if (productRows.isEmpty) {
            throw NotFoundFailure('Product not found: ${line.productId}');
          }
          final product = productRows.first;
          final current =
              (product['current_stock'] as num).toDouble();
          final trackBySheet =
              (product['track_stock_by_sheet'] as int? ?? 0) == 1;
          final cut = GlassCutHelper.plan(
            parentLength: (product['standard_height'] as num?)?.toDouble(),
            parentWidth: (product['standard_width'] as num?)?.toDouble(),
            cutLength: line.lengthM,
            cutWidth: line.widthM,
            quantity: qty,
            trackStockBySheet: trackBySheet,
          );
          final deduct = cut.sheetsConsumed;
          final next = current - deduct;
          if (next < -0.0001) {
            throw ValidationFailure(
              'Not enough stock for ${line.productName}.',
            );
          }
          final warehouseId =
              line.warehouseId ?? product['warehouse_id'] as int?;
          final productUpdate = <String, Object?>{
            'current_stock': next < 0 ? 0 : next,
            'updated_at': now.toIso8601String(),
          };
          if (line.unitPrice > 0) {
            productUpdate['selling_price'] = line.unitPrice;
          }
          if (line.warehouseId != null) {
            productUpdate['warehouse_id'] = line.warehouseId;
          }
          await txn.update(
            'products',
            productUpdate,
            where: 'id = ?',
            whereArgs: [line.productId],
          );

          final parentLength =
              (product['standard_height'] as num?)?.toDouble();
          final parentWidth =
              (product['standard_width'] as num?)?.toDouble();
          final pieceArea = GlassCutHelper.pieceAreaM2(
            line.lengthM,
            line.widthM,
          );
          final saleNotes = GlassCutHelper.saleCutNotes(
            base: 'orders.invoiceTitle'.tr() + invoiceNumber,
            cut: cut,
            cutLength: line.lengthM,
            cutWidth: line.widthM,
            parentLength: parentLength,
            parentWidth: parentWidth,
          );

          final movementId = await txn.insert('stock_movements', {
            'product_id': line.productId,
            'movement_type': 'sale',
            'quantity': -deduct,
            'balance_after': next < 0 ? 0 : next,
            'reference_type': partnerType,
            'reference_id': partnerId,
            'notes': saleNotes,
            'partner_name': partnerName,
            'length_m': line.lengthM,
            'width_m': line.widthM,
            'area_m2': pieceArea,
            'parent_length_m': parentLength,
            'parent_width_m': parentWidth,
            'broken_qty': 0,
            'unit_price': line.unitPrice,
            'paid_amount': line.paidAmount < 0 ? 0 : line.paidAmount,
            'currency_id': line.currencyId ?? currencyId,
            'warehouse_id': warehouseId,
            'order_id': oid,
            'created_by': 'system',
            'created_at': now.toIso8601String(),
          });

          await txn.insert('order_items', {
            'order_id': oid,
            'product_id': line.productId,
            'product_name': line.productName,
            'quantity': qty,
            'unit_price': line.unitPrice,
            'line_total': line.lineTotal,
            'length_m': line.lengthM,
            'width_m': line.widthM,
            'area_m2': pieceArea,
            'paid_amount': line.paidAmount < 0 ? 0 : line.paidAmount,
            'currency_id': line.currencyId ?? currencyId,
            'movement_id': movementId,
            'warehouse_id': warehouseId,
          });

          if (cut.hasRemnant) {
            final rid = await RemnantStockHelper.upsertRemnant(
              txn: txn,
              parent: product,
              remnantLengthM: cut.remnantLengthM!,
              remnantWidthM: cut.remnantWidthM!,
              quantity: deduct,
              now: now,
              warehouseId: warehouseId,
              cutLengthM: line.lengthM,
              cutWidthM: line.widthM,
            );
            if (rid != null) remnantIds.add(rid);
          }

          syncMovements.add(SyncPayloadBuilders.movement(
            id: movementId,
            productId: line.productId,
            movementType: 'sale',
            quantity: -deduct,
            notes: saleNotes,
            referenceType: partnerType,
            referenceId: partnerId,
            partnerName: partnerName,
            lengthM: line.lengthM,
            widthM: line.widthM,
            areaM2: pieceArea,
            parentLengthM: parentLength,
            parentWidthM: parentWidth,
            brokenQty: 0,
            unitPrice: line.unitPrice,
            paidAmount: line.paidAmount < 0 ? 0 : line.paidAmount,
            currencyId: line.currencyId ?? currencyId,
            warehouseId: warehouseId,
            orderId: oid,
            createdAt: now.toIso8601String(),
            updatedAt: now.toIso8601String(),
          ));
        }
        return oid;
      });

      // New movements -> updated products -> the invoice last, as one group.
      await SyncOutbox.group(() async {
        for (final m in syncMovements) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '${m['id']}',
            operation: SyncOperation.create,
            data: m,
          );
        }
        for (final rid in remnantIds) {
          await RemnantStockHelper.enqueueRemnantProductSync(_db, rid);
        }
        final touchedProducts = <int>{
          for (final m in syncMovements)
            if (m['productId'] is int) m['productId'] as int,
        };
        for (final pid in touchedProducts) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await _syncCustomerBalancesAfterOrder(
          partnerType: partnerType,
          partnerId: partnerId,
        );
        await SyncPayloadBuilders.enqueueInvoiceSnapshot(
          _db,
          isOrder: true,
          id: orderId,
          operation: SyncOperation.create,
        );
      });

      return getById(orderId);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create order: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<OrderModel>> updateOrder({
    required int orderId,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    double? discount,
    double? amountPaid,
    String? notes,
  }) async {
    try {
      final existing = await getById(orderId);
      if (existing is FailureResult) return existing;
      final order = (existing as Success<OrderModel>).value;
      final now = DateTime.now();
      final disc = discount ?? order.discount;
      final total =
          (order.subtotal - disc) < 0 ? 0.0 : (order.subtotal - disc);
      final paid = amountPaid ?? order.amountPaid;
      final paymentStatus = paid + 0.0001 >= total
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');

      final partnerChanged =
          partnerName != null || partnerType != null || partnerId != null;
      await _db.transaction((txn) async {
        await txn.update(
          'orders',
          {
            if (partnerType != null) 'partner_type': partnerType,
            if (partnerId != null) 'partner_id': partnerId,
            if (partnerName != null) 'partner_name': partnerName,
            'discount': disc,
            'total': total,
            'amount_paid': paid,
            'payment_status': paymentStatus,
            if (notes != null) 'notes': notes,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );

        // Keep partner name on linked movements in sync.
        if (partnerChanged) {
          await txn.update(
            'stock_movements',
            {
              if (partnerName != null) 'partner_name': partnerName,
              if (partnerType != null) 'reference_type': partnerType,
              if (partnerId != null) 'reference_id': partnerId,
            },
            where: 'order_id = ?',
            whereArgs: [orderId],
          );
        }
      });

      await SyncOutbox.group(() async {
        if (partnerChanged) {
          final moves = await _db.query(
            'stock_movements',
            columns: ['id'],
            where: 'order_id = ?',
            whereArgs: [orderId],
            orderBy: 'id ASC',
          );
          for (final m in moves) {
            await SyncPayloadBuilders.enqueueMovementSnapshot(
              _db,
              m['id'] as int,
            );
          }
        }
        await SyncPayloadBuilders.enqueueInvoiceSnapshot(
          _db,
          isOrder: true,
          id: orderId,
        );
      });

      return getById(orderId);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to update order: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<OrderModel>> replaceOutboundOrder({
    required int orderId,
    required List<OutboundOrderLineInput> lines,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    String? currencyCode,
    double discount = 0,
    required double amountPaid,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      return const FailureResult(ValidationFailure('Cart is empty.'));
    }
    try {
      final existing = await getById(orderId);
      if (existing is FailureResult) return existing;
      final order = (existing as Success<OrderModel>).value;
      final now = DateTime.now();
      final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
      final disc = discount < 0 ? 0.0 : discount;
      final total = (subtotal - disc) < 0 ? 0.0 : (subtotal - disc);
      final paid = amountPaid < 0 ? 0.0 : amountPaid;
      final paymentStatus = paid + 0.0001 >= total
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');
      final invoiceNumber = order.invoiceNumber;
      final oldMovementIds = [
        for (final item in order.items)
          if (item.movementId != null) item.movementId!,
      ];
      final syncMovements = <Map<String, dynamic>>[];
      final remnantIds = <int>[];

      await _db.transaction((txn) async {
        // Reverse stock from previous invoice lines.
        for (final item in order.items) {
          final mid = item.movementId;
          if (mid == null) continue;
          final movRows = await txn.query(
            'stock_movements',
            where: 'id = ?',
            whereArgs: [mid],
          );
          if (movRows.isEmpty) continue;
          final mov = movRows.first;
          final productId = mov['product_id'] as int;
          final qty = (mov['quantity'] as num).toDouble();
          final productRows = await txn.query(
            'products',
            columns: ['current_stock'],
            where: 'id = ?',
            whereArgs: [productId],
          );
          if (productRows.isNotEmpty) {
            final current =
                (productRows.first['current_stock'] as num).toDouble();
            final restored = current - qty; // sale qty negative → increase
            await txn.update(
              'products',
              {
                'current_stock': restored,
                'updated_at': now.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [productId],
            );
          }
          await txn.delete(
            'stock_movements',
            where: 'id = ?',
            whereArgs: [mid],
          );
        }

        await txn.delete(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );

        await txn.update(
          'orders',
          {
            'partner_type': partnerType,
            'partner_id': partnerId,
            'partner_name': partnerName,
            'currency_id': currencyId,
            'currency_code': currencyCode,
            'subtotal': subtotal,
            'discount': disc,
            'total': total,
            'amount_paid': paid,
            'payment_status': paymentStatus,
            'notes': notes,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );

        for (final line in lines) {
          final qty = line.quantity.abs();
          if (qty <= 0) {
            throw const ValidationFailure('Quantity must be positive.');
          }
          final productRows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [line.productId],
          );
          if (productRows.isEmpty) {
            throw NotFoundFailure('Product not found: ${line.productId}');
          }
          final product = productRows.first;
          final current = (product['current_stock'] as num).toDouble();
          final trackBySheet =
              (product['track_stock_by_sheet'] as int? ?? 0) == 1;
          final cut = GlassCutHelper.plan(
            parentLength: (product['standard_height'] as num?)?.toDouble(),
            parentWidth: (product['standard_width'] as num?)?.toDouble(),
            cutLength: line.lengthM,
            cutWidth: line.widthM,
            quantity: qty,
            trackStockBySheet: trackBySheet,
          );
          final deduct = cut.sheetsConsumed;
          final next = current - deduct;
          if (next < -0.0001) {
            throw ValidationFailure(
              'Not enough stock for ${line.productName}.',
            );
          }
          final warehouseId =
              line.warehouseId ?? product['warehouse_id'] as int?;
          final productUpdate = <String, Object?>{
            'current_stock': next < 0 ? 0 : next,
            'updated_at': now.toIso8601String(),
          };
          if (line.unitPrice > 0) {
            productUpdate['selling_price'] = line.unitPrice;
          }
          if (line.warehouseId != null) {
            productUpdate['warehouse_id'] = line.warehouseId;
          }
          await txn.update(
            'products',
            productUpdate,
            where: 'id = ?',
            whereArgs: [line.productId],
          );

          final parentLength =
              (product['standard_height'] as num?)?.toDouble();
          final parentWidth =
              (product['standard_width'] as num?)?.toDouble();
          final pieceArea = GlassCutHelper.pieceAreaM2(
            line.lengthM,
            line.widthM,
          );
          final saleNotes = GlassCutHelper.saleCutNotes(
            base: 'orders.invoiceTitle'.tr() + invoiceNumber,
            cut: cut,
            cutLength: line.lengthM,
            cutWidth: line.widthM,
            parentLength: parentLength,
            parentWidth: parentWidth,
          );

          final movementId = await txn.insert('stock_movements', {
            'product_id': line.productId,
            'movement_type': 'sale',
            'quantity': -deduct,
            'balance_after': next < 0 ? 0 : next,
            'reference_type': partnerType,
            'reference_id': partnerId,
            'notes': saleNotes,
            'partner_name': partnerName,
            'length_m': line.lengthM,
            'width_m': line.widthM,
            'area_m2': pieceArea,
            'parent_length_m': parentLength,
            'parent_width_m': parentWidth,
            'broken_qty': 0,
            'unit_price': line.unitPrice,
            'paid_amount': line.paidAmount < 0 ? 0 : line.paidAmount,
            'currency_id': line.currencyId ?? currencyId,
            'warehouse_id': warehouseId,
            'order_id': orderId,
            'created_by': 'system',
            'created_at': order.createdAt.toIso8601String(),
          });

          await txn.insert('order_items', {
            'order_id': orderId,
            'product_id': line.productId,
            'product_name': line.productName,
            'quantity': qty,
            'unit_price': line.unitPrice,
            'line_total': line.lineTotal,
            'length_m': line.lengthM,
            'width_m': line.widthM,
            'area_m2': pieceArea,
            'paid_amount': line.paidAmount < 0 ? 0 : line.paidAmount,
            'currency_id': line.currencyId ?? currencyId,
            'movement_id': movementId,
            'warehouse_id': warehouseId,
          });

          if (cut.hasRemnant) {
            final rid = await RemnantStockHelper.upsertRemnant(
              txn: txn,
              parent: product,
              remnantLengthM: cut.remnantLengthM!,
              remnantWidthM: cut.remnantWidthM!,
              quantity: deduct,
              now: now,
              warehouseId: warehouseId,
              cutLengthM: line.lengthM,
              cutWidthM: line.widthM,
            );
            if (rid != null) remnantIds.add(rid);
          }

          syncMovements.add(SyncPayloadBuilders.movement(
            id: movementId,
            productId: line.productId,
            movementType: 'sale',
            quantity: -deduct,
            notes: saleNotes,
            referenceType: partnerType,
            referenceId: partnerId,
            partnerName: partnerName,
            lengthM: line.lengthM,
            widthM: line.widthM,
            areaM2: pieceArea,
            parentLengthM: parentLength,
            parentWidthM: parentWidth,
            brokenQty: 0,
            unitPrice: line.unitPrice,
            paidAmount: line.paidAmount < 0 ? 0 : line.paidAmount,
            currencyId: line.currencyId ?? currencyId,
            warehouseId: warehouseId,
            orderId: orderId,
            createdAt: order.createdAt.toIso8601String(),
            updatedAt: now.toIso8601String(),
          ));
        }
      });

      // Removed movements -> new movements -> updated products -> invoice.
      await SyncOutbox.group(() async {
        for (final mid in oldMovementIds) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '$mid',
            operation: SyncOperation.delete,
            data: {'id': mid},
          );
        }
        for (final m in syncMovements) {
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '${m['id']}',
            operation: SyncOperation.create,
            data: m,
          );
        }
        for (final rid in remnantIds) {
          await RemnantStockHelper.enqueueRemnantProductSync(_db, rid);
        }
        final touchedProducts = <int>{
          for (final item in order.items) item.productId,
          for (final m in syncMovements)
            if (m['productId'] is int) m['productId'] as int,
        };
        for (final pid in touchedProducts) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await _syncCustomerBalancesAfterOrder(
          partnerType: partnerType,
          partnerId: partnerId,
        );
        if (order.partnerType != partnerType ||
            order.partnerId != partnerId) {
          await _syncCustomerBalancesAfterOrder(
            partnerType: order.partnerType,
            partnerId: order.partnerId,
          );
        }
        await SyncPayloadBuilders.enqueueInvoiceSnapshot(
          _db,
          isOrder: true,
          id: orderId,
        );
      });

      return getById(orderId);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to replace order: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> deleteOrder(int orderId) async {
    try {
      final existing = await getById(orderId);
      if (existing is FailureResult) {
        return FailureResult((existing as FailureResult).failure);
      }
      final order = (existing as Success<OrderModel>).value;
      final now = DateTime.now();

      await _db.transaction((txn) async {
        for (final item in order.items) {
          final mid = item.movementId;
          if (mid == null) continue;
          final movRows = await txn.query(
            'stock_movements',
            where: 'id = ?',
            whereArgs: [mid],
          );
          if (movRows.isEmpty) continue;
          final mov = movRows.first;
          final productId = mov['product_id'] as int;
          final qty = (mov['quantity'] as num).toDouble();
          // Sale qty is negative; restore stock by subtracting delta
          // (i.e. adding abs qty).
          final productRows = await txn.query(
            'products',
            columns: ['current_stock', 'name'],
            where: 'id = ?',
            whereArgs: [productId],
          );
          if (productRows.isEmpty) continue;
          final current =
              (productRows.first['current_stock'] as num).toDouble();
          final restored = current - qty; // qty negative → increase
          await txn.update(
            'products',
            {
              'current_stock': restored,
              'updated_at': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [productId],
          );
          await txn.delete(
            'stock_movements',
            where: 'id = ?',
            whereArgs: [mid],
          );
        }
        await txn.delete(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        await txn.delete('orders', where: 'id = ?', whereArgs: [orderId]);
      });

      // Removed movements -> restored products -> the invoice delete.
      await SyncOutbox.group(() async {
        for (final item in order.items) {
          if (item.movementId == null) continue;
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '${item.movementId}',
            operation: SyncOperation.delete,
            data: {'id': item.movementId},
          );
        }
        for (final pid in {for (final item in order.items) item.productId}) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await _syncCustomerBalancesAfterOrder(
          partnerType: order.partnerType,
          partnerId: order.partnerId,
        );
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.orders,
          entityId: '$orderId',
          operation: SyncOperation.delete,
          data: {'id': orderId},
        );
      });

      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete order: $e', cause: st),
      );
    }
  }
}
