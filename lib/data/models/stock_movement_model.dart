import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';

import '../../core/utils/glass_cut_helper.dart';

enum StockMovementType {
  initial,
  purchase,
  sale,
  adjustment,
  transfer,
  damage,
  returnIn,
  returnOut,
  waste,
  correction,
}

extension StockMovementTypeX on StockMovementType {
  String get dbValue => switch (this) {
        StockMovementType.initial => 'initial',
        StockMovementType.purchase => 'purchase',
        StockMovementType.sale => 'sale',
        StockMovementType.adjustment => 'adjustment',
        StockMovementType.transfer => 'transfer',
        StockMovementType.damage => 'damage',
        StockMovementType.returnIn => 'return_in',
        StockMovementType.returnOut => 'return_out',
        StockMovementType.waste => 'waste',
        StockMovementType.correction => 'correction',
      };

  /// Localized label for UI (follows current app language).
  String get label => switch (this) {
        StockMovementType.initial => 'movementTypes.initial'.tr(),
        StockMovementType.purchase => 'movementTypes.purchase'.tr(),
        StockMovementType.sale => 'movementTypes.sale'.tr(),
        StockMovementType.adjustment => 'movementTypes.adjustment'.tr(),
        StockMovementType.transfer => 'movementTypes.transfer'.tr(),
        StockMovementType.damage => 'movementTypes.damage'.tr(),
        StockMovementType.returnIn => 'movementTypes.returnIn'.tr(),
        StockMovementType.returnOut => 'movementTypes.returnOut'.tr(),
        StockMovementType.waste => 'movementTypes.waste'.tr(),
        StockMovementType.correction => 'movementTypes.correction'.tr(),
      };

  static StockMovementType fromDb(String value) {
    return StockMovementType.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => StockMovementType.adjustment,
    );
  }
}

class StockMovementModel extends Equatable {
  const StockMovementModel({
    required this.id,
    required this.productId,
    this.productName,
    this.productImagePath,
    this.productThickness,
    this.productUnitWeight,
    this.productWeightUnit,
    required this.movementType,
    required this.quantity,
    required this.balanceAfter,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.partnerName,
    this.lengthM,
    this.widthM,
    this.pieceAreaM2,
    this.parentLengthM,
    this.parentWidthM,
    this.brokenQty = 0,
    this.unitPrice,
    this.paidAmount = 0,
    this.currencyId,
    this.currencyCode,
    this.currencySymbol,
    this.createdBy,
    this.employeeId,
    this.employeeName,
    this.warehouseId,
    this.warehouseName,
    required this.createdAt,
  });

  final int id;
  final int productId;
  final String? productName;
  final String? productImagePath;
  /// Product glass thickness in mm (joined from products).
  final double? productThickness;
  final double? productUnitWeight;
  final String? productWeightUnit;
  final StockMovementType movementType;
  final double quantity;
  final double balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final String? notes;
  final String? partnerName;
  final double? lengthM;
  final double? widthM;
  /// Persisted cut-piece area in m² (one unit).
  final double? pieceAreaM2;
  final double? parentLengthM;
  final double? parentWidthM;
  final double brokenQty;
  /// Unit price at the time of this inbound (cost) or outbound (sale).
  final double? unitPrice;
  /// Amount paid against [lineTotal] in the movement currency.
  final double paidAmount;
  final int? currencyId;
  final String? currencyCode;
  final String? currencySymbol;
  final String? createdBy;
  final int? employeeId;
  final String? employeeName;
  final int? warehouseId;
  final String? warehouseName;
  final DateTime createdAt;

  /// Area in m² = piece area × |quantity|, or length × width × |quantity|.
  double get areaM2 {
    if (pieceAreaM2 != null && pieceAreaM2! > 0) {
      return pieceAreaM2! * quantity.abs();
    }
    final l = lengthM;
    final w = widthM;
    if (l == null || w == null || l <= 0 || w <= 0) return 0;
    final length = l >= 50 ? l / 1000 : l;
    final width = w >= 50 ? w / 1000 : w;
    return length * width * quantity.abs();
  }

