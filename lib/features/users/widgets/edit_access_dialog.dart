import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/user_model.dart';
import 'area_fields.dart';

/// Result of [showEditAccessDialog].
class AccessChange {
  final UserRole role;
  final String? region;
  final String? township;

  const AccessChange({required this.role, this.region, this.township});
}

/// Lets an administrator change a user's role and area together.
///
/// Returns null when cancelled. Role and area are edited in one dialog
/// because they are validated together: switching someone to Supervisor
/// without a township would otherwise be refused by the server.
Future<AccessChange?> showEditAccessDialog(
  BuildContext context,
  UserModel user,
) {
  return showDialog<AccessChange>(
    context: context,
    builder: (_) => _EditAccessDialog(user: user),
  );
}

class _EditAccessDialog extends StatefulWidget {
  final UserModel user;

  const _EditAccessDialog({required this.user});

  @override
  State<_EditAccessDialog> createState() => _EditAccessDialogState();
}

class _EditAccessDialogState extends State<_EditAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  late UserRole _role = widget.user.role;
  late final _region = TextEditingController(text: widget.user.region ?? '');
  late final _township =
      TextEditingController(text: widget.user.township ?? '');

  @override
  void dispose() {
    _region.dispose();
    _township.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AccessChange(
        role: _role,
        region: _role.requiresRegion ? _region.text.trim() : null,
        township: _role.requiresTownship ? _township.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Access for ${widget.user.name}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final role in UserRole.values)
                  RadioListTile<UserRole>(
                    value: role,
                    groupValue: _role,
                    onChanged: (value) => setState(() => _role = value!),
                    contentPadding: EdgeInsets.zero,
                    title: Text(role.displayName),
                    subtitle: Text(
                      role.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_role.requiresRegion) ...[
                  const SizedBox(height: 8),
                  AreaFields(
                    regionController: _region,
                    townshipController: _township,
                    requireTownship: _role.requiresTownship,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
