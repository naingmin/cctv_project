// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      name: json['full_name'] as String,
      email: json['email'] as String,
      role: _roleFromJson(json['role'] as String),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      lastSignIn: json['last_login_at'] == null
          ? null
          : DateTime.parse(json['last_login_at'] as String),
      region: json['region'] as String?,
      township: json['township'] as String?,
    );

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'full_name': instance.name,
      'email': instance.email,
      'role': _roleToJson(instance.role),
      'is_active': instance.isActive,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'last_login_at': instance.lastSignIn?.toIso8601String(),
      'region': instance.region,
      'township': instance.township,
    };
