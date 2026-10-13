import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../shared/widgets/user_role_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';

/// Settings screen with account, app info, and data management.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = AppConstants.appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final settingsState = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account
          _buildSectionTitle(context, 'ACCOUNT'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    user?.initial ?? 'U',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'User',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      UserRoleBadge(role: user?.role ?? UserRole.user),
                      if (user?.areaLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Area: ${user!.areaLabel}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Data
          _buildSectionTitle(context, 'DATA'),
          const SizedBox(height: 12),
          _buildSettingTile(
            context,
            icon: Icons.cloud_upload_outlined,
            title: 'Upload Queue',
            subtitle: '${settingsState.pendingUploads} pending, ${settingsState.failedUploads} failed',
            onTap: () {},
          ),
          _buildSettingTile(
            context,
            icon: Icons.delete_outline,
            title: 'Clear Uploaded',
            subtitle: 'Remove completed uploads from queue',
            onTap: () => ref.read(settingsProvider.notifier).clearUploaded(),
          ),
          const SizedBox(height: 24),

          // Application
          _buildSectionTitle(context, 'APPLICATION'),
          const SizedBox(height: 12),
          _buildSettingTile(
            context,
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: _version,
            onTap: null,
          ),
          _buildSettingTile(
            context,
            icon: Icons.security,
            title: 'Security',
            subtitle: 'Authorized personnel only',
            onTap: null,
          ),
          const SizedBox(height: 24),

          // Logout
          Container(
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                // The router guard also enforces this, but navigating
                // explicitly keeps the intent obvious at the call site.
                if (context.mounted) context.go('/login');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: onTap != null
            ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
            : null,
        onTap: onTap,
      ),
    );
  }
}
