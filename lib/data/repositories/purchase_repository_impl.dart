import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/app_database.dart';
import '../../core/database/invoice_numbers.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/result.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_outbox.dart';
import '../../core/sync/sync_payload_builders.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../models/purchase_model.dart';
import '../models/report_models.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  PurchaseRepositoryImpl();

  Database get _db => AppDatabase.instance;

  @override
  Future<Result<PaginatedResult<PurchaseModel>>> list({
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
        'SELECT COUNT(*) AS c FROM purchases WHERE $whereSql',
        args,
      );
      final total = (countRows.first['c'] as num?)?.toInt() ?? 0;
      final safePageSize = pageSize < 1 ? 50 : pageSize;
      final safePage = page < 1 ? 1 : page;
      final offset = (safePage - 1) * safePageSize;

      final rows = await _db.rawQuery(
        '''
        SELECT p.*,
          (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = p.id)
            AS line_count
        FROM purchases p
        WHERE $whereSql
        ORDER BY p.created_at DESC
        LIMIT ? OFFSET ?
        ''',
        [...args, safePageSize, offset],
      );

      final purchases = <PurchaseModel>[];
      for (final row in rows) {
        final items = includeItems
            ? await _loadItems(row['id'] as int)
            : const <PurchaseItemModel>[];
        purchases.add(PurchaseModel.fromMap(row, items: items));
      }
      return Success(
        PaginatedResult(
          items: purchases,
          total: total,
          page: safePage,
          pageSize: safePageSize,
        ),
      );
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to list purchases: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<PurchaseModel>> getById(int id) async {
    try {
      final rows =
          await _db.query('purchases', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        return const FailureResult(NotFoundFailure('Purchase not found.'));
      }
      final items = await _loadItems(id);
      return Success(PurchaseModel.fromMap(rows.first, items: items));
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to load purchase: $e', cause: st),
      );
    }
  }

  Future<List<PurchaseItemModel>> _loadItems(int purchaseId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT pi.*, p.image_path AS product_image_path
      FROM purchase_items pi
      LEFT JOIN products p ON p.id = pi.product_id
      WHERE pi.purchase_id = ?
      ORDER BY pi.id ASC
      ''',
      [purchaseId],
    );
    return rows.map(PurchaseItemModel.fromMap).toList();
  }

  Future<String> _nextInvoiceNumber(DatabaseExecutor db) {
    return nextSequentialInvoiceNumber(db, table: 'purchases');
  }

  @override
  Future<Result<PurchaseModel>> createPurchase({
    required List<PurchaseLineInput> lines,
    required String invoiceNumber,
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
      final updatedAt = DateTime.now();
      final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
      final disc = discount < 0 ? 0.0 : discount;
      final total = (subtotal - disc) < 0 ? 0.0 : (subtotal - disc);
      final paid = amountPaid < 0 ? 0.0 : amountPaid;
      final paymentStatus = paid + 0.0001 >= total
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');

      late String inv;
      final syncMovements = <Map<String, dynamic>>[];
      final purchaseId = await _db.transaction((txn) async {
        inv = await _nextInvoiceNumber(txn);

        final pid = await txn.insert('purchases', {
          'invoice_number': inv,
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
          'updated_at': updatedAt.toIso8601String(),
        });

        await _insertLines(
          txn: txn,
          purchaseId: pid,
          invoiceNumber: inv,
          lines: lines,
          partnerType: partnerType,
          partnerId: partnerId,
          partnerName: partnerName,
          currencyId: currencyId,
          createdAt: now,
          syncMovements: syncMovements,
        );
        return pid;
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
        final touchedProducts = <int>{
          for (final m in syncMovements)
            if (m['productId'] is int) m['productId'] as int,
        };
        for (final pid in touchedProducts) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await SyncPayloadBuilders.enqueueInvoiceSnapshot(
          _db,
          isOrder: false,
          id: purchaseId,
          operation: SyncOperation.create,
        );
      });

      return getById(purchaseId);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to create purchase: $e', cause: st),
      );
    }
  }

  Future<void> _insertLines({
    required Transaction txn,
    required int purchaseId,
    required String invoiceNumber,
    required List<PurchaseLineInput> lines,
    String? partnerType,
    int? partnerId,
    String? partnerName,
    int? currencyId,
    required DateTime createdAt,
    required List<Map<String, dynamic>> syncMovements,
  }) async {
    for (final line in lines) {
      final qty = line.quantity.abs();
      if (qty <= 0) {
        throw const ValidationFailure('Quantity must be positive.');
      }
      final productRows = await txn.query(
        'products',
        columns: ['current_stock', 'name', 'warehouse_id'],
        where: 'id = ?',
        whereArgs: [line.productId],
      );
      if (productRows.isEmpty) {
        throw NotFoundFailure('Product not found: ${line.productId}');
      }
      final current = (productRows.first['current_stock'] as num).toDouble();
      final next = current + qty;
      final warehouseId =
          line.warehouseId ?? productRows.first['warehouse_id'] as int?;
      final productUpdate = <String, Object?>{
        'current_stock': next,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (line.unitPrice > 0) {
        productUpdate['cost_price'] = line.unitPrice;
      }
      final costCurrencyId = line.currencyId ?? currencyId;
      if (costCurrencyId != null) {
        productUpdate['cost_currency_id'] = costCurrencyId;
      }
      if (line.sellingPrice != null && line.sellingPrice! > 0) {
        productUpdate['selling_price'] = line.sellingPrice;
      }
      if (line.sellingCurrencyId != null) {
        productUpdate['currency_id'] = line.sellingCurrencyId;
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

      final paid = line.paidAmount < 0 ? 0.0 : line.paidAmount;
      final lineArea = (line.lengthM != null &&
              line.widthM != null &&
              line.lengthM! > 0 &&
              line.widthM! > 0)
          ? line.lengthM! * line.widthM!
          : null;
      final movementId = await txn.insert('stock_movements', {
        'product_id': line.productId,
        'movement_type': 'purchase',
        'quantity': qty,
        'balance_after': next,
        'reference_type': partnerType,
        'reference_id': partnerId,
        'notes': 'Purchase $invoiceNumber',
        'partner_name': partnerName,
        'length_m': line.lengthM,
        'width_m': line.widthM,
        'area_m2': lineArea,
        'broken_qty': 0,
        'unit_price': line.unitPrice,
        'paid_amount': paid,
        'currency_id': costCurrencyId,
        'warehouse_id': warehouseId,
        'order_id': null,
        'purchase_id': purchaseId,
        'created_by': 'system',
        'created_at': createdAt.toIso8601String(),
      });

      await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': line.productId,
        'product_name': line.productName,
        'quantity': qty,
        'unit_price': line.unitPrice,
        'line_total': line.lineTotal,
        'length_m': line.lengthM,
        'width_m': line.widthM,
        'paid_amount': paid,
        'currency_id': costCurrencyId,
        'selling_price': line.sellingPrice,
        'selling_currency_id': line.sellingCurrencyId,
        'movement_id': movementId,
        'warehouse_id': warehouseId,
      });

      syncMovements.add(SyncPayloadBuilders.movement(
        id: movementId,
        productId: line.productId,
        movementType: 'purchase',
        quantity: qty,
        notes: 'Purchase $invoiceNumber',
        referenceType: partnerType,
        referenceId: partnerId,
        partnerName: partnerName,
        lengthM: line.lengthM,
        widthM: line.widthM,
        areaM2: lineArea,
        brokenQty: 0,
        unitPrice: line.unitPrice,
        paidAmount: paid,
        currencyId: costCurrencyId,
        warehouseId: warehouseId,
        purchaseId: purchaseId,
        balanceAfter: next,
        createdBy: 'system',
        createdAt: createdAt.toIso8601String(),
        updatedAt: createdAt.toIso8601String(),
      ));
    }
  }

  @override
  Future<Result<PurchaseModel>> replacePurchase({
    required int purchaseId,
    required List<PurchaseLineInput> lines,
    required String invoiceNumber,
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
    final inv = invoiceNumber.trim();
    if (inv.isEmpty) {
      return const FailureResult(ValidationFailure('Invoice number is required.'));
    }
    try {
      final existing = await getById(purchaseId);
      if (existing is FailureResult) return existing;
      final purchase = (existing as Success<PurchaseModel>).value;
      final now = DateTime.now();
      final txDate = createdAt ?? purchase.createdAt;
      final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
      final disc = discount < 0 ? 0.0 : discount;
      final total = (subtotal - disc) < 0 ? 0.0 : (subtotal - disc);
      final paid = amountPaid < 0 ? 0.0 : amountPaid;
      final paymentStatus = paid + 0.0001 >= total
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');
      final oldMovementIds = [
        for (final item in purchase.items)
          if (item.movementId != null) item.movementId!,
      ];
      final syncMovements = <Map<String, dynamic>>[];

      await _db.transaction((txn) async {
        final dup = await txn.query(
          'purchases',
          columns: ['id'],
          where: 'invoice_number = ? AND id != ?',
          whereArgs: [inv, purchaseId],
        );
        if (dup.isNotEmpty) {
          throw const ValidationFailure('Invoice number already exists.');
        }

        // Reverse stock from previous purchase lines.
        for (final item in purchase.items) {
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
            final restored = current - qty; // purchase qty positive → decrease
            await txn.update(
              'products',
              {
                'current_stock': restored < 0 ? 0 : restored,
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
          'purchase_items',
          where: 'purchase_id = ?',
          whereArgs: [purchaseId],
        );

        await txn.update(
          'purchases',
          {
            'invoice_number': inv,
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
            'created_at': txDate.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [purchaseId],
        );

        await _insertLines(
          txn: txn,
          purchaseId: purchaseId,
          invoiceNumber: inv,
          lines: lines,
          partnerType: partnerType,
          partnerId: partnerId,
          partnerName: partnerName,
          currencyId: currencyId,
          createdAt: txDate,
          syncMovements: syncMovements,
        );
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
        final touchedProducts = <int>{
          for (final item in purchase.items) item.productId,
          for (final m in syncMovements)
            if (m['productId'] is int) m['productId'] as int,
        };
        for (final pid in touchedProducts) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await SyncPayloadBuilders.enqueueInvoiceSnapshot(
          _db,
          isOrder: false,
          id: purchaseId,
        );
      });

      return getById(purchaseId);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to replace purchase: $e', cause: st),
      );
    }
  }

  @override
  Future<Result<void>> deletePurchase(int purchaseId) async {
    try {
      final existing = await getById(purchaseId);
      if (existing is FailureResult) {
        return FailureResult((existing as FailureResult).failure);
      }
      final purchase = (existing as Success<PurchaseModel>).value;
      final now = DateTime.now();

      await _db.transaction((txn) async {
        for (final item in purchase.items) {
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
            final restored = current - qty;
            await txn.update(
              'products',
              {
                'current_stock': restored < 0 ? 0 : restored,
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
          'purchase_items',
          where: 'purchase_id = ?',
          whereArgs: [purchaseId],
        );
        await txn.delete(
          'purchases',
          where: 'id = ?',
          whereArgs: [purchaseId],
        );
      });

      // Removed movements -> restored products -> the invoice delete.
      await SyncOutbox.group(() async {
        for (final item in purchase.items) {
          if (item.movementId == null) continue;
          await SyncOutbox.enqueue(
            entityType: SyncEntityTypes.transactions,
            entityId: '${item.movementId}',
            operation: SyncOperation.delete,
            data: {'id': item.movementId},
          );
        }
        for (final pid in {
          for (final item in purchase.items) item.productId,
        }) {
          await SyncPayloadBuilders.enqueueProductSnapshot(_db, pid);
        }
        await SyncOutbox.enqueue(
          entityType: SyncEntityTypes.purchases,
          entityId: '$purchaseId',
          operation: SyncOperation.delete,
          data: {'id': purchaseId},
        );
      });

      return const Success(null);
    } on AppFailure catch (e) {
      return FailureResult(e);
    } catch (e, st) {
      return FailureResult(
        DatabaseFailure('Failed to delete purchase: $e', cause: st),
      );
    }
  }
}
