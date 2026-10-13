import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../map/screens/map_location_picker_screen.dart';
import '../providers/cctv_form_provider.dart';
import '../providers/cctv_list_provider.dart';
import '../../users/widgets/area_fields.dart';

/// Add CCTV screen with form, GPS capture, and image upload.
class AddCctvScreen extends ConsumerStatefulWidget {
  const AddCctvScreen({super.key});

  @override
  ConsumerState<AddCctvScreen> createState() => _AddCctvScreenState();
}

class _AddCctvScreenState extends ConsumerState<AddCctvScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cctvIdController = TextEditingController();
  final _ipAddressController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _regionController = TextEditingController();
  final _streetController = TextEditingController();
  final _townshipController = TextEditingController();
  String? _status = 'ACTIVE';
  String? _direction;

  @override
  void initState() {
    super.initState();
    ref.read(cctvFormProvider.notifier).reset();
  }

  @override
  void dispose() {
    _cctvIdController.dispose();
    _ipAddressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _descriptionController.dispose();
    _regionController.dispose();
    _streetController.dispose();
    _townshipController.dispose();
    super.dispose();
  }

  Future<void> _chooseLocation() async {
    final formState = ref.read(cctvFormProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.primary),
              title: const Text('Use Current GPS Location'),
              subtitle: const Text('Get latitude and longitude automatically'),
              onTap: () => Navigator.pop(context, 'gps'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined, color: AppColors.primary),
              title: const Text('Drop Pin on Map'),
              subtitle: const Text('Choose the location manually on a map'),
              onTap: () => Navigator.pop(context, 'map'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'gps') {
      await ref.read(cctvFormProvider.notifier).captureLocation();
    } else if (choice == 'map') {
      await _pickOnMap(formState.latitude, formState.longitude);
    }
  }

  Future<void> _pickOnMap(double? lat, double? lng) async {
    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (context) => MapLocationPickerScreen(
          initialLatitude: lat,
          initialLongitude: lng,
        ),
      ),
    );

    if (result != null) {
      ref.read(cctvFormProvider.notifier).setManualLocation(
            result.latitude,
            result.longitude,
          );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(cctvFormProvider.notifier);
    notifier.updateField('cctvId', _cctvIdController.text.trim());
    notifier.updateField('ipAddress', _ipAddressController.text.trim());
    notifier.updateField('username', _usernameController.text.trim());
    notifier.updateField('password', _passwordController.text);
    notifier.updateField('description', _descriptionController.text.trim());
    notifier.updateField('region', _regionController.text.trim());
    notifier.updateField('street', _streetController.text.trim());
    notifier.updateField('township', _townshipController.text.trim());
    notifier.updateField('direction', _direction);
    notifier.updateField('status', _status ?? 'ACTIVE');
    // Tags are already managed by the FilterChip onSelected callbacks,
    // which update the form state directly. No additional call needed.

    final record = await notifier.submit();

    if (record != null && mounted) {
      ref.read(cctvListProvider.notifier).load();
      // A non-null record can still be missing images. `submit` reports that
      // through the form's error state, so read it back rather than always
      // claiming success.
      final partialFailure = ref.read(cctvFormProvider).error;
      AppUtils.showSnackBar(
        context,
        partialFailure ?? 'CCTV record saved successfully',
        isError: partialFailure != null,
      );
      context.pushReplacement('/cctv/${record.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(cctvFormProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add CCTV'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(context, 'CCTV INFORMATION'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cctvIdController,
                decoration: const InputDecoration(
                  hintText: 'CCTV ID (e.g., CCTV-000001)',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
                validator: Validators.cctvId,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ipAddressController,
                decoration: const InputDecoration(
                  hintText: 'IP Address (e.g., 192.168.1.10)',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  hintText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  hintText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              Text(
                'Purpose',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              // Selected tags display (pills that wrap)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: cctvTagDescriptions.entries.map((entry) {
                  final selected = formState.tags.contains(entry.key);
                  return FilterChip(
                    label: Text(entry.key),
                    tooltip: entry.value,
                    selected: selected,
                    onSelected: (value) {
                      final tags = [...formState.tags];
                      if (value) {
                        tags.add(entry.key);
                      } else {
                        tags.remove(entry.key);
                      }
                      ref
                          .read(cctvFormProvider.notifier)
                          .updateField('tags', tags);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Location
              _buildSectionTitle(context, 'LOCATION'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    if (formState.latitude != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Latitude',
                                  style: Theme.of(context).textTheme.bodySmall),
                              Text(
                                formState.latitude!.toStringAsFixed(6),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Longitude',
                                  style: Theme.of(context).textTheme.bodySmall),
                              Text(
                                formState.longitude!.toStringAsFixed(6),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (formState.gpsAccuracy != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Accuracy: ±${formState.gpsAccuracy!.toStringAsFixed(0)}m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    SecondaryButton(
                      onPressed: formState.isLoading ? null : _chooseLocation,
                      isLoading: formState.isLoading,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_location_alt_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(formState.latitude != null
                              ? 'Change Location'
                              : 'Set Location'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // CCTV View Image
              _buildSectionTitle(context, 'CCTV VIEW'),
              const SizedBox(height: 12),
              if (formState.cctvViewImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    formState.cctvViewImage!.bytes,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  // Browsers cannot capture from a camera via the picker.
                  if (!kIsWeb) ...[
                    Expanded(
                      child: SecondaryButton(
                        onPressed: () => ref
                            .read(cctvFormProvider.notifier)
                            .pickCctvViewImage(ImageSource.camera),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, size: 18),
                            SizedBox(width: 8),
                            Text('Take Photo'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SecondaryButton(
                      onPressed: () => ref
                          .read(cctvFormProvider.notifier)
                          .pickCctvViewImage(ImageSource.gallery),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library, size: 18),
                          SizedBox(width: 8),
                          Text('Select Photo'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Environment Images
              _buildSectionTitle(context, 'ENVIRONMENT VIEW'),
              const SizedBox(height: 12),
              if (formState.environmentImages.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: formState.environmentImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              formState.environmentImages[index].bytes,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => ref
                                  .read(cctvFormProvider.notifier)
                                  .removeEnvironmentImage(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SecondaryButton(
                onPressed: () =>
                    ref.read(cctvFormProvider.notifier).pickEnvironmentImage(
                          // Browsers cannot capture from a camera via the picker.
                          kIsWeb ? ImageSource.gallery : ImageSource.camera,
                        ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 18),
                    SizedBox(width: 8),
                    Text('Add Environment Photo'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Additional Information
              _buildSectionTitle(context, 'ADDITIONAL INFORMATION'),
              const SizedBox(height: 12),
              AreaFields(
                regionController: _regionController,
                townshipController: _townshipController,
                requireRegion: false,
                requireTownship: false,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _townshipController,
                decoration: const InputDecoration(
                  hintText: 'Township',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(
                  hintText: 'Street',
                  prefixIcon: Icon(Icons.route),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  hintText: 'Status',
                  prefixIcon: Icon(Icons.info_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  DropdownMenuItem(
                      value: 'MAINTENANCE', child: Text('Maintenance')),
                ],
                onChanged: (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 12),
              // Direction selector
              _buildSectionTitle(context, 'DIRECTION'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _direction,
                decoration: const InputDecoration(
                  hintText: 'Direction',
                  prefixIcon: Icon(Icons.lock),
                ),
                items: const [
                  DropdownMenuItem(value: 'N', child: Text('North (N)')),
                  DropdownMenuItem(value: 'NE', child: Text('Northeast (NE)')),
                  DropdownMenuItem(value: 'E', child: Text('East (E)')),
                  DropdownMenuItem(value: 'SE', child: Text('Southeast (SE)')),
                  DropdownMenuItem(value: 'S', child: Text('South (S)')),
                  DropdownMenuItem(value: 'SW', child: Text('Southwest (SW)')),
                  DropdownMenuItem(value: 'W', child: Text('West (W)')),
                  DropdownMenuItem(value: 'NW', child: Text('Northwest (NW)')),
                ],
                onChanged: (value) => setState(() => _direction = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText: 'Description',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 3,
                maxLength: 2000,
              ),
              const SizedBox(height: 24),

              // Error
              if (formState.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formState.error!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Upload Progress
              if (formState.isUploading) ...[
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: formState.uploadProgress,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formState.currentStatusMessage ?? 'Uploading...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Submit
              PrimaryButton(
                onPressed: formState.isUploading ? null : _submit,
                isLoading: formState.isUploading,
                child: const Text('Upload CCTV'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
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
}
