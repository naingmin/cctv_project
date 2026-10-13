import 'package:flutter_test/flutter_test.dart';
import 'package:cctv_manager/data/models/cctv_record_model.dart';

void main() {
  group('CctvRecord', () {
    test('fromJson creates valid CctvRecord', () {
      final json = {
        'id': 'test-uuid',
        'cctv_id': 'CCTV-000001',
        'description': 'Intersection at Main St.',
        'latitude': 19.7633,
        'longitude': 96.0781,
        'region': 'Yangon',
        'township': 'Bahan',
        'street': 'Main St',
        'direction': 'E',
        'ip_address': '192.168.1.25',
        'username': 'stream-user',
        'password': 'camera-secret',
        'tags': ['ALPRS', 'CPCS'],
        'status': 'ACTIVE',
        'images': [],
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
      };

      final record = CctvRecord.fromJson(json);

      expect(record.id, 'test-uuid');
      expect(record.cctvId, 'CCTV-000001');
      expect(record.latitude, 19.7633);
      expect(record.longitude, 96.0781);
      expect(record.region, 'Yangon');
      expect(record.township, 'Bahan');
      expect(record.street, 'Main St');
      expect(record.direction, 'E');
      expect(record.description, 'Intersection at Main St.');
      expect(record.ipAddress, '192.168.1.25');
      expect(record.username, 'stream-user');
      expect(record.password, 'camera-secret');
      expect(record.tags, ['ALPRS', 'CPCS']);
      expect(record.status, 'ACTIVE');
      expect(record.operationalStatus, 'operational');
    });

    test('toJson produces valid JSON', () {
      final record = CctvRecord(
        id: 'test-uuid',
        cctvId: 'CCTV-000001',
        latitude: 19.7633,
        longitude: 96.0781,
        region: 'Yangon',
        township: 'Bahan',
        street: 'Main St',
        direction: 'E',
        status: 'ACTIVE',
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00Z'),
      );

      final json = record.toJson();

      expect(json['id'], 'test-uuid');
      expect(json['cctv_id'], 'CCTV-000001');
      expect(json['latitude'], 19.7633);
      expect(json['region'], 'Yangon');
      expect(json['township'], 'Bahan');
      expect(json['street'], 'Main St');
      expect(json['direction'], 'E');
      expect(json['status'], 'ACTIVE');
      expect(json.containsKey('ip_address'), isFalse);
      expect(json.containsKey('username'), isFalse);
      expect(json.containsKey('password'), isFalse);
    });

    test('copyWith creates new instance with updated fields', () {
      final record = CctvRecord(
        id: 'test-uuid',
        cctvId: 'CCTV-000001',
        latitude: 19.7633,
        longitude: 96.0781,
        region: 'Yangon',
        township: 'Bahan',
        street: 'Main St',
        direction: 'E',
        status: 'ACTIVE',
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00Z'),
      );

      final updated = record.copyWith(status: 'INACTIVE');

      expect(updated.status, 'INACTIVE');
      expect(updated.direction, 'E');
      expect(updated.operationalStatus, 'inactive');
      expect(updated.cctvId, 'CCTV-000001');
      expect(record.status, 'ACTIVE');
    });

    test('copyWith can clear direction', () {
      final record = CctvRecord(
        id: 'test-uuid',
        cctvId: 'CCTV-000001',
        latitude: 19.7633,
        longitude: 96.0781,
        direction: 'E',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      expect(record.copyWith(clearDirection: true).direction, isNull);
    });

    test('operationalStatus maps correctly', () {
      final active = CctvRecord(
        id: '1',
        cctvId: 'CCTV-001',
        latitude: 19.0,
        longitude: 96.0,
        status: 'ACTIVE',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final inactive = active.copyWith(status: 'INACTIVE');
      final maintenance = active.copyWith(status: 'MAINTENANCE');

      expect(active.operationalStatus, 'operational');
      expect(inactive.operationalStatus, 'inactive');
      expect(maintenance.operationalStatus, 'maintenance');
    });
  });

  group('CctvRecord image URLs', () {
    Map<String, dynamic> imageJson(String id, String type) => {
          'id': id,
          'cctv_record_id': 'rec-1',
          'image_type': type,
          'object_key':
              'cctv/CCTV-1/${type == 'CCTV_VIEW' ? 'view' : 'environment'}/$id.png',
          'mime_type': 'image/png',
          'created_at': '2024-01-01T00:00:00Z',
        };

    CctvRecord recordWith(List<Map<String, dynamic>> images,
            {String? viewUrl}) =>
        CctvRecord.fromJson({
          'id': 'rec-1',
          'cctv_id': 'CCTV-1',
          'latitude': 19.0,
          'longitude': 96.0,
          'status': 'ACTIVE',
          'images': images,
          'view_image_url': viewUrl,
          'created_at': '2024-01-01T00:00:00Z',
          'updated_at': '2024-01-01T00:00:00Z',
        });

    test('signedUrl is not read from JSON', () {
      // The backend never sends it - it is resolved per session.
      final record = recordWith([imageJson('img-1', 'CCTV_VIEW')]);
      expect(record.images.single.signedUrl, isNull);
    });

    test('view_image_url is parsed from the record', () {
      final record = recordWith(
        [imageJson('img-1', 'CCTV_VIEW')],
        viewUrl:
            'http://localhost:9000/bucket/cctv/CCTV-1/view/img-1.png?sig=1',
      );
      expect(record.viewImageUrl, isNotNull);
      expect(record.cctvViewImageUrl,
          'http://localhost:9000/bucket/cctv/CCTV-1/view/img-1.png?sig=1');
    });

    test('cctvViewImageUrl is null when there are no images', () {
      // This is what previously left the detail screen showing nothing.
      final record = recordWith([]);
      expect(record.cctvViewImageUrl, isNull);
    });

    test('withSignedUrls attaches resolved URLs to matching images', () {
      final record = recordWith([
        imageJson('img-1', 'CCTV_VIEW'),
        imageJson('img-2', 'ENVIRONMENT'),
      ]);

      final resolved = record.withSignedUrls({
        'img-1': 'https://storage.test/v/1.png?sig=a',
        'img-2': 'https://storage.test/e/2.png?sig=b',
      });

      expect(
          resolved.images[0].signedUrl, 'https://storage.test/v/1.png?sig=a');
      expect(
          resolved.images[1].signedUrl, 'https://storage.test/e/2.png?sig=b');
      // Original is untouched.
      expect(record.images.every((i) => i.signedUrl == null), isTrue);
    });

    test('withSignedUrls prefers a per-image URL over the record URL', () {
      final record = recordWith(
        [imageJson('img-1', 'CCTV_VIEW')],
        viewUrl: 'https://storage.test/record-level.png',
      );
      final resolved = record.withSignedUrls({
        'img-1': 'https://storage.test/per-image.png',
      });
      expect(resolved.cctvViewImageUrl, 'https://storage.test/per-image.png');
    });

    test('withSignedUrls falls back to the record URL for unmatched images',
        () {
      final record = recordWith(
        [imageJson('img-1', 'CCTV_VIEW')],
        viewUrl: 'https://storage.test/record-level.png',
      );
      // Batch response missing this image, e.g. it was deleted concurrently.
      final resolved =
          record.withSignedUrls({'other': 'https://storage.test/x.png'});
      expect(resolved.images.single.signedUrl, isNull);
      expect(
          resolved.cctvViewImageUrl, 'https://storage.test/record-level.png');
    });

    test('withSignedUrls is a no-op without images', () {
      final record = recordWith([]);
      expect(identical(record.withSignedUrls({'a': 'b'}), record), isTrue);
    });

    test('cctvViewImageUrl picks the CCTV_VIEW image, not the environment one',
        () {
      final record = recordWith([
        imageJson('img-env', 'ENVIRONMENT'),
        imageJson('img-view', 'CCTV_VIEW'),
      ]);
      final resolved = record.withSignedUrls({
        'img-env': 'https://storage.test/env.png',
        'img-view': 'https://storage.test/view.png',
      });
      expect(resolved.cctvViewImageUrl, 'https://storage.test/view.png');
    });
  });
}
