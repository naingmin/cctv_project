import 'package:cctv_manager/features/cctv/providers/cctv_list_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filtered = CctvListState(
    statusFilter: 'ACTIVE,MAINTENANCE',
    regionFilter: 'Yangon',
    townshipFilter: 'Bahan',
    selectedTags: ['ALPRS', 'FRS'],
    error: 'boom',
  );

  test('explicit null clears filters', () {
    final cleared = filtered.copyWith(
      statusFilter: null,
      regionFilter: null,
      townshipFilter: null,
      selectedTags: const <String>[],
    );
    expect(cleared.statusFilter, isNull);
    expect(cleared.regionFilter, isNull);
    expect(cleared.townshipFilter, isNull);
    expect(cleared.selectedTags, isEmpty);
    expect(cleared.hasFilters, isFalse);
  });

  test('omitted arguments keep existing values', () {
    final next = filtered.copyWith(isLoading: true);
    expect(next.statusFilter, 'ACTIVE,MAINTENANCE');
    expect(next.regionFilter, 'Yangon');
    expect(next.townshipFilter, 'Bahan');
    expect(next.selectedTags, ['ALPRS', 'FRS']);
    expect(next.error, 'boom');
    expect(next.hasFilters, isTrue);
  });

  test('error can be cleared explicitly', () {
    expect(filtered.copyWith(error: null).error, isNull);
  });
}
