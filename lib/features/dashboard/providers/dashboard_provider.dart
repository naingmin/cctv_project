import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../data/models/dashboard_stats.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/services/cctv_service.dart';
import '../../../data/services/dashboard_service.dart';

/// Dashboard state.
class DashboardState {
  final bool isLoading;
  final DashboardStats? stats;
  final List<CctvRecord> recentUploads;
  final String? error;

  const DashboardState({
    this.isLoading = false,
    this.stats,
    this.recentUploads = const [],
    this.error,
  });
}

/// Dashboard notifier. Pulls aggregate stats from the backend (MongoDB
/// aggregation) and recent records from the paginated list endpoint.
class DashboardNotifier extends StateNotifier<DashboardState> {
  final DashboardService _statsService;
  final CctvService _cctvService;

  DashboardNotifier(this._statsService, this._cctvService)
      : super(const DashboardState()) {
    load();
  }

  Future<void> load() async {
    state = DashboardState(
      isLoading: true,
      stats: state.stats,
      recentUploads: state.recentUploads,
    );
    try {
      final raw = await _statsService.getStats();
      final recent = await _cctvService.getCctvRecords(page: 1, limit: 10);
      if (!mounted) return;
      state = DashboardState(
        isLoading: false,
        stats: DashboardStats.fromJson(raw),
        recentUploads: recent.items,
        error: null,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      state = DashboardState(
        isLoading: false,
        stats: state.stats,
        recentUploads: state.recentUploads,
        error: e.message,
      );
    } catch (e) {
      if (!mounted) return;
      state = DashboardState(
        isLoading: false,
        stats: state.stats,
        recentUploads: state.recentUploads,
        error: 'Failed to load dashboard.',
      );
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  // Reload when the signed-in user changes, but not on every auth state
  // change (e.g. isLoading toggles), which would rebuild the notifier while a
  // load is in flight.
  ref.watch(authProvider.select((s) => s.user?.id));
  return DashboardNotifier(
    ref.watch(dashboardServiceProvider),
    ref.watch(cctvServiceProvider),
  );
});
