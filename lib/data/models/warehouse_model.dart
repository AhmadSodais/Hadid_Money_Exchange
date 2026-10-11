import 'package:equatable/equatable.dart';

class WarehouseModel extends Equatable {
  const WarehouseModel({
    required this.id,
    required this.name,
    this.address,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.inboundQty = 0,
    this.outboundQty = 0,
    this.inboundArea = 0,
    this.outboundArea = 0,
    this.productCount = 0,
    this.stockQty = 0,
  });

  final int id;
  final String name;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Period inbound/outbound transaction counts (filled by stats queries).
  final double inboundQty;
  final double outboundQty;
  final double inboundArea;
  final double outboundArea;
  final int productCount;
  final double stockQty;

  double get netQty => inboundQty - outboundQty;

  factory WarehouseModel.fromMap(Map<String, Object?> map) {
    return WarehouseModel(
      id: map['id'] as int,
      name: map['name'] as String,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      inboundQty: (map['inbound_qty'] as num?)?.toDouble() ?? 0,
      outboundQty: (map['outbound_qty'] as num?)?.toDouble() ?? 0,
      inboundArea: (map['inbound_area'] as num?)?.toDouble() ?? 0,
      outboundArea: (map['outbound_area'] as num?)?.toDouble() ?? 0,
      productCount: (map['product_count'] as num?)?.toInt() ?? 0,
      stockQty: (map['stock_qty'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toInsertMap() => {
        'name': name.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  WarehouseModel copyWith({
    int? id,
    String? name,
    String? address,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? inboundQty,
    double? outboundQty,
    double? inboundArea,
    double? outboundArea,
    int? productCount,
    double? stockQty,
  }) {
    return WarehouseModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      inboundQty: inboundQty ?? this.inboundQty,
      outboundQty: outboundQty ?? this.outboundQty,
      inboundArea: inboundArea ?? this.inboundArea,
      outboundArea: outboundArea ?? this.outboundArea,
      productCount: productCount ?? this.productCount,
      stockQty: stockQty ?? this.stockQty,
    );
  }

  @override
  List<Object?> get props => [id, name, address, isActive, updatedAt];
}
