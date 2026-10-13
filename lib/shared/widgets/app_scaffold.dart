import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Main app scaffold with role-based bottom navigation.
class AppScaffold extends ConsumerWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final currentLocation = GoRouterState.of(context).matchedLocation;

    final adminTabs = [
      '/dashboard',
      '/cctv',
      '/map',
      '/users',
      '/settings',
    ];

    final userTabs = [
      '/cctv',
      '/map',
      '/settings',
    ];

    final tabs = isAdmin ? adminTabs : userTabs;
    final currentIndex = tabs.indexOf(currentLocation);
    final safeIndex = currentIndex >= 0 ? currentIndex : 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: isAdmin
                  ? [
                      _NavItem(
                        icon: Icons.dashboard_outlined,
                        activeIcon: Icons.dashboard,
                        label: 'Dashboard',
                        isSelected: safeIndex == 0,
                        onTap: () => context.go('/dashboard'),
                      ),
                      _NavItem(
                        icon: Icons.videocam_outlined,
                        activeIcon: Icons.videocam,
                        label: 'CCTV',
                        isSelected: safeIndex == 1,
                        onTap: () => context.go('/cctv'),
                      ),
                      _NavItem(
                        icon: Icons.map_outlined,
                        activeIcon: Icons.map,
                        label: 'Map',
                        isSelected: safeIndex == 2,
                        onTap: () => context.go('/map'),
                      ),
                      _NavItem(
                        icon: Icons.people_outline,
                        activeIcon: Icons.people,
                        label: 'Users',
                        isSelected: safeIndex == 3,
                        onTap: () => context.go('/users'),
                      ),
                      _NavItem(
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings,
                        label: 'Settings',
                        isSelected: safeIndex == 4,
                        onTap: () => context.go('/settings'),
                      ),
                    ]
                  : [
                      _NavItem(
                        icon: Icons.videocam_outlined,
                        activeIcon: Icons.videocam,
                        label: 'CCTV',
                        isSelected: safeIndex == 0,
                        onTap: () => context.go('/cctv'),
                      ),
                      _NavItem(
                        icon: Icons.map_outlined,
                        activeIcon: Icons.map,
                        label: 'Map',
                        isSelected: safeIndex == 1,
                        onTap: () => context.go('/map'),
                      ),
                      _NavItem(
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings,
                        label: 'Settings',
                        isSelected: safeIndex == 2,
                        onTap: () => context.go('/settings'),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.primary : AppColors.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
