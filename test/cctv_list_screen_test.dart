import 'package:cctv_manager/core/errors/api_exception.dart';
import 'package:cctv_manager/core/utils/role_permissions.dart';
import 'package:cctv_manager/data/models/paginated_response.dart';
import 'package:cctv_manager/data/models/cctv_record_model.dart';
import 'package:cctv_manager/data/services/cctv_service.dart';
import 'package:cctv_manager/features/auth/providers/auth_provider.dart';
import 'package:cctv_manager/features/cctv/screens/cctv_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/fake_data.dart';

class _MockCctvService extends Mock implements CctvService {}

PaginatedResponse<CctvRecord> _page(List<CctvRecord> items) =>
    PaginatedResponse<CctvRecord>(
      items: items,
      page: 1,
      limit: 20,
      total: items.length,
      hasNext: false,
    );

void main() {
  late _MockCctvService service;

  setUp(() => service = _MockCctvService());

  void stubList(Future<PaginatedResponse<CctvRecord>> Function() answer) {
    when(() => service.getCctvRecords(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          status: any(named: 'status'),
          region: any(named: 'region'),
          township: any(named: 'township'),
          tag: any(named: 'tag'),
        )).thenAnswer((_) => answer());
  }

  Future<void> pump(WidgetTester tester, {bool isAdmin = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cctvServiceProvider.overrideWithValue(service),
          userRoleProvider.overrideWithValue(
            isAdmin ? UserRole.admin : UserRole.user,
          ),
        ],
        child: const MaterialApp(home: CctvListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CctvListScreen', () {
    testWidgets('shows the records returned by the backend', (tester) async {
      stubList(() async => _page([
            fakeRecord(id: 'a', cctvId: 'CCTV-YGN-000001'),
            fakeRecord(
                id: 'b', cctvId: 'CCTV-MDY-000002', status: 'MAINTENANCE'),
          ]));

      await pump(tester);

      expect(find.text('CCTV-YGN-000001'), findsOneWidget);
      expect(find.text('CCTV-MDY-000002'), findsOneWidget);
    });

    testWidgets('shows an empty state when there are no records',
        (tester) async {
      stubList(() async => _page([]));

      await pump(tester);

      expect(find.text('No CCTV records found'), findsOneWidget);
    });

    testWidgets('multiple purpose filters combine with search and All clears',
        (tester) async {
      stubList(() async => _page([
            fakeRecord(id: 'cpcs', cctvId: 'CCTV-CPCS', tags: ['CPCS']),
            fakeRecord(id: 'alprs', cctvId: 'CCTV-ALPRS', tags: ['ALPRS']),
            fakeRecord(id: 'frs', cctvId: 'CCTV-FRS', tags: ['FRS']),
          ]));

      await pump(tester);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'All'))
            .selected,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'intersection');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      clearInteractions(service);
      await tester.tap(find.widgetWithText(FilterChip, 'ALPRS'));
      await tester.pumpAndSettle();

      verify(() => service.getCctvRecords(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            search: 'intersection',
            status: any(named: 'status'),
            region: any(named: 'region'),
            township: any(named: 'township'),
            tag: 'ALPRS',
          )).called(1);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'ALPRS'))
            .selected,
        isTrue,
      );
      expect(find.text('CCTV-ALPRS'), findsOneWidget);
      expect(find.text('CCTV-CPCS'), findsNothing);
      expect(find.text('CCTV-FRS'), findsNothing);

      clearInteractions(service);
      await tester.tap(find.widgetWithText(FilterChip, 'FRS'));
      await tester.pumpAndSettle();
      verify(() => service.getCctvRecords(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            search: 'intersection',
            status: any(named: 'status'),
            region: any(named: 'region'),
            township: any(named: 'township'),
            tag: 'ALPRS,FRS',
          )).called(1);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'FRS'))
            .selected,
        isTrue,
      );
      expect(find.text('CCTV-ALPRS'), findsOneWidget);
      expect(find.text('CCTV-FRS'), findsOneWidget);
      expect(find.text('CCTV-CPCS'), findsNothing);

      clearInteractions(service);
      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();
      verify(() => service.getCctvRecords(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            search: 'intersection',
            status: any(named: 'status'),
            region: any(named: 'region'),
            township: any(named: 'township'),
            tag: null,
          )).called(1);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'All'))
            .selected,
        isTrue,
      );
      expect(find.text('CCTV-ALPRS'), findsOneWidget);
      expect(find.text('CCTV-CPCS'), findsOneWidget);
      expect(find.text('CCTV-FRS'), findsOneWidget);
    });

    testWidgets('shows the server error with a retry that reloads',
        (tester) async {
      var calls = 0;
      stubList(() async {
        calls++;
        if (calls == 1) {
          throw ApiException('Something went wrong on the server.');
        }
        return _page([fakeRecord()]);
      });

      await pump(tester);
      expect(find.text('Something went wrong on the server.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('CCTV-YGN-000001'), findsOneWidget);
    });

    testWidgets('only admins get the Add CCTV button', (tester) async {
      stubList(() async => _page([fakeRecord()]));

      await pump(tester, isAdmin: false);
      expect(find.text('Add CCTV'), findsNothing);

      await pump(tester, isAdmin: true);
      expect(find.text('Add CCTV'), findsOneWidget);
    });
  });
}
