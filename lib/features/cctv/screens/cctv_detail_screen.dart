import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/location_card.dart';
import '../../../shared/widgets/image_gallery.dart';
import '../../../shared/widgets/resilient_image.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/cctv_detail_provider.dart';
import '../providers/cctv_list_provider.dart';
import '../providers/image_upload_provider.dart';

/// A choice offered by the "attach image" sheet.
class _ImageOption {
  final String label;
  final IconData icon;
  final String imageType;
  final ImageSource source;

  const _ImageOption({
    required this.label,
    required this.icon,
    required this.imageType,
    required this.source,
  });
}

/// CCTV record detail screen.
class CctvDetailScreen extends ConsumerWidget {
  final String cctvId;

  const CctvDetailScreen({super.key, required this.cctvId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cctvDetailProvider(cctvId));
    final role = ref.watch(userRoleProvider);
    final canUploadImages = RolePermissions.canUploadImages(role);

    if (state.isLoading) {
      return const Scaffold(
          body: LoadingView(message: 'Loading CCTV record...'));
    }

    if (state.error != null || state.record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('CCTV Detail')),
        body: ErrorView(
          message: state.error ?? 'Record not found',
          onRetry: () => ref.read(cctvDetailProvider(cctvId).notifier).load(),
        ),
      );
    }

    final record = state.record!;
    final upload = ref.watch(imageUploadProvider(cctvId));

    return Scaffold(
      appBar: AppBar(
        title: Text(record.cctvId),
        actions: [
          // Lets a record saved without images be repaired later, rather than
          // being stuck empty because its upload failed at creation time.
          if (canUploadImages)
            IconButton(
              tooltip: 'Add image',
              icon: upload.isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              onPressed: upload.isUploading
                  ? null
                  : () => _addImage(context, ref, record),
            ),
          if (RolePermissions.canEditCctv(role))
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/cctv/${record.id}/edit'),
            ),
          if (RolePermissions.canDeleteCctv(role))
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upload failure. The create form's equivalent message was erased
            // by a later state update and the save was reported as a success;
            // this state keeps errors until they are dismissed.
            if (upload.error != null) ...[
              _UploadBanner(
                message: upload.error!,
                onDismiss: () =>
                    ref.read(imageUploadProvider(cctvId).notifier).clearError(),
              ),
              const SizedBox(height: 16),
            ],
            if (upload.isUploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: upload.progress),
              ),
              const SizedBox(height: 16),
            ],

            if (record.tags.isNotEmpty) ...[
              _buildSection(context, 'Purpose', [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: record.tags.map((tag) {
                    final description = cctvTagDescriptions[tag];
                    return Chip(
                      avatar: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        description == null ? tag : '$tag · $description',
                      ),
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      side:
                          BorderSide(color: AppColors.primary.withOpacity(0.3)),
                    );
                  }).toList(),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.cctvId,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (record.region != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          record.region!,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                StatusBadge(status: record.operationalStatus),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/cctv/${record.id}/live'),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch Live'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Location
            LocationCard(
              latitude: record.latitude,
              longitude: record.longitude,
              onTap: () => context.push('/map?focus=${record.id}'),
            ),
            const SizedBox(height: 16),

            // CCTV View Image
            if (record.cctvViewImageUrl != null) ...[
              Text(
                'CCTV View',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1,
                    ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ResilientImage(
                  source: record.cctvViewImageUrl,
                  cctvId: record.id,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Environment Images
            if (record.environmentImages.isNotEmpty) ...[
              ImageGallery(
                imageUrls: record.environmentImages
                    .map((img) => img.signedUrl)
                    .where((url) => url != null && url.isNotEmpty)
                    .cast<String>()
                    .toList(),
                title: 'Environment Views',
                cctvId: record.id,
              ),
              const SizedBox(height: 16),
            ],

            // Details
            _buildSection(context, 'Details', [
              _buildDetailRow(context, 'Region', record.region),
              _buildDetailRow(context, 'Township', record.township),
              _buildDetailRow(context, 'Street', record.street),
              _buildDetailRow(context, 'Direction', record.direction),
              _buildDetailRow(context, 'Status', record.status),
              _buildDetailRow(context, 'Purpose', record.tags.isNotEmpty ? record.tags.join(', ') : null),
            ]),
            const SizedBox(height: 16),

            if (record.ipAddress != null ||
                record.username != null ||
                record.password != null) ...[
              _buildSection(context, 'CCTV Credentials', [
                _buildDetailRow(context, 'IP Address', record.ipAddress),
                _buildDetailRow(context, 'Username', record.username),
                if (record.password != null)
                  _CredentialPasswordRow(password: record.password!),
              ]),
              const SizedBox(height: 16),
            ],

            // Description
            if (record.description != null) ...[
              _buildSection(context, 'Description', [
                Text(
                  record.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // Audit Info
            _buildSection(context, 'Audit Information', [
              _buildDetailRow(
                  context, 'Created by', record.createdBy ?? 'Unknown'),
              _buildDetailRow(context, 'Created',
                  AppUtils.formatDateTime(record.createdAt)),
              _buildDetailRow(
                  context, 'Updated by', record.updatedBy ?? 'Unknown'),
              _buildDetailRow(context, 'Updated',
                  AppUtils.formatDateTime(record.updatedAt)),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppUtils.showConfirmDialog(
      context,
      title: 'Delete CCTV',
      message:
          'Are you sure you want to delete this record? This cannot be undone.',
      confirmText: 'Delete',
      isDanger: true,
    );
    if (confirmed && context.mounted) {
      final error =
          await ref.read(cctvDetailProvider(cctvId).notifier).delete();
      if (error == null) {
        // The list is kept in memory, so drop the record from it too.
        ref.read(cctvListProvider.notifier).removeDeleted(cctvId);
      }
      if (context.mounted) {
        if (error == null) {
          AppUtils.showSnackBar(context, 'CCTV record deleted');
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/cctv');
          }
        } else {
          AppUtils.showSnackBar(context, error, isError: true);
        }
      }
    }
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addImage(
    BuildContext context,
    WidgetRef ref,
    CctvRecord record,
  ) async {
    // A record can hold several environment images but only one view image, so
    // the view slot is only offered while it is empty. Offering it otherwise
    // would silently add a second one that nothing would display.
    final options = <_ImageOption>[
      if (record.cctvViewImageUrl == null) ...[
        // Browsers cannot capture from a camera via the picker.
        if (!kIsWeb)
          const _ImageOption(
            label: 'CCTV view photo - camera',
            icon: Icons.photo_camera_outlined,
            imageType: 'CCTV_VIEW',
            source: ImageSource.camera,
          ),
        const _ImageOption(
          label: 'CCTV view photo - gallery',
          icon: Icons.image_outlined,
          imageType: 'CCTV_VIEW',
          source: ImageSource.gallery,
        ),
      ],
      if (!kIsWeb)
        const _ImageOption(
          label: 'Environment photo - camera',
          icon: Icons.add_a_photo_outlined,
          imageType: 'ENVIRONMENT',
          source: ImageSource.camera,
        ),
      const _ImageOption(
        label: 'Environment photo - gallery',
        icon: Icons.photo_library_outlined,
        imageType: 'ENVIRONMENT',
        source: ImageSource.gallery,
      ),
    ];

    final choice = await showModalBottomSheet<_ImageOption>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ATTACH IMAGE',
              style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (final option in options)
              ListTile(
                leading: Icon(option.icon, color: AppColors.textSecondary),
                title: Text(option.label),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    final success = await ref
        .read(imageUploadProvider(cctvId).notifier)
        .pickAndUpload(choice.source, imageType: choice.imageType);

    if (!context.mounted) return;

    if (success) {
      // The record now has an extra image, so both the detail view and any
      // list thumbnail are stale.
      await ref.read(cctvDetailProvider(cctvId).notifier).load();
      ref.read(cctvListProvider.notifier).load();
      if (context.mounted) {
        AppUtils.showSnackBar(context, 'Image attached');
      }
    }
  }
}

/// Inline banner for an image upload that failed.
class _UploadBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _UploadBanner({required this.message, required this.onDismiss});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withOpacity(0.3))),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 13))),
          IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: AppColors.danger,
              onPressed: onDismiss),
        ],
      ),
    );
  }
}

class _CredentialPasswordRow extends StatefulWidget {
  final String password;

  const _CredentialPasswordRow({required this.password});

  @override
  State<_CredentialPasswordRow> createState() => _CredentialPasswordRowState();
}

class _CredentialPasswordRowState extends State<_CredentialPasswordRow> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('Password', style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        _isVisible ? widget.password : '•' * widget.password.length,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: IconButton(
        tooltip: _isVisible ? 'Hide password' : 'Show password',
        icon: Icon(_isVisible ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _isVisible = !_isVisible),
      ),
    );
  }
}
