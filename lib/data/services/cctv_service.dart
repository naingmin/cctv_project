import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../models/cctv_record_model.dart';
import '../models/map_bounds.dart';
import '../models/paginated_response.dart';

/// CCTV service backed by the FastAPI `/cctvs` and image endpoints.
class CctvService {
  final ApiClient _api;

  CctvService(this._api);

  Future<PaginatedResponse<CctvRecord>> getCctvRecords({
    int page = 1,
    int limit = AppConstants.defaultPageSize,
    String? search,
    String? status,
    String? type,
    String? region,
    String? township,
    String? tag,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (type != null && type.isNotEmpty) query['type'] = type;
    if (region != null && region.isNotEmpty) query['region'] = region;
    if (township != null && township.isNotEmpty) query['township'] = township;
    if (tag != null && tag.isNotEmpty) query['tag'] = tag;

    final response = await _api.get('/cctvs', query: query);
    final data = response['data'] as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => CctvRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = data['pagination'] as Map<String, dynamic>;
    return PaginatedResponse<CctvRecord>(
      items: items,
      page: pagination['page'] as int,
      limit: pagination['limit'] as int,
      total: pagination['total'] as int,
      hasNext: pagination['has_next'] as bool,
    );
  }

  /// Region -> townships already used by records the user can see.
  Future<Map<String, List<String>>> getAreas() async {
    final response = await _api.get('/cctvs/areas');
    final regions = (response['data'] as Map<String, dynamic>)['regions']
        as Map<String, dynamic>;
    return regions.map(
      (region, townships) => MapEntry(
        region,
        (townships as List).map((t) => t.toString()).toList(),
      ),
    );
  }

  Future<CctvRecord> getCctvById(String id) async {
    final response = await _api.get('/cctvs/$id');
    return CctvRecord.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<CctvRecord> createCctv(CctvRecord record) async {
    final response = await _api.post('/cctvs', data: _writePayload(record));
    return CctvRecord.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<CctvRecord> updateCctv(String id, CctvRecord record) async {
    final response = await _api.put('/cctvs/$id',
        data: _writePayload(record, partial: true));
    return CctvRecord.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> deleteCctv(String id) async {
    await _api.delete('/cctvs/$id');
  }

  /// Lightweight markers for the current map viewport.
  Future<List<CctvRecord>> getMarkersInBounds(MapBounds bounds) async {
    final response = await _api.get(
      '/cctvs/map',
      query: {
        'min_lat': bounds.south,
        'max_lat': bounds.north,
        'min_lng': bounds.west,
        'max_lng': bounds.east,
        'zoom': bounds.zoom,
      },
    );
    final data = response['data'] as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => _markerToRecord(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CctvRecord>> getNearby({
    required double latitude,
    required double longitude,
    double radiusMeters = 1000,
  }) async {
    final response = await _api.get(
      '/cctvs/nearby',
      query: {
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
      },
    );
    final data = response['data'] as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => _markerToRecord(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getStats() async {
    final response = await _api.get('/cctvs/stats');
    return response['data'] as Map<String, dynamic>;
  }

  /// Resolve a short-lived signed URL for an image.
  Future<String> getImageUrl(String cctvId, String imageId) async {
    final response = await _api.get('/cctvs/$cctvId/images/$imageId/url');
    return (response['data'] as Map<String, dynamic>)['url'] as String;
  }

  /// Resolve presigned URLs for every image on a record in one call.
  ///
  /// Returns a map of image id to URL. Without this, a record with N images
  /// costs N round trips just to render a gallery.
  Future<Map<String, String>> getImageUrls(String cctvId) async {
    final response = await _api.get('/cctvs/$cctvId/images/urls');
    final data = (response['data'] as Map<String, dynamic>)['urls'];
    if (data is! Map) return const {};
    return data.map((key, value) => MapEntry(key as String, value as String));
  }

  Future<void> deleteImage(String cctvId, String imageId) async {
    await _api.delete('/cctvs/$cctvId/images/$imageId');
  }

  /// Request an upload authorization.
  ///
  /// Returns an absolute presigned URL to PUT the bytes to, plus the
  /// server-chosen object key to report back on completion.
  Future<Map<String, dynamic>> presign({
    required String cctvId,
    required String imageType,
    required String filename,
    required String contentType,
  }) async {
    final response = await _api.post(
      '/uploads/presign',
      data: {
        'cctv_id': cctvId,
        'image_type': imageType,
        'filename': filename,
        'content_type': contentType,
      },
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// Upload a file straight to object storage using its presigned URL.
  ///
  /// Uses a bare [Dio] with no interceptors: the URL is already SigV4-signed,
  /// and attaching the API's Authorization header would break the signature
  /// and leak the bearer token to the storage host.
  Future<void> uploadToStorage(
    String uploadUrl,
    List<int> bytes, {
    required String contentType,
    Function(int sent, int total)? onProgress,
  }) async {
    final dio = Dio();
    // Bytes are sent as a plain body rather than a stream so Dio derives
    // Content-Length itself - a chunked body would not match the signature.
    await dio.put<void>(
      uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
      onSendProgress: onProgress,
    );
  }

  /// Finalize an uploaded image so the backend records its metadata.
  Future<void> completeImage({
    required String cctvId,
    required String objectKey,
    required String imageType,
    required String mimeType,
    int? fileSize,
    int? width,
    int? height,
  }) async {
    await _api.post('/cctvs/$cctvId/images/complete', data: {
      'object_key': objectKey,
      'image_type': imageType,
      'mime_type': mimeType,
      'file_size': fileSize,
      'width': width,
      'height': height,
    });
  }

  Map<String, dynamic> _writePayload(CctvRecord r, {bool partial = false}) {
    return {
      'cctv_id': r.cctvId,
      'latitude': r.latitude,
      'longitude': r.longitude,
      'region': r.region,
      'township': r.township,
      'street': r.street,
      'direction': r.direction,
      'ip_address': r.ipAddress,
      'username': r.username,
      'password': r.password,
      'tags': r.tags,
      'status': r.status,
      'type': r.type,
      'description': r.description,
    };
  }

  CctvRecord _markerToRecord(Map<String, dynamic> json) {
    final now = DateTime.now();
    return CctvRecord(
      id: json['id'] as String,
      cctvId: json['cctv_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      direction: json['direction'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Provider for CctvService.
final cctvServiceProvider = Provider<CctvService>((ref) {
  return CctvService(ref.watch(apiClientProvider));
});
