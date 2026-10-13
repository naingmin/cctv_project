import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/upload_queue_service.dart';

/// Settings state.
class SettingsState {
  final int pendingUploads;
  final int failedUploads;

  const SettingsState({
    this.pendingUploads = 0,
    this.failedUploads = 0,
  });

  SettingsState copyWith({
    int? pendingUploads,
    int? failedUploads,
  }) {
    return SettingsState(
      pendingUploads: pendingUploads ?? this.pendingUploads,
      failedUploads: failedUploads ?? this.failedUploads,
    );
  }
}

/// Settings notifier.
class SettingsNotifier extends StateNotifier<SettingsState> {
  final UploadQueueService _uploadQueue;

  SettingsNotifier(this._uploadQueue) : super(const SettingsState()) {
    _loadUploadStats();
  }

  void _loadUploadStats() {
    state = SettingsState(
      pendingUploads: _uploadQueue.pendingCount,
      failedUploads: _uploadQueue.failedCount,
    );
  }

  Future<void> retryFailedUploads() async {
    // Retry logic would go here
    _loadUploadStats();
  }

  Future<void> clearUploaded() async {
    await _uploadQueue.clearUploaded();
    _loadUploadStats();
  }
}

/// Provider for settings.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final uploadQueue = ref.watch(uploadQueueServiceProvider);
  return SettingsNotifier(uploadQueue);
});
