import 'package:json_annotation/json_annotation.dart';

import 'cctv_image_model.dart';

part 'cctv_record_model.g.dart';

const cctvTagDescriptions = <String, String>{
  'ALPRS': 'Automatic License Plate Recognition System',
  'FRS': 'Face Recognition System',
  'CPCS': 'Car Pedestrian Counting System',
  'ARDS': 'Arm Robbery Detection System',
};

/// CCTV record data model, matching the FastAPI `/cctvs` response.
@JsonSerializable()
class CctvRecord {
  final String id;
  @JsonKey(name: 'cctv_id')
  final String cctvId;
  final double latitude;
  final double longitude;
  final String? region;
  final String? township;
  final String? street;
  final String? direction;
  final String? description;
  @JsonKey(name: 'ip_address', includeToJson: false)
  final String? ipAddress;
  @JsonKey(includeToJson: false)
  final String? username;
  @JsonKey(includeToJson: false)
  final String? password;
  final List<String> tags;

  /// Status is one of ACTIVE, INACTIVE, MAINTENANCE (backend enum).
  final String status;
  final String? type;
  final List<CctvImage> images;

  /// Presigned GET URL for the primary view image, supplied per response
  /// because it expires and therefore cannot be persisted server-side.
  @JsonKey(name: 'view_image_url')
  final String? viewImageUrl;
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @JsonKey(name: 'updated_by')
  final String? updatedBy;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const CctvRecord({
    required this.id,
    required this.cctvId,
    required this.latitude,
    required this.longitude,
    this.region,
    this.township,
    this.street,
    this.direction,
    this.ipAddress,
    this.username,
    this.password,
    this.tags = const [],
    this.status = 'ACTIVE',
    this.type,
    this.description,
    this.images = const [],
    this.viewImageUrl,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CctvRecord.fromJson(Map<String, dynamic> json) =>
      _$CctvRecordFromJson(json);

  Map<String, dynamic> toJson() => _$CctvRecordToJson(this);

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  /// Normalized operational status used by UI badges
  /// ('operational' | 'inactive' | 'maintenance').
  String get operationalStatus {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return 'operational';
      case 'MAINTENANCE':
        return 'maintenance';
      case 'INACTIVE':
      default:
        return 'inactive';
    }
  }

  String? get cctvViewImageUrl {
    // Prefer a per-image URL when one has been resolved, else the record-level
    // URL the backend signs for the primary view image.
    final view = images.firstWhere(
      (i) => i.signedUrl != null && i.imageType == 'CCTV_VIEW',
      orElse: () => images.firstWhere(
        (i) => i.signedUrl != null,
        orElse: () => const CctvImage(
          id: '',
          imageType: '',
          objectKey: '',
        ),
      ),
    );
    return view.signedUrl ?? viewImageUrl;
  }

  List<CctvImage> get environmentImages =>
      images.where((i) => i.imageType == 'ENVIRONMENT').toList();

  int get imageCount => images.length;

  /// Attach resolved presigned URLs to this record's images.
  ///
  /// `signedUrl` is never sent by the backend - it has to be resolved per
  /// session - so records arrive with it null and every image would render as
  /// a placeholder until this is applied.
  CctvRecord withSignedUrls(Map<String, String> urlsByImageId) {
    if (images.isEmpty || urlsByImageId.isEmpty) return this;
    return copyWith(
      images: images
          .map((img) => img.copyWith(signedUrl: urlsByImageId[img.id]))
          .toList(),
    );
  }

  CctvRecord copyWith({
    String? id,
    String? cctvId,
    double? latitude,
    double? longitude,
    String? region,
    String? township,
    String? street,
    String? direction,
    String? ipAddress,
    String? username,
    String? password,
    List<String>? tags,
    String? status,
    String? type,
    String? description,
    List<CctvImage>? images,
    String? viewImageUrl,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDirection = false,
  }) {
    return CctvRecord(
      id: id ?? this.id,
      cctvId: cctvId ?? this.cctvId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      region: region ?? this.region,
      township: township ?? this.township,
      street: street ?? this.street,
      direction: clearDirection ? null : (direction ?? this.direction),
      ipAddress: ipAddress ?? this.ipAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      type: type ?? this.type,
      description: description ?? this.description,
      images: images ?? this.images,
      viewImageUrl: viewImageUrl ?? this.viewImageUrl,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
