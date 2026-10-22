import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/dashboard_websocket_service.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../cctv/providers/cctv_list_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/recent_uploads_card.dart';

/// Admin dashboard screen with statistics.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    ref.listen(dashboardUpdatesProvider, (previous, next) {
      next.whenData(ref.read(dashboardProvider.notifier).applyUpdate);
    });

    Future<void> refresh() async {
      // Reload the actual CCTV data first, then refresh the dashboard stats.
      await ref.read(cctvListProvider.notifier).load();
      await ref.read(dashboardProvider.notifier).load();
    }

    void goToCctvList({String? status, String? dateFrom, String? dateTo}) {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (dateFrom != null) queryParams['date_from'] = dateFrom;
      if (dateTo != null) queryParams['date_to'] = dateTo;
      final uri = Uri(path: '/cctv', queryParameters: queryParams);
      context.push(uri.toString());
    }

    void goToTodayAdded() {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      goToCctvList(
        dateFrom: startOfDay.toIso8601String(),
        dateTo: endOfDay.toIso8601String(),
      );
    }

    void goToThisMonthAdded() {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 1);
      goToCctvList(
        dateFrom: startOfMonth.toIso8601String(),
        dateTo: endOfMonth.toIso8601String(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: state.isLoading && state.stats == null
            ? const ShimmerList()
            : state.error != null && state.stats == null
                ? ErrorView(
                    message: state.error!,
                    onRetry: () => ref.read(dashboardProvider.notifier).load(),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Security Overview',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        if (state.stats != null) ...[
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.5,
                            children: [
                              StatCard(
                                label: 'Total CCTV',
                                value: _formatNumber(state.stats!.totalCctv),
                                icon: Icons.videocam,
                                color: AppColors.primary,
                                onTap: () => context.push('/cctv'),
                              ),
                              StatCard(
                                label: 'Added Today',
                                value: _formatNumber(state.stats!.addedToday),
                                icon: Icons.today,
                                color: AppColors.success,
                                onTap: goToTodayAdded,
                              ),
                              StatCard(
                                label: 'Total Users',
                                value: _formatNumber(state.stats!.totalUsers),
                                icon: Icons.people,
                                color: AppColors.accent,
                                onTap: () => context.push('/users'),
                              ),
                              StatCard(
                                label: 'Active',
                                value: _formatNumber(state.stats!.activeCctv),
                                icon: Icons.check_circle,
                                color: AppColors.success,
                                onTap: () => goToCctvList(status: 'ACTIVE'),
                              ),
                              StatCard(
                                label: 'Inactive',
                                value: _formatNumber(state.stats!.inactiveCctv),
                                icon: Icons.cancel,
                                color: AppColors.danger,
                                onTap: () => goToCctvList(status: 'INACTIVE'),
                              ),
                              StatCard(
                                label: 'Maintenance',
                                value:
                                    _formatNumber(state.stats!.maintenanceCctv),
                                icon: Icons.build,
                                color: AppColors.warning,
                                onTap: () =>
                                    goToCctvList(status: 'MAINTENANCE'),
                              ),
                              StatCard(
                                label: 'Added This Month',
                                value:
                                    _formatNumber(state.stats!.addedThisMonth),
                                icon: Icons.calendar_month,
                                color: AppColors.info,
                                onTap: goToThisMonthAdded,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        RecentUploadsCard(uploads: state.recentUploads),
                      ],
                    ),
                  ),
      ),
    );
  }

  String _formatNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}
