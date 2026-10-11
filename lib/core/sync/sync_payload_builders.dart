import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync_models.dart';
import 'sync_outbox.dart';

/// Canonical sync JSON for products / stock movements (transactions).
///
/// Writes both snake_case (SQLite column names) and camelCase aliases so
/// server consumers and [FirebaseRestoreService] round-trip every field.
abstract final class SyncPayloadBuilders {
  /// Full customer node from a `customers` table row (snake + camelCase).
  static Map<String, dynamic> customerFromRow(Map<String, Object?> r) {
    final id = r['id'];
    return {
      ...Map<String, dynamic>.from(r),
      'id': id,
      'name': r['name'],
      'phone': r['phone'],
      'email': r['email'],
      'address': r['address'],
      'notes': r['notes'],
      'outstandingBalance': r['outstanding_balance'] ?? r['outstandingBalance'],
      'outstanding_balance': r['outstanding_balance'] ?? r['outstandingBalance'],
      'totalPurchases': r['total_purchases'] ?? r['totalPurchases'],
      'total_purchases': r['total_purchases'] ?? r['totalPurchases'],
      'lastPurchaseAt': r['last_purchase_at'] ?? r['lastPurchaseAt'],
      'last_purchase_at': r['last_purchase_at'] ?? r['lastPurchaseAt'],
      'isArchived': r['is_archived'] ?? r['isArchived'],
      'is_archived': r['is_archived'] ?? r['isArchived'],
      'createdAt': r['created_at'] ?? r['createdAt'],
      'created_at': r['created_at'] ?? r['createdAt'],
      'updatedAt': r['updated_at'] ?? r['updatedAt'],
      'updated_at': r['updated_at'] ?? r['updatedAt'],
    };
  }

  /// Full product node from a `products` table row.
  static Map<String, dynamic> productFromRow(Map<String, Object?> r) {
    final id = r['id'];
    return {
      ...Map<String, dynamic>.from(r),
      'id': id,
      'createdAt': r['created_at'] ?? r['createdAt'],
      'updatedAt': r['updated_at'] ?? r['updatedAt'],
      'categoryId': r['category_id'],
      'currencyId': r['currency_id'],
      'costCurrencyId': r['cost_currency_id'],
      'supplierId': r['supplier_id'],
      'warehouseId': r['warehouse_id'],
      'unitWeight': r['unit_weight'],
      'weightUnit': r['weight_unit'],
      'parentProductId': r['parent_product_id'],
      'isRemnant': r['is_remnant'],
      'unitOfMeasure': r['unit_of_measure'],
      'initialStock': r['initial_stock'],
      'currentStock': r['current_stock'],
      'minimumStockAlert': r['minimum_stock_alert'],
      'costPrice': r['cost_price'],
      'sellingPrice': r['selling_price'],
      'standardWidth': r['standard_width'],
      'standardHeight': r['standard_height'],
      'trackStockBySheet': r['track_stock_by_sheet'],
      'isActive': r['is_active'],
      'isArchived': r['is_archived'],
      'imagePath': r['image_path'],
      'barcode': r['barcode'],
      'brand': r['brand'],
      'description': r['description'],
      'expirationDate': r['expiration_date'],
      'expiration_date': r['expiration_date'],
      'expiryAlertValue': r['expiry_alert_value'],
      'expiry_alert_value': r['expiry_alert_value'],
      'expiryAlertUnit': r['expiry_alert_unit'],
      'expiry_alert_unit': r['expiry_alert_unit'],
    };
  }

