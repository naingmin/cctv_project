import 'package:json_annotation/json_annotation.dart';

import '../../core/utils/role_permissions.dart';

part 'user_model.g.dart';

// Converts between backend role strings ("ADMIN"/"USER") and UserRole enum.
UserRole _roleFromJson(String value) => roleFromString(value);

String _roleToJson(UserRole role) => roleToString(role);

/// Field names follow the backend's snake_case JSON. The annotations are what
/// `build_runner` reads, so regenerating `user_model.g.dart` keeps them.
@JsonSerializable()
class UserModel {
  final String id;
  final String username;
  @JsonKey(name: 'full_name')
  final String name;
  final String email;
  @JsonKey(fromJson: _roleFromJson, toJson: _roleToJson)
  final UserRole role;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;
  @JsonKey(name: 'last_login_at')
  final DateTime? lastSignIn;

  /// Area a Regional Admin / Supervisor is restricted to (null otherwise).
  final String? region;
  final String? township;

  const UserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
    this.lastSignIn,
    this.region,
    this.township,
  });

  /// First letter for avatars; safe for empty names.
  String get initial {
    final source = name.trim().isNotEmpty ? name.trim() : username.trim();
    return source.isEmpty ? '?' : source[0].toUpperCase();
  }

  /// "Yangon / Bahan", "Yangon", or null when no area is assigned.
  String? get areaLabel {
    final parts = [region, township]
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' / ');
  }

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  UserModel copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
    UserRole? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSignIn,
    String? region,
    String? township,
    bool clearArea = false,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSignIn: lastSignIn ?? this.lastSignIn,
      region: clearArea ? null : (region ?? this.region),
      township: clearArea ? null : (township ?? this.township),
    );
  }
}