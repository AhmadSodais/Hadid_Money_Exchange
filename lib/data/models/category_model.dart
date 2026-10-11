import 'package:equatable/equatable.dart';

class CategoryModel extends Equatable {
  const CategoryModel({
    required this.id,
    required this.name,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? color;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CategoryModel.fromMap(Map<String, Object?> map) {
    return CategoryModel(
      id: map['id'] as int,
      name: map['name'] as String,
      color: map['color'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'sort_order': sortOrder,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, name, color, sortOrder, isActive];
}
