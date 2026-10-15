// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cctv_record_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CctvRecord _$CctvRecordFromJson(Map<String, dynamic> json) => CctvRecord(
      id: json['id'] as String,
      cctvId: json['cctv_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      region: json['region'] as String?,
      township: json['township'] as String?,
      street: json['street'] as String?,
      direction: json['direction'] as String?,
      ipAddress: json['ip_address'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      status: json['status'] as String? ?? 'ACTIVE',
      type: json['type'] as String?,
      description: json['description'] as String?,
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => CctvImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      viewImageUrl: json['view_image_url'] as String?,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$CctvRecordToJson(CctvRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'cctv_id': instance.cctvId,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'region': instance.region,
      'township': instance.township,
      'street': instance.street,
      'direction': instance.direction,
      'description': instance.description,
      'tags': instance.tags,
      'status': instance.status,
      'type': instance.type,
      'images': instance.images,
      'view_image_url': instance.viewImageUrl,
      'created_by': instance.createdBy,
      'updated_by': instance.updatedBy,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
