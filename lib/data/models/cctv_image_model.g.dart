// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cctv_image_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CctvImage _$CctvImageFromJson(Map<String, dynamic> json) => CctvImage(
      id: json['id'] as String,
      imageType: json['image_type'] as String,
      objectKey: json['object_key'] as String,
      thumbnailKey: json['thumbnail_key'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      mimeType: json['mime_type'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$CctvImageToJson(CctvImage instance) => <String, dynamic>{
      'id': instance.id,
      'image_type': instance.imageType,
      'object_key': instance.objectKey,
      'thumbnail_key': instance.thumbnailKey,
      'file_size': instance.fileSize,
      'mime_type': instance.mimeType,
      'width': instance.width,
      'height': instance.height,
      'created_at': instance.createdAt?.toIso8601String(),
    };