  /// Stock movement / transaction node. Accepts snake or camel inputs.
  static Map<String, dynamic> movement({
    required Object? id,
    required Object? productId,
    required String movementType,
    required num quantity,
    Object? notes,
    Object? referenceType,
    Object? referenceId,
    Object? partnerName,
    Object? lengthM,
    Object? widthM,
    Object? areaM2,
    Object? parentLengthM,
    Object? parentWidthM,
    Object? brokenQty,
    Object? unitPrice,
    Object? paidAmount,
    Object? currencyId,
    Object? warehouseId,
    Object? employeeId,
    Object? orderId,
    Object? purchaseId,
    Object? balanceAfter,
    Object? createdBy,
    Object? createdAt,
    Object? updatedAt,
  }) {
    final area = areaM2 ?? _areaFromDims(lengthM, widthM);
    return {
      'id': id,
      'productId': productId,
      'product_id': productId,
      'movementType': movementType,
      'movement_type': movementType,
      'quantity': quantity,
      'notes': notes,
      'referenceType': referenceType,
      'reference_type': referenceType,
      'referenceId': referenceId,
      'reference_id': referenceId,
      'partnerName': partnerName,
      'partner_name': partnerName,
      'lengthM': lengthM,
      'length_m': lengthM,
      'widthM': widthM,
      'width_m': widthM,
      'areaM2': area,
      'area_m2': area,
      'parentLengthM': parentLengthM,
      'parent_length_m': parentLengthM,
      'parentWidthM': parentWidthM,
      'parent_width_m': parentWidthM,
      'brokenQty': brokenQty ?? 0,
      'broken_qty': brokenQty ?? 0,
      'unitPrice': unitPrice,
      'unit_price': unitPrice,
      'paidAmount': paidAmount ?? 0,
      'paid_amount': paidAmount ?? 0,
      'currencyId': currencyId,
      'currency_id': currencyId,
      'warehouseId': warehouseId,
      'warehouse_id': warehouseId,
      'employeeId': employeeId,
      'employee_id': employeeId,
      'orderId': orderId,
      'order_id': orderId,
      'purchaseId': purchaseId,
      'purchase_id': purchaseId,
      if (balanceAfter != null) ...{
        'balanceAfter': balanceAfter,
        'balance_after': balanceAfter,
      },
      if (createdBy != null) ...{
        'createdBy': createdBy,
        'created_by': createdBy,
      },
      'createdAt': createdAt,
      'created_at': createdAt,
      'updatedAt': updatedAt ?? createdAt,
      'updated_at': updatedAt ?? createdAt,
    };
  }

  /// Build movement payload from a `stock_movements` row.
  static Map<String, dynamic> movementFromRow(Map<String, Object?> r) {
    return movement(
      id: r['id'],
      productId: r['product_id'],
      movementType: '${r['movement_type'] ?? 'adjustment'}',
      quantity: (r['quantity'] as num?) ?? 0,
      notes: r['notes'],
      referenceType: r['reference_type'],
      referenceId: r['reference_id'],
      partnerName: r['partner_name'],
      lengthM: r['length_m'],
      widthM: r['width_m'],
      areaM2: r['area_m2'],
      parentLengthM: r['parent_length_m'],
      parentWidthM: r['parent_width_m'],
      brokenQty: r['broken_qty'],
      unitPrice: r['unit_price'],
      paidAmount: r['paid_amount'],
      currencyId: r['currency_id'],
      warehouseId: r['warehouse_id'],
      employeeId: r['employee_id'],
      orderId: r['order_id'],
      purchaseId: r['purchase_id'],
      balanceAfter: r['balance_after'],
      createdBy: r['created_by'],
      createdAt: r['created_at'],
      updatedAt: r['created_at'],
    );
  }

  /// Enrich an existing (partial) movement map with dual keys + cut fields.
  static Map<String, dynamic> normalizeMovement(Map<String, dynamic> raw) {
    return movement(
      id: raw['id'],
      productId: raw['productId'] ?? raw['product_id'],
      movementType: '${raw['movementType'] ?? raw['movement_type'] ?? 'adjustment'}',
      quantity: (raw['quantity'] as num?) ?? 0,
      notes: raw['notes'],
      referenceType: raw['referenceType'] ?? raw['reference_type'],
      referenceId: raw['referenceId'] ?? raw['reference_id'],
      partnerName: raw['partnerName'] ?? raw['partner_name'],
      lengthM: raw['lengthM'] ?? raw['length_m'],
      widthM: raw['widthM'] ?? raw['width_m'],
      areaM2: raw['areaM2'] ?? raw['area_m2'],
      parentLengthM: raw['parentLengthM'] ?? raw['parent_length_m'],
      parentWidthM: raw['parentWidthM'] ?? raw['parent_width_m'],
      brokenQty: raw['brokenQty'] ?? raw['broken_qty'],
      unitPrice: raw['unitPrice'] ?? raw['unit_price'],
      paidAmount: raw['paidAmount'] ?? raw['paid_amount'],
      currencyId: raw['currencyId'] ?? raw['currency_id'],
      warehouseId: raw['warehouseId'] ?? raw['warehouse_id'],
      employeeId: raw['employeeId'] ?? raw['employee_id'],
      orderId: raw['orderId'] ?? raw['order_id'],
      purchaseId: raw['purchaseId'] ?? raw['purchase_id'],
      balanceAfter: raw['balanceAfter'] ?? raw['balance_after'],
      createdBy: raw['createdBy'] ?? raw['created_by'],
      createdAt: raw['createdAt'] ?? raw['created_at'],
      updatedAt: raw['updatedAt'] ?? raw['updated_at'],
    );
  }

