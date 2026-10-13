import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cctv_manager/data/models/cctv_record_model.dart';
import 'package:cctv_manager/data/models/map_bounds.dart';
import 'package:cctv_manager/data/services/cctv_service.dart';
import 'package:cctv_manager/features/map/providers/map_provider.dart';

class MockCctvService extends Mock implements CctvService {}

void main() {
  CctvRecord record({required String id, String? cctvId, double? lat, double? lng}) {
    final created = DateTime(2024, 1, 1);
    return CctvRecord(
      id: id,
      cctvId: cctvId ?? 'CCTV-$id',
      latitude: lat ?? 19.7633,
      longitude: lng ?? 96.0781,
      status: 'ACTIVE',
      createdAt: created,
      updatedAt: created,
    );
  }

  const bounds = MapBounds(north: 20, south: 19, east: 97, west: 96, zoom: 12);

  group('MapNotifier', () {
    test('focusRecord finds a local record outside the viewport and marks it',
        () async {
      final local = record(id: 'local-1');
      final service = MockCctvService();
      when(() => service.getMarkersInBounds(bounds))
          .thenAnswer((_) async => [local]);
      when(() => service.getCctvById('local-1'))
          .thenAnswer((_) async => local);

      final notifier = MapNotifier(service);
      await notifier.loadMarkers(bounds);

      final found = await notifier.focusRecord('local-1');

      expect(found, isNotNull);
      expect(found!.id, 'local-1');
      expect(notifier.state.focusedRecordId, 'local-1');
      expect(notifier.state.markers.any((r) => r.id == 'local-1'), true);
    });

    test('focusRecord matches by cctvId', () async {
      final local = record(id: 'local-2', cctvId: 'CCTV-000042');
      final service = MockCctvService();
      when(() => service.getMarkersInBounds(bounds))
          .thenAnswer((_) async => [local]);
      when(() => service.getCctvById('CCTV-000042'))
          .thenAnswer((_) async => local);

      final notifier = MapNotifier(service);
      await notifier.loadMarkers(bounds);

      final found = await notifier.focusRecord('CCTV-000042');

      expect(found, isNotNull);
      expect(found!.id, 'local-2');
      expect(notifier.state.focusedRecordId, 'local-2');
    });

    test('focusRecord returns null for an unknown record', () async {
      final service = MockCctvService();
      when(() => service.getMarkersInBounds(bounds))
          .thenAnswer((_) async => []);
      when(() => service.getCctvById('missing'))
          .thenAnswer((_) async => throw Exception('not found'));

      final notifier = MapNotifier(service);
      await notifier.loadMarkers(bounds);

      final found = await notifier.focusRecord('missing');

      expect(found, isNull);
      expect(notifier.state.focusedRecordId, 'missing');
    });

    test('loadMarkers surfaces records from the service', () async {
      final local = record(id: 'local-3');
      final service = MockCctvService();
      when(() => service.getMarkersInBounds(bounds))
          .thenAnswer((_) async => [local]);

      final notifier = MapNotifier(service);
      await notifier.loadMarkers(bounds);

      expect(notifier.state.isLoading, false);
      expect(notifier.state.markers.any((r) => r.id == 'local-3'), true);
    });
  });
}
