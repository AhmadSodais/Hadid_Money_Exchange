import 'package:equatable/equatable.dart';

class RoleModel extends Equatable {
  const RoleModel({
    required this.id,
    required this.name,
    this.description,
    this.isSystem = false,
    this.permissions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? description;
  final bool isSystem;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoleModel.fromMap(
    Map<String, Object?> map, {
    List<String> permissions = const [],
  }) {
    return RoleModel(
      id: map['id'] as int,
      name: map['name'] as String,
      description: map['description'] as String?,
      isSystem: (map['is_system'] as int? ?? 0) == 1,
      permissions: permissions,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
        'name': name,
        'description': description,
        'is_system': isSystem ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  RoleModel copyWith({
    int? id,
    String? name,
    String? description,
    bool? isSystem,
    List<String>? permissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isSystem: isSystem ?? this.isSystem,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, permissions];
}

class AppUserModel extends Equatable {
  const AppUserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.roleId,
    this.roleName,
    this.employeeId,
    this.isActive = true,
    this.permissions = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String username;
  final String displayName;
  final int roleId;
  final String? roleName;
  final int? employeeId;
  final bool isActive;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool hasPermission(String key) => permissions.contains(key);

  factory AppUserModel.fromMap(
    Map<String, Object?> map, {
    List<String> permissions = const [],
  }) {
    return AppUserModel(
      id: map['id'] as int,
      username: map['username'] as String,
      displayName: map['display_name'] as String,
      roleId: map['role_id'] as int,
      roleName: map['role_name'] as String?,
      employeeId: map['employee_id'] as int?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      permissions: permissions,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  AppUserModel copyWith({
    int? id,
    String? username,
    String? displayName,
    int? roleId,
    String? roleName,
    int? employeeId,
    bool? isActive,
    List<String>? permissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      employeeId: employeeId ?? this.employeeId,
      isActive: isActive ?? this.isActive,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, username, roleId, permissions];
}
