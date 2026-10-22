import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/services/cctv_service.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../map/screens/map_location_picker_screen.dart';
import '../providers/cctv_detail_provider.dart';
import '../providers/cctv_list_provider.dart';
import '../../users/widgets/area_fields.dart';

/// Edit CCTV record information and location.
class EditCctvScreen extends ConsumerStatefulWidget {
  final String cctvId;

  const EditCctvScreen({super.key, required this.cctvId});

  @override
  ConsumerState<EditCctvScreen> createState() => _EditCctvScreenState();
}

class _EditCctvScreenState extends ConsumerState<EditCctvScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cctvIdController;
  late final TextEditingController _ipAddressController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _regionController;
  late final TextEditingController _streetController;
  late final TextEditingController _townshipController;
  String? _initializedRecordId;
  String? _status;
  String? _type;
  String? _direction;
  List<String> _tags = [];
  double? _latitude;
  double? _longitude;
  bool _isSaving = false;

  static const _directions = <(String, String)>[
    ('N', 'North (N)'),
    ('NE', 'Northeast (NE)'),
    ('E', 'East (E)'),
    ('SE', 'Southeast (SE)'),
    ('S', 'South (S)'),
    ('SW', 'Southwest (SW)'),
    ('W', 'West (W)'),
    ('NW', 'Northwest (NW)'),
  ];

  @override
  void initState() {
    super.initState();
    _cctvIdController = TextEditingController();
    _ipAddressController = TextEditingController();
    _portController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _descriptionController = TextEditingController();
    _regionController = TextEditingController();
    _streetController = TextEditingController();
    _townshipController = TextEditingController();
  }

  @override
  void dispose() {
    _cctvIdController.dispose();
    _ipAddressController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _descriptionController.dispose();
    _regionController.dispose();
    _streetController.dispose();
    _townshipController.dispose();
    super.dispose();
  }

  void _initializeFromRecord(CctvRecord record) {
    if (_initializedRecordId == record.id) return;
    _initializedRecordId = record.id;
    _cctvIdController.text = record.cctvId;
    _ipAddressController.text = record.ipAddress ?? '';
    _portController.text = (record.port ?? 554).toString();
    _usernameController.text = record.username ?? '';
    _passwordController.text = record.password ?? '';
    _descriptionController.text = record.description ?? '';
    _regionController.text = record.region ?? '';
    _streetController.text = record.street ?? '';
    _townshipController.text = record.township ?? '';
    _status = record.status;
    _type = record.type;
    _direction = record.direction;
    _tags = List<String>.from(record.tags);
    _latitude = record.latitude;
    _longitude = record.longitude;
  }

  Future<void> _chooseLocation() async {
    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (context) => MapLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(cctvDetailProvider(widget.cctvId));

    if (detailState.isLoading) {
      return const Scaffold(body: LoadingView(message: 'Loading...'));
    }

    final record = detailState.record;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit CCTV')),
        body: const Center(child: Text('Record not found')),
      );
    }
    _initializeFromRecord(record);

    return Scaffold(
      appBar: AppBar(title: Text('Edit ${record.cctvId}')),
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
                  labelText: 'CCTV name / ID',
                  hintText: 'CCTV-000001',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 64,
                validator: (value) {
                  final required = Validators.required(value, field: 'CCTV ID');
                  if (required != null) return required;
                  if (value!.trim().length < 3) {
                    return 'CCTV ID must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ipAddressController,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
                keyboardType: TextInputType.url,
                maxLength: 45,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'RTSP Port',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return 'Enter a port between 1 and 65535';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                maxLength: 256,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                maxLength: 1024,
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: cctvTagDescriptions.entries.map((entry) {
                  return FilterChip(
                    label: Text(entry.key),
                    tooltip: entry.value,
                    selected: _tags.contains(entry.key),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _tags.add(entry.key);
                        } else {
                          _tags.remove(entry.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  hintText: 'Type',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'Dome', child: Text('Dome')),
                  DropdownMenuItem(value: 'Bullet', child: Text('Bullet')),
                  DropdownMenuItem(value: 'PTZ', child: Text('PTZ')),
                ],
                onChanged: (value) => setState(() => _type = value),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'LOCATION'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _coordinate('Latitude', _latitude),
                        ),
                        Expanded(
                          child: _coordinate('Longitude', _longitude),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _chooseLocation,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Change Location on Map'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                  labelText: 'Township',
                  prefixIcon: Icon(Icons.location_city),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(
                  labelText: 'Street',
                  prefixIcon: Icon(Icons.route),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.info_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  DropdownMenuItem(
                    value: 'MAINTENANCE',
                    child: Text('Maintenance'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _direction,
                decoration: const InputDecoration(
                  labelText: 'Direction',
                  prefixIcon: Icon(Icons.explore_outlined),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('No direction'),
                  ),
                  ..._directions.map(
                    (item) => DropdownMenuItem(
                      value: item.$1,
                      child: Text(item.$2),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _direction = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 3,
                maxLength: 2000,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                isLoading: _isSaving,
                onPressed: _isSaving ? null : () => _save(record),
                child: const Text('Save Changes'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coordinate(String label, double? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value?.toStringAsFixed(6) ?? 'Not set',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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

  Future<void> _save(CctvRecord record) async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      AppUtils.showSnackBar(context, 'Choose a location on the map',
          isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(cctvServiceProvider).updateCctv(
            widget.cctvId,
            record.copyWith(
              cctvId: _cctvIdController.text.trim().toUpperCase(),
              latitude: _latitude,
              longitude: _longitude,
              description: _descriptionController.text.trim(),
              region: _regionController.text.trim(),
              street: _streetController.text.trim(),
              township: _townshipController.text.trim(),
              direction: _direction,
              ipAddress: _ipAddressController.text.trim(),
              port: int.tryParse(_portController.text.trim()) ?? 554,
              username: _usernameController.text.trim(),
              password: _passwordController.text,
              tags: _tags,
              status: _status ?? record.status,
              type: _type,
              updatedAt: DateTime.now(),
              clearDirection: _direction == null,
            ),
          );
      ref.read(cctvListProvider.notifier).load();
      await ref.read(cctvDetailProvider(widget.cctvId).notifier).load();
      if (mounted) {
        AppUtils.showSnackBar(context, 'Changes saved');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppUtils.showSnackBar(
          context,
          'Failed to save changes: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// Purpose tag field (multi-select dropdown)