  /// Full order / purchase node from its table row + linked movement ids.
  static Map<String, dynamic> invoiceFromRow(
    Map<String, Object?> r,
    List<int> movementIds,
  ) {
    return {
      ...Map<String, dynamic>.from(r),
      'id': r['id'],
      'invoiceNumber': r['invoice_number'],
      'partnerType': r['partner_type'],
      'partnerId': r['partner_id'],
      'partnerName': r['partner_name'],
      'currencyId': r['currency_id'],
      'currencyCode': r['currency_code'],
      'amountPaid': r['amount_paid'],
      'paymentStatus': r['payment_status'],
      'createdAt': r['created_at'],
      'updatedAt': r['updated_at'],
      'movementIds': movementIds,
      'movement_ids': movementIds,
    };
  }

  /// Full company payment node + its allocations. `company_payments` has no
  /// updated_at column, so the job's change time is when it was queued.
  static Map<String, dynamic> companyPaymentFromRow(
    Map<String, Object?> r,
    List<Map<String, Object?>> allocations,
  ) {
    return {
      'id': r['id'],
      'partnerType': r['partner_type'],
      'partnerId': r['partner_id'],
      'partnerName': r['partner_name'],
      'amount': r['amount'],
      'currency': r['currency'],
      'paidAt': r['paid_at'],
      'paymentMethod': r['payment_method'],
      'settlementSide': r['settlement_side'],
      'notes': r['notes'],
      'isVoided': r['is_voided'] == 1,
      'createdAt': r['created_at'],
      'allocations': [
        for (final a in allocations)
          {
            'id': a['id'],
            'movementId': a['movement_id'],
            'purchaseId': a['purchase_id'],
            'orderId': a['order_id'],
            'amount': a['amount'],
          },
      ],
    };
  }

  /// Queue the latest full order (`isOrder`) or purchase row.
  static Future<void> enqueueInvoiceSnapshot(
    DatabaseExecutor db, {
    required bool isOrder,
    required int id,
    SyncOperation operation = SyncOperation.update,
  }) async {
    final table = isOrder ? 'orders' : 'purchases';
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final moves = await db.query(
      'stock_movements',
      columns: ['id'],
      where: '${isOrder ? 'order_id' : 'purchase_id'} = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    await SyncOutbox.enqueue(
      entityType: isOrder ? SyncEntityTypes.orders : SyncEntityTypes.purchases,
      entityId: '$id',
      operation: operation,
      data: invoiceFromRow(rows.first, [
        for (final m in moves)
          if (m['id'] is int) m['id'] as int,
      ]),
    );
  }

  /// Queue the latest full movement row, stamped as changed now
  /// (`stock_movements` has no updated_at column).
  static Future<void> enqueueMovementSnapshot(
    DatabaseExecutor db,
    int movementId, {
    SyncOperation operation = SyncOperation.update,
  }) async {
    final rows = await db.query(
      'stock_movements',
      where: 'id = ?',
      whereArgs: [movementId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await SyncOutbox.enqueue(
      entityType: SyncEntityTypes.transactions,
      entityId: '$movementId',
      operation: operation,
      data: {
        ...movementFromRow(rows.first),
        'updatedAt': now,
        'updated_at': now,
      },
    );
  }

  /// Push the latest full product row so server stock/dims stay intact.
  static Future<void> enqueueProductSnapshot(
    DatabaseExecutor db,
    int productId, {
    SyncOperation operation = SyncOperation.update,
    bool forceLocal = false,
  }) async {
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await SyncOutbox.enqueue(
      entityType: SyncEntityTypes.products,
      entityId: '$productId',
      operation: operation,
      data: {
        ...productFromRow(rows.first),
        if (forceLocal) 'forceLocal': true,
      },
    );
  }

  /// Push remnant product + all of its stock movements.
  static Future<void> enqueueRemnantBundle(
    DatabaseExecutor db,
    int remnantId,
  ) async {
    await enqueueProductSnapshot(
      db,
      remnantId,
      forceLocal: true,
    );
    final moves = await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [remnantId],
      orderBy: 'id ASC',
    );
    for (final m in moves) {
      final mid = m['id'];
      if (mid == null) continue;
      await SyncOutbox.enqueue(
        entityType: SyncEntityTypes.transactions,
        entityId: '$mid',
        operation: SyncOperation.update,
        data: {
          ...movementFromRow(m),
          'forceLocal': true,
        },
      );
    }
  }

  static double? _areaFromDims(Object? lengthM, Object? widthM) {
    final l = lengthM is num ? lengthM.toDouble() : null;
    final w = widthM is num ? widthM.toDouble() : null;
    if (l == null || w == null || l <= 0 || w <= 0) return null;
    return l * w;
  }
}
