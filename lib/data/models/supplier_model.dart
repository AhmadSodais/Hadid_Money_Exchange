import 'package:equatable/equatable.dart';

class SupplierModel extends Equatable {
  const SupplierModel({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.productCount = 0,
    this.outstandingPayable = 0,
  });

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int productCount;
  final double outstandingPayable;

  factory SupplierModel.fromMap(Map<String, Object?> map) {
    return SupplierModel(
      id: map['id'] as int,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      productCount: (map['product_count'] as int?) ?? 0,
      outstandingPayable:
          (map['outstanding_payable'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    if (includeId) map['id'] = id;
    return map;
  }

  SupplierModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      productCount: productCount,
      outstandingPayable: outstandingPayable,
    );
  }

  @override
  List<Object?> get props => [id, name, phone, email, isArchived];
}
