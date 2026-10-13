import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/models/paginated_response.dart';
import '../../../data/services/cctv_service.dart';

/// Marks a [CctvListState.copyWith] argument as "not passed", so that an
/// explicit `null` can clear a filter.
const _unset = Object();

/// CCTV list state with search and filters.
class CctvListState {
  final bool isLoading;
  final bool isLoadingMore;
  final List<CctvRecord> records;
  final String? error;
  final String search;

  /// One status or a comma-separated list, e.g. `ACTIVE,MAINTENANCE`.
  final String? statusFilter;
  final String? regionFilter;
  final String? townshipFilter;

  /// Selected purpose tags. An empty list represents "All".
  final List<String> selectedTags;
  final int page;
  final bool hasNext;
  final int total;

  const CctvListState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.records = const [],
    this.error,
    this.search = '',
    this.statusFilter,
    this.regionFilter,
    this.townshipFilter,
    this.selectedTags = const [],
    this.page = 1,
    this.hasNext = false,
    this.total = 0,
  });

  bool get hasFilters =>
      statusFilter != null ||
      regionFilter != null ||
      townshipFilter != null ||
      selectedTags.isNotEmpty;

  /// Compatibility accessor for code that refers to filters collectively.
  String? get tagFilter => selectedTags.isEmpty ? null : selectedTags.join(',');

  /// Compatibility accessor for older single-tag callers.
  String? get selectedTag =>
      selectedTags.length == 1 ? selectedTags.single : null;

  /// Nullable fields ([error] and the filters) are only changed when passed;
  /// pass `null` explicitly to clear them.
  CctvListState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    List<CctvRecord>? records,
    Object? error = _unset,
    String? search,
    Object? statusFilter = _unset,
    Object? regionFilter = _unset,
    Object? townshipFilter = _unset,
    Object? selectedTags = _unset,
    int? page,
    bool? hasNext,
    int? total,
  }) {
    return CctvListState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      records: records ?? this.records,
      error: identical(error, _unset) ? this.error : error as String?,
      search: search ?? this.search,
      statusFilter: identical(statusFilter, _unset)
          ? this.statusFilter
          : statusFilter as String?,
      regionFilter: identical(regionFilter, _unset)
          ? this.regionFilter
          : regionFilter as String?,
      townshipFilter: identical(townshipFilter, _unset)
          ? this.townshipFilter
          : townshipFilter as String?,
      selectedTags: identical(selectedTags, _unset)
          ? this.selectedTags
          : List<String>.unmodifiable(selectedTags as List<String>),
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
      total: total ?? this.total,
    );
  }
}

/// CCTV list state notifier (server-side search, filter, pagination).
class CctvListNotifier extends StateNotifier<CctvListState> {
  final CctvService _service;

  /// Incremented on every new query. A response is applied only if no newer
  /// query has started since, so a slow, stale response can never overwrite
  /// the results of the latest search or filter.
  int _generation = 0;

  CctvListNotifier(this._service) : super(const CctvListState()) {
    load();
  }

  Future<void> load({bool clearResults = false}) async {
    final generation = ++_generation;
    final query = state;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      error: null,
      page: 1,
      records: clearResults ? const [] : state.records,
      total: clearResults ? 0 : state.total,
    );
    try {
      final response = await _fetchMatchingPage(
        page: 1,
        selectedTags: query.selectedTags,
        query: query,
      );
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        records: response.items,
        page: response.page,
        hasNext: response.hasNext,
        total: response.total,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        error: e is ApiException ? e.message : 'Failed to load CCTV records.',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasNext) return;

