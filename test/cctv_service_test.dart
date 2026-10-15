import 'package:cctv_manager/core/network/api_client.dart';
import 'package:cctv_manager/data/models/cctv_record_model.dart';
import 'package:cctv_manager/data/services/cctv_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  late _MockApiClient api;
  late CctvService service;
  late CctvRecord record;

  setUp(() {
    api = _MockApiClient();
    service = CctvService(api);
    record = CctvRecord(
      id: 'record-id',
      cctvId: 'CCTV-YGN-000001',
      latitude: 16.8409,
      longitude: 96.1561,
      type: 'Dome',
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
  });

  final expectedPayload = <String, dynamic>{
    'cctv_id': 'CCTV-YGN-000001',
    'latitude': 16.8409,
    'longitude': 96.1561,
    'region': null,
    'township': null,
    'street': null,
    'direction': null,
    'ip_address': null,
    'username': null,
    'password': null,
    'tags': <String>[],
    'status': 'ACTIVE',
    'type': 'Dome',
    'description': null,
  };

  test('createCctv sends Type to the backend', () async {
    when(() => api.post('/cctvs', data: expectedPayload))
        .thenAnswer((_) async => {'data': record.toJson()});

    final created = await service.createCctv(record);

    expect(created.type, 'Dome');
    verify(() => api.post('/cctvs', data: expectedPayload)).called(1);
  });

  test('updateCctv sends Type to the backend', () async {
    when(() => api.put('/cctvs/record-id', data: expectedPayload))
        .thenAnswer((_) async => {'data': record.toJson()});

    final updated = await service.updateCctv('record-id', record);

    expect(updated.type, 'Dome');
    verify(() => api.put('/cctvs/record-id', data: expectedPayload)).called(1);
  });
}
