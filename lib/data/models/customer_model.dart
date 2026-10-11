import 'package:equatable/equatable.dart';

class CustomerModel extends Equatable {
  const CustomerModel({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.outstandingBalance = 0,
    this.totalPurchases = 0,
    this.lastPurchaseAt,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double outstandingBalance;
  final double totalPurchases;
  final DateTime? lastPurchaseAt;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CustomerModel.fromMap(Map<String, Object?> map) {
    return CustomerModel(
      id: map['id'] as int,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      outstandingBalance:
          (map['outstanding_balance'] as num?)?.toDouble() ?? 0,
      totalPurchases: (map['total_purchases'] as num?)?.toDouble() ?? 0,
      lastPurchaseAt: map['last_purchase_at'] != null
          ? DateTime.parse(map['last_purchase_at'] as String)
          : null,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'outstanding_balance': outstandingBalance,
      'total_purchases': totalPurchases,
      'last_purchase_at': lastPurchaseAt?.toIso8601String(),
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    if (includeId) map['id'] = id;
    return map;
  }

  CustomerModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    double? outstandingBalance,
    double? totalPurchases,
    DateTime? lastPurchaseAt,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      lastPurchaseAt: lastPurchaseAt ?? this.lastPurchaseAt,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, phone, outstandingBalance];
}
