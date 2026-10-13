import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/user_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/user_role_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/user_management_provider.dart';
import '../widgets/edit_access_dialog.dart';

/// User management screen (admin only).
class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userManagementProvider);
    final currentUserId = ref.watch(authProvider.select((s) => s.user?.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
      ),
      // Creating users needs Permission.USER_CREATE (ADMIN only). Hiding the
      // button keeps non-admins from opening a form that the backend would
      // reject with a 403.
      floatingActionButton: ref.watch(isAdminProvider)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/users/add'),
              backgroundColor: AppColors.primarySurface,
              foregroundColor: AppColors.textOnPrimary,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add User'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              hintText: 'Search users...',
              onChanged: (value) {
                ref.read(userManagementProvider.notifier).setSearch(value);
              },
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const ShimmerList()
                // An empty result set is normal (search miss, or a fresh
                // install), so it gets a dedicated state rather than a
                // full-screen error.
                : state.users.isEmpty && state.error == null
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        title: 'No users found',
                        subtitle: 'Try a different search, or add a new user.',
                      )
                : state.error != null
                    ? ErrorView(
                        message: state.error!,
                        onRetry: () => ref.read(userManagementProvider.notifier).load(),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.users.length,
                        itemBuilder: (context, index) {
                          final user = state.users[index];
                          final notifier =
                              ref.read(userManagementProvider.notifier);
                          return _UserTile(
                            user: user,
                            // Admins cannot change their own access; the
                            // server refuses, so the menu doesn't offer it.
                            isSelf: user.id == currentUserId,
                            onToggleStatus: () => _report(
                              context,
                              notifier.toggleUserStatus(user),
                              user.isActive
                                  ? 'Disabled ${user.username}'
                                  : 'Enabled ${user.username}',
                            ),
                            onEditAccess: () async {
                              final change =
                                  await showEditAccessDialog(context, user);
                              if (change == null || !context.mounted) return;
                              await _report(
                                context,
                                notifier.updateAccess(
                                  user,
                                  role: change.role,
                                  region: change.region,
                                  township: change.township,
                                ),
                                'Updated access for ${user.username}',
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Shows the outcome of a user action: success, or the server's reason.
  Future<void> _report(
    BuildContext context,
    Future<String?> action,
    String successMessage,
  ) async {
    final error = await action;
    if (!context.mounted) return;
    AppUtils.showSnackBar(context, error ?? successMessage, isError: error != null);
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;
  final bool isSelf;
  final VoidCallback onToggleStatus;
  final VoidCallback onEditAccess;

  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onToggleStatus,
    required this.onEditAccess,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              user.initial,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    UserRoleBadge(role: user.role),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (user.areaLabel != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 13, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          user.areaLabel!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!user.isActive) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Disabled',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Joined ${AppUtils.formatDate(user.createdAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (!isSelf)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textTertiary),
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'access') onEditAccess();
                if (value == 'toggle') onToggleStatus();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'access',
                  child: Text('Change role & area'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(user.isActive ? 'Disable User' : 'Enable User'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
