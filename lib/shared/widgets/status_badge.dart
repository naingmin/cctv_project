import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Status badge for CCTV records and users.
class StatusBadge extends StatelessWidget {
  final String status;
  final bool isCompact;

  const StatusBadge({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _getStatusInfo();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 10,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(isCompact ? 4 : 8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isCompact ? 10 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isCompact ? 10 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _getStatusInfo() {
    switch (status.toLowerCase()) {
      case 'operational':
      case 'active':
        return (AppColors.success, 'Operational', Icons.check_circle_outline);
      case 'inactive':
      case 'disabled':
        return (AppColors.danger, 'Inactive', Icons.cancel_outlined);
      case 'maintenance':
        return (AppColors.warning, 'Maintenance', Icons.build_outlined);
      case 'pending':
        return (AppColors.warning, 'Pending', Icons.schedule);
      case 'failed':
        return (AppColors.danger, 'Failed', Icons.error_outline);
      case 'uploaded':
        return (AppColors.success, 'Uploaded', Icons.cloud_done_outlined);
      case 'uploading':
        return (AppColors.info, 'Uploading', Icons.cloud_upload_outlined);
      default:
        return (AppColors.textSecondary, status, Icons.help_outline);
    }
  }
}
