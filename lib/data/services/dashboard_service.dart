import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// Dashboard statistics service backed by `/cctvs/stats`.
class DashboardService {
  final ApiClient _api;

  DashboardService(this._api);

  Future<Map<String, dynamic>> getStats() async {
    final response = await _api.get('/cctvs/stats');
    return response['data'] as Map<String, dynamic>;
  }
}

/// Provider for DashboardService.
final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(ref.watch(apiClientProvider));
});