    final generation = _generation;
    final query = state;
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final response = await _fetchMatchingPage(
        page: state.page + 1,
        selectedTags: query.selectedTags,
        query: query,
      );
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoadingMore: false,
        records: [...state.records, ...response.items],
        page: response.page,
        hasNext: response.hasNext,
        total: response.total,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: e is ApiException ? e.message : 'Failed to load more records.',
      );
    }
  }

  Future<PaginatedResponse<CctvRecord>> _fetchMatchingPage({
    required int page,
    required List<String> selectedTags,
    required CctvListState query,
  }) async {
    var response = await _fetch(page: page, query: query);
    var matchingItems = _matchingItems(response.items, selectedTags);

    // Older backend instances may ignore the tag query parameter. Never
    // display a nonmatching record; keep paging until we find a match or run
    // out of server results so an empty first page does not hide later matches.
    while (
        selectedTags.isNotEmpty && matchingItems.isEmpty && response.hasNext) {
      response = await _fetch(page: response.page + 1, query: query);
      matchingItems = _matchingItems(response.items, selectedTags);
    }

    return PaginatedResponse<CctvRecord>(
      items: matchingItems,
      page: response.page,
      limit: response.limit,
      total: response.total,
      hasNext: response.hasNext,
    );
  }

  List<CctvRecord> _matchingItems(
    List<CctvRecord> records,
    List<String> tags,
  ) {
    if (tags.isEmpty) return records;
    return records.where((record) => record.tags.any(tags.contains)).toList();
  }

  Future<PaginatedResponse<CctvRecord>> _fetch({
    required int page,
    required CctvListState query,
  }) async {
    final response = await _service.getCctvRecords(
      page: page,
      search: query.search.isNotEmpty ? query.search : null,
      status: query.statusFilter,
      region: query.regionFilter,
      township: query.townshipFilter,
      tag: query.selectedTags.isEmpty ? null : query.selectedTags.join(','),
    );

    // Resolve fresh presigned URLs for every record. The backend signs
    // view_image_url per response, but signedUrl on each image is never
    // sent - it must be resolved per session. Without this, images break
    // when the server IP changes because the old URLs point to the old host.
    final resolvedItems = <CctvRecord>[];
    for (final record in response.items) {
      if (record.images.isEmpty) {
        resolvedItems.add(record);
        continue;
      }
      try {
        final urls = await _service.getImageUrls(record.id);
        resolvedItems.add(record.withSignedUrls(urls));
      } catch (_) {
        // Keep the record with whatever URLs it already has; images fall
        // back to placeholders rather than failing the whole list.
        resolvedItems.add(record);
      }
    }

    return PaginatedResponse<CctvRecord>(
      items: resolvedItems,
      page: response.page,
      limit: response.limit,
      total: response.total,
      hasNext: response.hasNext,
    );
  }

  void setSearch(String search) {
    if (search == state.search) return;
    state = state.copyWith(search: search);
    load();
  }

  /// Replaces all filters. `null` clears that filter.
  void setFilters({String? status, String? region, String? township}) {
    state = state.copyWith(
      statusFilter: _blankToNull(status),
      regionFilter: _blankToNull(region),
      townshipFilter: _blankToNull(township),
    );
    load();
  }

  /// Replaces selected purpose filters; `null` or "All" clears the tag filter.
  void setSelectedTag(String? tag) {
    final normalized = _blankToNull(tag)?.toUpperCase();
    setSelectedTags(
      normalized == null || normalized == 'ALL' ? const [] : [normalized],
    );
  }

  /// Toggles a purpose filter; records matching any selected purpose are shown.
  void toggleSelectedTag(String tag) {
    final normalized = tag.trim().toUpperCase();
    if (normalized == 'ALL' || normalized.isEmpty) {
      setSelectedTags(const []);
      return;
    }
    final tags = [...state.selectedTags];
    if (tags.contains(normalized)) {
      tags.remove(normalized);
    } else {
      tags.add(normalized);
    }
    setSelectedTags(tags);
  }

  void setSelectedTags(Iterable<String> tags) {
    final normalized = tags
        .map((tag) => tag.trim().toUpperCase())
        .where((tag) => tag.isNotEmpty && tag != 'ALL')
        .toSet()
        .toList();
    if (normalized.length == state.selectedTags.length &&
        normalized.every(state.selectedTags.contains)) {
      return;
    }
    state = state.copyWith(selectedTags: normalized);
    load(clearResults: true);
  }

  void setTagFilter(String? tag) => setSelectedTag(tag);

  void clearFilters() {
    state = state.copyWith(
      statusFilter: null,
      regionFilter: null,
      townshipFilter: null,
      selectedTags: const [],
    );
    load();
  }

  void removeDeleted(String id) {
    state = state.copyWith(
      records: state.records.where((r) => r.id != id).toList(),
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}

/// Provider for CCTV list state.
final cctvListProvider =
    StateNotifierProvider<CctvListNotifier, CctvListState>((ref) {
  return CctvListNotifier(ref.watch(cctvServiceProvider));
});
