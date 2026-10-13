import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/role_permissions.dart';

/// Badge displaying the user's role.
class UserRoleBadge extends StatelessWidget {
  final UserRole role;

  const UserRoleBadge({super.key, required this.role});

  /// Accent per role; Viewer stays neutral.
  Color? get _accent {
    switch (role) {
      case UserRole.admin:
        return AppColors.primary;
      case UserRole.regionalAdmin:
        return AppColors.warning;
      case UserRole.supervisor:
        return AppColors.success;
      case UserRole.user:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent?.withOpacity(0.15) ?? AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent?.withOpacity(0.3) ?? AppColors.border,
        ),
      ),
      child: Text(
        role.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent ?? AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
