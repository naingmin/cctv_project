import 'package:json_annotation/json_annotation.dart';

part 'cctv_image_model.g.dart';

/// CCTV image metadata returned by the backend.
///
/// The binary object lives in MinIO (S3-compatible); this model carries only
/// metadata plus a short-lived presigned URL resolved per response.
@JsonSerializable()
class CctvImage {
  final String id;
  @JsonKey(name: 'image_type')
  final String imageType; // 'CCTV_VIEW' or 'ENVIRONMENT'
  @JsonKey(name: 'object_key')
  final String objectKey;
  @JsonKey(name: 'thumbnail_key')
  final String? thumbnailKey;
  @JsonKey(name: 'file_size')
  final int? fileSize;
  @JsonKey(name: 'mime_type')
  final String? mimeType;
  final int? width;
  final int? height;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  /// Resolved at runtime (presigned GET URL). Not part of the stored metadata.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? signedUrl;

  const CctvImage({
    required this.id,
    required this.imageType,
    required this.objectKey,
    this.thumbnailKey,
    this.fileSize,
    this.mimeType,
    this.width,
    this.height,
    this.createdAt,
    this.signedUrl,
  });

  factory CctvImage.fromJson(Map<String, dynamic> json) =>
      _$CctvImageFromJson(json);

  Map<String, dynamic> toJson() => _$CctvImageToJson(this);

  CctvImage copyWith({String? signedUrl}) => CctvImage(
        id: id,
        imageType: imageType,
        objectKey: objectKey,
        thumbnailKey: thumbnailKey,
        fileSize: fileSize,
        mimeType: mimeType,
        width: width,
        height: height,
        createdAt: createdAt,
        signedUrl: signedUrl ?? this.signedUrl,
      );
}