  /// Line weight for this movement.
  ///
  /// Cut sales from a parent sheet scale [productUnitWeight] by piece area.
  /// Remnant product rows already store proportional [productUnitWeight], so
  /// those movements use it as-is (`reference_type == remnant`).
  double get weightTotal {
    final u = productUnitWeight;
    if (u == null || u <= 0) return 0;
    return _pieceUnitWeight(u) * quantity.abs();
  }

  String get weightLabel {
    final u = productUnitWeight;
    if (u == null || u <= 0) return '—';
    final unit =
        (productWeightUnit == null || productWeightUnit!.trim().isEmpty)
            ? 'kg'
            : productWeightUnit!.trim();
    final total = weightTotal;
    final text = total == total.roundToDouble()
        ? '${total.round()}'
        : total.toStringAsFixed(2);
    return '$text $unit';
  }

  double _pieceUnitWeight(double productWeight) {
    if (referenceType == 'remnant') return productWeight;
    return GlassCutHelper.proportionalWeight(
          parentWeight: productWeight,
          parentLength: parentLengthM,
          parentWidth: parentWidthM,
          pieceLength: lengthM,
          pieceWidth: widthM,
        ) ??
        productWeight;
  }

  double get lineTotal {
    final p = unitPrice;
    if (p == null) return 0;
    return p * quantity.abs();
  }

  /// Remaining balance after payment (never negative).
  double get outstanding {
    final o = lineTotal - paidAmount;
    return o < 0 ? 0 : o;
  }

  factory StockMovementModel.fromMap(Map<String, Object?> map) {
    return StockMovementModel(
      id: map['id'] as int,
      productId: map['product_id'] as int,
      productName: map['product_name'] as String?,
      productImagePath: map['product_image_path'] as String?,
      productThickness: (map['product_thickness'] as num?)?.toDouble(),
      productUnitWeight: (map['product_unit_weight'] as num?)?.toDouble(),
      productWeightUnit: map['product_weight_unit'] as String?,
      movementType: StockMovementTypeX.fromDb(map['movement_type'] as String),
      quantity: (map['quantity'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as int?,
      notes: map['notes'] as String?,
      partnerName: map['partner_name'] as String?,
      lengthM: (map['length_m'] as num?)?.toDouble(),
      widthM: (map['width_m'] as num?)?.toDouble(),
      pieceAreaM2: (map['area_m2'] as num?)?.toDouble(),
      parentLengthM: (map['parent_length_m'] as num?)?.toDouble(),
      parentWidthM: (map['parent_width_m'] as num?)?.toDouble(),
      brokenQty: (map['broken_qty'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      currencyId: map['currency_id'] as int?,
      currencyCode: map['currency_code'] as String?,
      currencySymbol: map['currency_symbol'] as String?,
      createdBy: map['created_by'] as String?,
      employeeId: map['employee_id'] as int?,
      employeeName: map['employee_name'] as String?,
      warehouseId: map['warehouse_id'] as int?,
      warehouseName: map['warehouse_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'product_id': productId,
        'movement_type': movementType.dbValue,
        'quantity': quantity,
        'balance_after': balanceAfter,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'notes': notes,
        'partner_name': partnerName,
        'length_m': lengthM,
        'width_m': widthM,
        'area_m2': pieceAreaM2,
        'parent_length_m': parentLengthM,
        'parent_width_m': parentWidthM,
        'broken_qty': brokenQty,
        'unit_price': unitPrice,
        'paid_amount': paidAmount,
        'currency_id': currencyId,
        'warehouse_id': warehouseId,
        'created_by': createdBy,
        'employee_id': employeeId,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, productId, movementType, quantity, unitPrice, paidAmount, currencyId];
}
