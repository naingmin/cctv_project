import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/models/map_bounds.dart';
import '../../../data/services/cctv_service.dart';

/// Map state with viewport-based loading.
class MapState {
  final bool isLoading;
  final List<CctvRecord> markers;
  final String? error;
  final MapBounds? currentBounds;
  final String? focusedRecordId;

  const MapState({
    this.isLoading = false,
    this.markers = const [],
    this.error,
    this.currentBounds,
    this.focusedRecordId,
  });

  MapState copyWith({
    bool? isLoading,
    List<CctvRecord>? markers,
    String? error,
    MapBounds? currentBounds,
    String? focusedRecordId,
  }) {
    return MapState(
      isLoading: isLoading ?? this.isLoading,
      markers: markers ?? this.markers,
      error: error,
      currentBounds: currentBounds ?? this.currentBounds,
      focusedRecordId: focusedRecordId ?? this.focusedRecordId,
    );
  }
}

/// Map state notifier with viewport-based loading via the backend.
class MapNotifier extends StateNotifier<MapState> {
  final CctvService _service;

  MapNotifier(this._service) : super(const MapState());

  Future<void> loadMarkers(MapBounds bounds) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final markers = await _service.getMarkersInBounds(bounds);
      state = MapState(
        isLoading: false,
        markers: markers,
        currentBounds: bounds,
        focusedRecordId: state.focusedRecordId,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load map markers',
      );
    }
  }

  /// Ensure a specific record is present in the marker list and focus it.
  ///
  /// Markers are lightweight; if the record is outside the current viewport,
  /// we fetch its detail and inject a marker so it can be shown precisely.
  Future<CctvRecord?> focusRecord(String id) async {
    CctvRecord? match = _find(id);
    if (match == null) {
      try {
        match = await _service.getCctvById(id);
      } catch (_) {
        match = null;
      }
    }

    if (match == null) {
      state = state.copyWith(focusedRecordId: id);
      return null;
    }

    final byId = <String, CctvRecord>{
      for (final record in state.markers) record.id: record,
      match.id: match,
    };
    state = state.copyWith(
      markers: byId.values.toList(),
      focusedRecordId: match.id,
    );
    return match;
  }

  CctvRecord? _find(String id) {
    for (final record in state.markers) {
      if (record.id == id || record.cctvId == id) return record;
    }
    return null;
  }

  void clearFocus() {
    state = state.copyWith(focusedRecordId: null);
  }
}

/// Provider for map state.
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier(ref.watch(cctvServiceProvider));
});
