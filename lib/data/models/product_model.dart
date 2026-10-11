import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/glass_cut_helper.dart';

enum ProductStockStatus { inStock, lowStock, outOfStock }

/// Retail alert kinds shown on product rows and the Alerts page.
enum ProductAlertKind { none, lowStock, outOfStock, expiringSoon, expired }

class ProductModel extends Equatable {
  const ProductModel({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    this.brand,
    this.description,
    this.expirationDate,
    this.expiryAlertValue = 1,
    this.expiryAlertUnit = 'month',
    this.categoryId,
    this.categoryName,
    this.categoryColor,
    this.thickness,
    this.standardWidth,
    this.standardHeight,
    this.unitOfMeasure,
    this.initialStock = 0,
    this.currentStock = 0,
    this.minimumStockAlert = 0,
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.currencyId,
    this.currencyCode,
    this.costCurrencyId,
    this.costCurrencyCode,
    this.supplierId,
    this.supplierName,
    this.imagePath,
    this.trackStockBySheet = false,
    this.isActive = true,
    this.isArchived = false,
    this.notes,
    this.warehouseId,
    this.warehouseName,
    this.unitWeight,
    this.weightUnit = 'kg',
    this.parentProductId,
    this.isRemnant = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String sku;
  final String? barcode;
  final String? brand;
  final String? description;
  final DateTime? expirationDate;
  /// Lead time before [expirationDate] when "expiring soon" alerts start.
  final int expiryAlertValue;
  /// `day` | `week` | `month` | `year`
  final String expiryAlertUnit;
  final int? categoryId;
  final String? categoryName;
  final String? categoryColor;
  final double? thickness;
  final double? standardWidth;
  final double? standardHeight;
  final String? unitOfMeasure;
  final double initialStock;
  final double currentStock;
  final double minimumStockAlert;
  final double costPrice;
  final double sellingPrice;
  /// Catalog selling-price currency.
  final int? currencyId;
  final String? currencyCode;
  /// Catalog cost / purchase-price currency.
  final int? costCurrencyId;
  final String? costCurrencyCode;
  final int? supplierId;
  final String? supplierName;
  final String? imagePath;
  final bool trackStockBySheet;
  final bool isActive;
  final bool isArchived;
  final String? notes;
  final int? warehouseId;
  final String? warehouseName;
  /// Weight of one unit (sheet/pcs) as entered on the product form.
  final double? unitWeight;
  /// Display unit for [unitWeight] (kg, g, t, …).
  final String weightUnit;
  /// Parent full-sheet / larger remnant this piece was cut from.
  final int? parentProductId;
  final bool isRemnant;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Locale-aware name (cut pieces use translated “برش / remnant” wording).
  String get displayName {
    if (!isRemnant && parentProductId == null) return name;
    final h = standardHeight;
    final w = standardWidth;
    if (h == null || w == null || h <= 0 || w <= 0) {
      return name
          .replaceAll(RegExp(r'\s+remnant\s+', caseSensitive: false), ' · ')
          .trim();
    }
    final length = h >= 50 ? h / 1000 : h;
    final width = w >= 50 ? w / 1000 : w;
    final parent = name
        .replaceAll(
          RegExp(
            r'\s*(remnant|برش|پاتې)\s+[\d.]+\s*[x×]\s*[\d.]+\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return GlassCutHelper.remnantName(
      parentName: parent.isEmpty ? name : parent,
      lengthM: length,
      widthM: width,
    );
  }

  /// Sheet area in m²: length × width (stored as meters; legacy mm ≥ 50).
  double get sheetAreaM2 {
    final w = standardWidth;
    final h = standardHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return 0;
    final length = h >= 50 ? h / 1000 : h;
    final width = w >= 50 ? w / 1000 : w;
    return length * width;
  }

  /// True when this product still uses sheet cut-to-size stock logic.
  bool get usesSheetCutLogic {
    if (!trackStockBySheet) return false;
    final h = standardHeight;
    final w = standardWidth;
    return h != null && w != null && h > 0 && w > 0;
  }

  /// Unit weight for a piece cut from this product (area-proportional).
  double? weightForPiece({double? length, double? width}) {
    return GlassCutHelper.proportionalWeight(
          parentWeight: unitWeight,
          parentLength: standardHeight,
          parentWidth: standardWidth,
          pieceLength: length,
          pieceWidth: width,
        ) ??
        unitWeight;
  }

  double get totalAreaM2 {
    if (sheetAreaM2 <= 0) return 0;
    return sheetAreaM2 * currentStock;
  }

  double get totalWeight {
    final w = unitWeight;
    if (w == null || w <= 0) return 0;
    return w * currentStock;
  }

  String get weightLabel {
    final w = unitWeight;
    if (w == null || w <= 0) return '—';
    final u = weightUnit.trim().isEmpty ? 'kg' : weightUnit.trim();
    final text = w == w.roundToDouble() ? '${w.round()}' : '$w';
    return '$text $u';
  }

  ProductStockStatus get stockStatus {
    if (currentStock <= 0) return ProductStockStatus.outOfStock;
    if (currentStock <= minimumStockAlert) return ProductStockStatus.lowStock;
    return ProductStockStatus.inStock;
  }

  String get stockStatusLabel => switch (stockStatus) {
        ProductStockStatus.inStock => 'In Stock',
        ProductStockStatus.lowStock => 'Low Stock',
        ProductStockStatus.outOfStock => 'Out of Stock',
      };

  int get expiryAlertDays {
    final v = expiryAlertValue < 1 ? 1 : expiryAlertValue;
    return switch (expiryAlertUnit.trim().toLowerCase()) {
      'day' => v,
      'week' => v * 7,
      'month' => v * 30,
      'year' => v * 365,
      _ => AppConstants.expiryAlertDays,
    };
  }

  /// Combined stock + expiry alert for UI badges.
  ProductAlertKind get alertKind {
    final exp = expirationDate;
    if (exp != null) {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final expDay = DateTime(exp.year, exp.month, exp.day);
      if (expDay.isBefore(day)) return ProductAlertKind.expired;
      final soon = day.add(Duration(days: expiryAlertDays));
      if (!expDay.isAfter(soon)) return ProductAlertKind.expiringSoon;
    }
    return switch (stockStatus) {
      ProductStockStatus.outOfStock => ProductAlertKind.outOfStock,
      ProductStockStatus.lowStock => ProductAlertKind.lowStock,
      ProductStockStatus.inStock => ProductAlertKind.none,
    };
  }

  bool get hasAlert => alertKind != ProductAlertKind.none;

  double get estimatedMargin {
    if (sellingPrice <= 0) return 0;
    return ((sellingPrice - costPrice) / sellingPrice) * 100;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory ProductModel.fromMap(Map<String, Object?> map) {
    return ProductModel(
      id: map['id'] as int,
      name: map['name'] as String,
      sku: map['sku'] as String,
      barcode: map['barcode'] as String?,
      brand: map['brand'] as String?,
      description: map['description'] as String?,
      expirationDate: _parseDate(map['expiration_date']),
      expiryAlertValue: (map['expiry_alert_value'] as num?)?.toInt() ?? 1,
      expiryAlertUnit:
          (map['expiry_alert_unit'] as String?)?.trim().isNotEmpty == true
              ? (map['expiry_alert_unit'] as String).trim().toLowerCase()
              : 'month',
      categoryId: map['category_id'] as int?,
      categoryName: map['category_name'] as String?,
      categoryColor: map['category_color'] as String?,
      thickness: (map['thickness'] as num?)?.toDouble(),
      standardWidth: (map['standard_width'] as num?)?.toDouble(),
      standardHeight: (map['standard_height'] as num?)?.toDouble(),
      unitOfMeasure: map['unit_of_measure'] as String?,
      initialStock: (map['initial_stock'] as num?)?.toDouble() ?? 0,
      currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0,
      minimumStockAlert:
          (map['minimum_stock_alert'] as num?)?.toDouble() ?? 0,
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      currencyId: map['currency_id'] as int?,
      currencyCode: map['currency_code'] as String?,
      costCurrencyId: map['cost_currency_id'] as int?,
      costCurrencyCode: map['cost_currency_code'] as String?,
      supplierId: map['supplier_id'] as int?,
      supplierName: map['supplier_name'] as String?,
      imagePath: map['image_path'] as String?,
      trackStockBySheet: (map['track_stock_by_sheet'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      notes: map['notes'] as String?,
      warehouseId: map['warehouse_id'] as int?,
      warehouseName: map['warehouse_name'] as String?,
      unitWeight: (map['unit_weight'] as num?)?.toDouble(),
      weightUnit: (map['weight_unit'] as String?)?.trim().isNotEmpty == true
          ? (map['weight_unit'] as String).trim()
          : 'kg',
      parentProductId: map['parent_product_id'] as int?,
      isRemnant: (map['is_remnant'] as int? ?? 0) == 1 ||
          map['parent_product_id'] != null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'brand': brand,
        'description': description,
        'expiration_date': expirationDate?.toIso8601String().split('T').first,
        'expiry_alert_value': expiryAlertValue < 1 ? 1 : expiryAlertValue,
        'expiry_alert_unit': expiryAlertUnit.trim().isEmpty
            ? 'month'
            : expiryAlertUnit.trim().toLowerCase(),
        'category_id': categoryId,
        'thickness': thickness,
        'standard_width': standardWidth,
        'standard_height': standardHeight,
        'unit_of_measure': unitOfMeasure,
        'initial_stock': initialStock,
        'current_stock': currentStock,
        'minimum_stock_alert': minimumStockAlert,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'currency_id': currencyId,
        'cost_currency_id': costCurrencyId,
        'supplier_id': supplierId,
        'image_path': imagePath,
        'track_stock_by_sheet': trackStockBySheet ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'notes': notes,
        'warehouse_id': warehouseId,
        'unit_weight': unitWeight,
        'weight_unit': weightUnit,
        'parent_product_id': parentProductId,
        'is_remnant': isRemnant || parentProductId != null ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  ProductModel copyWith({
    int? id,
    String? name,
    String? sku,
    String? barcode,
    bool clearBarcode = false,
    String? brand,
    bool clearBrand = false,
    String? description,
    bool clearDescription = false,
    DateTime? expirationDate,
    bool clearExpiration = false,
    int? expiryAlertValue,
    String? expiryAlertUnit,
    int? categoryId,
    String? categoryName,
    String? categoryColor,
    double? thickness,
    double? standardWidth,
    double? standardHeight,
    String? unitOfMeasure,
    double? initialStock,
    double? currentStock,
    double? minimumStockAlert,
    double? costPrice,
    double? sellingPrice,
    int? currencyId,
    String? currencyCode,
    int? costCurrencyId,
    String? costCurrencyCode,
    int? supplierId,
    bool clearSupplier = false,
    String? supplierName,
    String? imagePath,
    bool clearImage = false,
    bool? trackStockBySheet,
    bool? isActive,
    bool? isArchived,
    String? notes,
    int? warehouseId,
    String? warehouseName,
    bool clearWarehouse = false,
    double? unitWeight,
    bool clearUnitWeight = false,
    String? weightUnit,
    int? parentProductId,
    bool clearParent = false,
    bool? isRemnant,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      brand: clearBrand ? null : (brand ?? this.brand),
      description:
          clearDescription ? null : (description ?? this.description),
      expirationDate:
          clearExpiration ? null : (expirationDate ?? this.expirationDate),
      expiryAlertValue: expiryAlertValue ?? this.expiryAlertValue,
      expiryAlertUnit: expiryAlertUnit ?? this.expiryAlertUnit,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categoryColor: categoryColor ?? this.categoryColor,
      thickness: thickness ?? this.thickness,
      standardWidth: standardWidth ?? this.standardWidth,
      standardHeight: standardHeight ?? this.standardHeight,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      initialStock: initialStock ?? this.initialStock,
      currentStock: currentStock ?? this.currentStock,
      minimumStockAlert: minimumStockAlert ?? this.minimumStockAlert,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      currencyId: currencyId ?? this.currencyId,
      currencyCode: currencyCode ?? this.currencyCode,
      costCurrencyId: costCurrencyId ?? this.costCurrencyId,
      costCurrencyCode: costCurrencyCode ?? this.costCurrencyCode,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName:
          clearSupplier ? null : (supplierName ?? this.supplierName),
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      trackStockBySheet: trackStockBySheet ?? this.trackStockBySheet,
      isActive: isActive ?? this.isActive,
      isArchived: isArchived ?? this.isArchived,
      notes: notes ?? this.notes,
      warehouseId: clearWarehouse ? null : (warehouseId ?? this.warehouseId),
      warehouseName:
          clearWarehouse ? null : (warehouseName ?? this.warehouseName),
      unitWeight: clearUnitWeight ? null : (unitWeight ?? this.unitWeight),
      weightUnit: weightUnit ?? this.weightUnit,
      parentProductId:
          clearParent ? null : (parentProductId ?? this.parentProductId),
      isRemnant: isRemnant ?? this.isRemnant,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, sku, name, currentStock, updatedAt];
}

class ProductStats extends Equatable {
  const ProductStats({
    required this.total,
    required this.active,
    required this.lowStock,
    required this.outOfStock,
  });

  final int total;
  final int active;
  final int lowStock;
  final int outOfStock;

  @override
  List<Object?> get props => [total, active, lowStock, outOfStock];
}

class ProductQuery {
  const ProductQuery({
    this.search,
    this.categoryId,
    this.categoryName,
    this.brand,
    this.supplierId,
    this.status,
    this.includeArchived = false,
    this.page = 1,
    this.pageSize = 20,
    this.sortBy = 'updated_at',
    this.ascending = false,
  });

  final String? search;
  final int? categoryId;
  final String? categoryName;
  final String? brand;
  final int? supplierId;
  final ProductStockStatus? status;
  final bool includeArchived;
  final int page;
  final int pageSize;
  final String sortBy;
  final bool ascending;

  int get offset => (page - 1) * pageSize;
}
