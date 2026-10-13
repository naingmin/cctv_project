import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../data/services/cctv_service.dart';

/// Region -> townships used by existing camera records. Loaded on demand and
/// discarded when no screen needs it, so suggestions are always current.
final areasProvider =
    FutureProvider.autoDispose<Map<String, List<String>>>((ref) {
  return ref.watch(cctvServiceProvider).getAreas();
});

/// Region (and optionally township) inputs with suggestions taken from the
/// names already used on cameras.
///
/// Access is matched on the exact name, so a typo ("Yangoon") would leave the
/// account seeing nothing. Suggestions make the right spelling the easy path,
/// and a hint flags names that no camera uses yet.
class AreaFields extends ConsumerStatefulWidget {
  final TextEditingController regionController;
  final TextEditingController townshipController;
  final bool requireTownship;
  final bool requireRegion;

  const AreaFields({
    super.key,
    required this.regionController,
    required this.townshipController,
    required this.requireTownship,
    this.requireRegion = true,
  });

  @override
  ConsumerState<AreaFields> createState() => _AreaFieldsState();
}

class _AreaFieldsState extends ConsumerState<AreaFields> {
  final _regionFocus = FocusNode();
  final _townshipFocus = FocusNode();
  late String _previousRegion;

  @override
  void initState() {
    super.initState();
    _previousRegion = widget.regionController.text.trim();
    // Rebuild so township suggestions and "unknown name" hints follow input.
    widget.regionController.addListener(_changed);
    widget.townshipController.addListener(_changed);
  }

  void _changed() {
    final currentRegion = widget.regionController.text.trim();
    if (currentRegion != _previousRegion) {
      _previousRegion = currentRegion;
      widget.townshipController.clear();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.regionController.removeListener(_changed);
    widget.townshipController.removeListener(_changed);
    _regionFocus.dispose();
    _townshipFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).valueOrNull ?? const {};
    final region = widget.regionController.text.trim();
    final townships = areas[region] ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SuggestField(
          controller: widget.regionController,
          focusNode: _regionFocus,
          hint: 'Region',
          icon: Icons.map_outlined,
          options: areas.keys.toList(),
          validator: widget.requireRegion
              ? (v) => Validators.required(v, field: 'Region')
              : null,
        ),
        _unknownHint(region, areas.keys, 'region'),
        if (widget.requireTownship) ...[
          const SizedBox(height: 12),
          _SuggestField(
            controller: widget.townshipController,
            focusNode: _townshipFocus,
            hint: 'Township',
            icon: Icons.location_city_outlined,
            options: townships,
            validator: (v) => Validators.required(v, field: 'Township'),
          ),
          _unknownHint(
            widget.townshipController.text.trim(),
            townships,
            'township in $region',
          ),
        ],
      ],
    );
  }

  /// Warns (without blocking) when the name matches no existing camera.
  /// New areas are legitimate, so this is a hint, not a validation error.
  Widget _unknownHint(String value, Iterable<String> known, String what) {
    if (value.isEmpty || known.isEmpty || known.contains(value)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'No camera uses this $what yet. Check the spelling: it must match '
        'exactly, or this account will see no cameras.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.warning),
      ),
    );
  }
}

class _SuggestField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final List<String> options;
  final FormFieldValidator<String>? validator;

  const _SuggestField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    required this.options,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return options.where(
          (o) => query.isEmpty || o.toLowerCase().contains(query),
        );
      },
      fieldViewBuilder: (context, textController, node, onSubmit) {
        return TextFormField(
          controller: textController,
          focusNode: node,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon)),
          validator: validator,
          onFieldSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, matches) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in matches)
                    ListTile(
                      dense: true,
                      title: Text(option),
                      onTap: () => onSelected(option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
