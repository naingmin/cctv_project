import 'package:cctv_manager/core/errors/api_exception.dart';
import 'package:cctv_manager/core/utils/role_permissions.dart';
import 'package:cctv_manager/data/services/cctv_service.dart';
import 'package:cctv_manager/features/auth/providers/auth_provider.dart';
import 'package:cctv_manager/features/cctv/screens/cctv_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/fake_data.dart';

class _MockCctvService extends Mock implements CctvService {}

void main() {
  late _MockCctvService service;

  setUp(() => service = _MockCctvService());

  Future<void> pump(WidgetTester tester, {UserRole role = UserRole.user}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cctvServiceProvider.overrideWithValue(service),
          userRoleProvider.overrideWithValue(role),
        ],
        child: const MaterialApp(home: CctvDetailScreen(cctvId: 'r1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CctvDetailScreen', () {
    testWidgets('shows the record details', (tester) async {
      when(() => service.getCctvById('r1')).thenAnswer((_) async => fakeRecord());

      await pump(tester);

      expect(find.text('CCTV-YGN-000001'), findsWidgets);
      expect(find.textContaining('Bahan'), findsWidgets);
      expect(find.textContaining('Main intersection camera'), findsOneWidget);
    });

    testWidgets('viewers can add images but not edit or delete', (tester) async {
      when(() => service.getCctvById('r1')).thenAnswer((_) async => fakeRecord());

      await pump(tester, role: UserRole.user);

      expect(find.byTooltip('Add image'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('admins can edit and delete', (tester) async {
      when(() => service.getCctvById('r1')).thenAnswer((_) async => fakeRecord());

      await pump(tester, role: UserRole.admin);

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows the error when the record cannot be loaded', (tester) async {
      when(() => service.getCctvById('r1')).thenThrow(
        ApiException('The requested resource was not found.'),
      );

      await pump(tester);

      expect(find.text('The requested resource was not found.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
