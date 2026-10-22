import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/services/cctv_service.dart';

/// CCTV detail state.
class CctvDetailState {
  final bool isLoading;
  final bool isTestingConnection;
  final CctvRecord? record;
  final String? error;

  const CctvDetailState({
    this.isLoading = false,
    this.isTestingConnection = false,
    this.record,
    this.error,
  });

  CctvDetailState copyWith({
    bool? isLoading,
    bool? isTestingConnection,
    CctvRecord? record,
    String? error,
  }) {
    return CctvDetailState(
      isLoading: isLoading ?? this.isLoading,
      isTestingConnection: isTestingConnection ?? this.isTestingConnection,
      record: record ?? this.record,
      error: error,
    );
  }
}

/// CCTV detail notifier.
class CctvDetailNotifier extends StateNotifier<CctvDetailState> {
  final CctvService _service;
  final String cctvId;

  CctvDetailNotifier(this._service, this.cctvId)
      : super(const CctvDetailState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      var record = await _service.getCctvById(cctvId);
      // Presigned URLs are per-session, so resolve them after every load.
      if (record.images.isNotEmpty) {
        try {
          record = record.withSignedUrls(await _service.getImageUrls(cctvId));
        } catch (_) {
          // Keep the record; images fall back to placeholders rather than
          // failing the whole screen.
        }
      }
      state = CctvDetailState(isLoading: false, record: record);
    } on ApiException catch (e) {
      state = CctvDetailState(isLoading: false, error: e.message);
    } catch (e) {
      state =
          const CctvDetailState(isLoading: false, error: 'Record not found');
    }
  }

  /// Deletes the record. Returns null on success, otherwise an error message.
  Future<String?> delete() async {
    try {
      await _service.deleteCctv(cctvId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to delete record.';
    }
  }

  Future<CctvConnectionTestResult> testConnection() async {
    state = state.copyWith(isTestingConnection: true);
    try {
      final result = await _service.testConnection(cctvId);
      final current = state.record;
      if (current != null) {
        state = state.copyWith(
          record: current.copyWith(
            status: result.cctv.status,
            lastChecked: result.cctv.lastChecked,
          ),
        );
      }
      return result;
    } finally {
      if (mounted) state = state.copyWith(isTestingConnection: false);
    }
  }

  Future<void> deleteImage(String imageId) async {
    await _service.deleteImage(cctvId, imageId);
    await load();
  }

  Future<String> imageUrl(String imageId) =>
      _service.getImageUrl(cctvId, imageId);
}

/// Provider for CCTV detail.
final cctvDetailProvider =
    StateNotifierProvider.family<CctvDetailNotifier, CctvDetailState, String>(
        (ref, cctvId) {
  return CctvDetailNotifier(ref.watch(cctvServiceProvider), cctvId);
});
