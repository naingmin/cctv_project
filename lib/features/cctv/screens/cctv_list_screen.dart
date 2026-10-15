import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/search_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/cctv_list_provider.dart';
import '../widgets/cctv_card.dart';
import '../widgets/filter_sheet.dart';

/// CCTV records list screen with search, filter, and pagination.
class CctvListScreen extends ConsumerStatefulWidget {
  const CctvListScreen({super.key});

  @override
  ConsumerState<CctvListScreen> createState() => _CctvListScreenState();
}

class _CctvListScreenState extends ConsumerState<CctvListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(cctvListProvider.notifier).loadMore();
    }
  }

  void _showFilterSheet() {
    final state = ref.read(cctvListProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterSheet(
        currentStatus: state.statusFilter,
        currentType: state.typeFilter,
        currentRegion: state.regionFilter,
        currentTownship: state.townshipFilter,
        onApply: (status, type, region, township) {
          ref.read(cctvListProvider.notifier).setFilters(
                status: status,
                type: type,
                region: region,
                township: township,
              );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cctvListProvider);
    final canCreate =
        RolePermissions.canCreateCctv(ref.watch(userRoleProvider));

    return Scaffold(
      appBar: AppBar(
        title: const Text('CCTV Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cctv/add'),
              icon: const Icon(Icons.add),
              label: const Text('Add CCTV'),
            )
          : null,
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              hintText: 'Search CCTV ID, type, region, township...',
              onChanged: (value) {
                ref.read(cctvListProvider.notifier).setSearch(value);
              },
            ),
          ),

          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _tagFilterChip(
                  label: 'All',
                  selected: state.selectedTags.isEmpty,
                  onSelected: () =>
                      ref.read(cctvListProvider.notifier).setSelectedTags([]),
                ),
                for (final tag in cctvTagDescriptions.keys)
                  _tagFilterChip(
                    label: tag,
                    selected: state.selectedTags.contains(tag),
                    onSelected: () => ref
                        .read(cctvListProvider.notifier)
                        .toggleSelectedTag(tag),
                  ),
              ],
            ),
          ),

          // Active filters
          if (state.statusFilter != null ||
              state.typeFilter != null ||
              state.regionFilter != null ||
              state.townshipFilter != null ||
              state.selectedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.filter_list,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filters active',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(cctvListProvider.notifier).clearFilters(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: state.isLoading && state.records.isEmpty
                ? const ShimmerList()
                : state.error != null && state.records.isEmpty
                    ? ErrorView(
                        message: state.error!,
                        onRetry: () =>
                            ref.read(cctvListProvider.notifier).load(),
                      )
                    : state.records.isEmpty
                        ? EmptyState(
                            icon: Icons.videocam_off_outlined,
                            title: 'No CCTV records found',
                            subtitle: 'Try changing your search or filter',
                            action: canCreate
                                ? ElevatedButton.icon(
                                    onPressed: () => context.push('/cctv/add'),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add CCTV'),
                                  )
                                : null,
                          )
                        : RefreshIndicator(
                            onRefresh: () =>
                                ref.read(cctvListProvider.notifier).load(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: state.records.length +
                                  (state.hasNext ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= state.records.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: CctvCard(record: state.records[index]),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tagFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.primary.withOpacity(0.18),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
