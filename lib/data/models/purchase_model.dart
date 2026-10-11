import 'package:equatable/equatable.dart';

class PurchaseItemModel extends Equatable {
  const PurchaseItemModel({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.lengthM,
    this.widthM,
    this.paidAmount = 0,
    this.currencyId,
    this.sellingPrice,
    this.sellingCurrencyId,
    this.movementId,
    this.warehouseId,
    this.productImagePath,
  });

  final int id;
  final int purchaseId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final double? lengthM;
  final double? widthM;
  final double paidAmount;
  final int? currencyId;
  final double? sellingPrice;
  final int? sellingCurrencyId;
  final int? movementId;
  final int? warehouseId;
  final String? productImagePath;

  factory PurchaseItemModel.fromMap(Map<String, Object?> map) {
    return PurchaseItemModel(
      id: map['id'] as int,
      purchaseId: map['purchase_id'] as int,
      productId: map['product_id'] as int,
      productName: (map['product_name'] as String?) ?? '',
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
      lengthM: (map['length_m'] as num?)?.toDouble(),
      widthM: (map['width_m'] as num?)?.toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      currencyId: map['currency_id'] as int?,
      sellingPrice: (map['selling_price'] as num?)?.toDouble(),
      sellingCurrencyId: map['selling_currency_id'] as int?,
      movementId: map['movement_id'] as int?,
      warehouseId: map['warehouse_id'] as int?,
      productImagePath: map['product_image_path'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, purchaseId, productId, quantity];
}

class PurchaseModel extends Equatable {
  const PurchaseModel({
    required this.id,
    required this.invoiceNumber,
    this.partnerType,
    this.partnerId,
    this.partnerName,
    this.currencyId,
    this.currencyCode,
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.amountPaid = 0,
    this.paymentStatus = 'paid',
    this.status = 'completed',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.lineCount = 0,
  });

  final int id;
  final String invoiceNumber;
  final String? partnerType;
  final int? partnerId;
  final String? partnerName;
  final int? currencyId;
  final String? currencyCode;
  final double subtotal;
  final double discount;
  final double total;
  final double amountPaid;
  final String paymentStatus;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PurchaseItemModel> items;

  /// Line-row count from SQL when [items] is not loaded (list views).
  final int lineCount;

  int get displayLineCount =>
      items.isNotEmpty ? items.length : lineCount;

  int get itemCount => items.isEmpty
      ? 0
      : items.fold<int>(0, (n, i) => n + i.quantity.round());

  factory PurchaseModel.fromMap(
    Map<String, Object?> map, {
    List<PurchaseItemModel> items = const [],
  }) {
    return PurchaseModel(
      id: map['id'] as int,
      invoiceNumber: (map['invoice_number'] as String?) ?? '',
      partnerType: map['partner_type'] as String?,
      partnerId: map['partner_id'] as int?,
      partnerName: map['partner_name'] as String?,
      currencyId: map['currency_id'] as int?,
      currencyCode: map['currency_code'] as String?,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0,
      paymentStatus: (map['payment_status'] as String?) ?? 'paid',
      status: (map['status'] as String?) ?? 'completed',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      items: items,
      lineCount: (map['line_count'] as num?)?.toInt() ?? items.length,
    );
  }

  @override
  List<Object?> get props => [id, invoiceNumber, total, status];
}

/// Line input when creating a purchase invoice from the cart/dialog.
class PurchaseLineInput {
  const PurchaseLineInput({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.paidAmount,
    this.sellingPrice,
    this.sellingCurrencyId,
    this.lengthM,
    this.widthM,
    this.currencyId,
    this.warehouseId,
  });

  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final double paidAmount;
  /// When set (> 0), updates the product catalog selling price on save.
  final double? sellingPrice;
  /// Catalog selling-price currency written back to the product.
  final int? sellingCurrencyId;
  final double? lengthM;
  final double? widthM;
  /// Purchase / cost price currency for this line.
  final int? currencyId;
  final int? warehouseId;
}
