import 'package:equatable/equatable.dart';

class OrderItemModel extends Equatable {
  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.lengthM,
    this.widthM,
    this.areaM2,
    this.paidAmount = 0,
    this.currencyId,
    this.movementId,
    this.warehouseId,
    this.productImagePath,
  });

  final int id;
  final int orderId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final double? lengthM;
  final double? widthM;
  final double? areaM2;
  final double paidAmount;
  final int? currencyId;
  final int? movementId;
  final int? warehouseId;
  final String? productImagePath;

  factory OrderItemModel.fromMap(Map<String, Object?> map) {
    return OrderItemModel(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      productId: map['product_id'] as int,
      productName: (map['product_name'] as String?) ?? '',
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
      lengthM: (map['length_m'] as num?)?.toDouble(),
      widthM: (map['width_m'] as num?)?.toDouble(),
      areaM2: (map['area_m2'] as num?)?.toDouble() ??
          (() {
            final l = (map['length_m'] as num?)?.toDouble();
            final w = (map['width_m'] as num?)?.toDouble();
            if (l == null || w == null || l <= 0 || w <= 0) return null;
            final lm = l >= 50 ? l / 1000 : l;
            final wm = w >= 50 ? w / 1000 : w;
            return lm * wm;
          })(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      currencyId: map['currency_id'] as int?,
      movementId: map['movement_id'] as int?,
      warehouseId: map['warehouse_id'] as int?,
      productImagePath: map['product_image_path'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, orderId, productId, quantity];
}

class OrderModel extends Equatable {
  const OrderModel({
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
  final List<OrderItemModel> items;

  /// Line-row count from SQL when [items] is not loaded (list views).
  final int lineCount;

  /// Prefer loaded items; otherwise the SQL [lineCount].
  int get displayLineCount =>
      items.isNotEmpty ? items.length : lineCount;

  int get itemCount => items.isEmpty
      ? 0
      : items.fold<int>(0, (n, i) => n + i.quantity.round());

  factory OrderModel.fromMap(
    Map<String, Object?> map, {
    List<OrderItemModel> items = const [],
  }) {
    return OrderModel(
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

  OrderModel copyWith({
    String? partnerType,
    int? partnerId,
    String? partnerName,
    double? discount,
    double? total,
    double? amountPaid,
    String? paymentStatus,
    String? notes,
    List<OrderItemModel>? items,
    int? lineCount,
  }) {
    return OrderModel(
      id: id,
      invoiceNumber: invoiceNumber,
      partnerType: partnerType ?? this.partnerType,
      partnerId: partnerId ?? this.partnerId,
      partnerName: partnerName ?? this.partnerName,
      currencyId: currencyId,
      currencyCode: currencyCode,
      subtotal: subtotal,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      items: items ?? this.items,
      lineCount: lineCount ?? this.lineCount,
    );
  }

  @override
  List<Object?> get props => [id, invoiceNumber, total, status];
}

/// Line input when creating an outbound invoice from the cart.
class OutboundOrderLineInput {
  const OutboundOrderLineInput({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.paidAmount,
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
  final double? lengthM;
  final double? widthM;
  final int? currencyId;
  final int? warehouseId;
}
