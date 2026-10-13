import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/add_user_provider.dart';
import '../providers/user_management_provider.dart';
import '../widgets/area_fields.dart';

/// Create-user screen.
///
/// Client-side validation mirrors the backend contract (`schemas/user.py` and
/// `core/security.py`) so obvious mistakes are caught before a round trip, but
/// the server stays the authority — a duplicate username/email still comes back
/// as a 409 and lands in the error banner.
class AddUserScreen extends ConsumerStatefulWidget {
  const AddUserScreen({super.key});

  @override
  ConsumerState<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends ConsumerState<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _regionController = TextEditingController();
  final _townshipController = TextEditingController();
  UserRole _role = UserRole.user;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _regionController.dispose();
    _townshipController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final created = await ref.read(addUserProvider.notifier).submit(
          username: _usernameController.text.trim(),
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          // Not trimmed: the backend rejects surrounding whitespace outright,
          // and `strongPassword` says so before the request is made.
          password: _passwordController.text,
          role: _role,
          region: _regionController.text,
          township: _townshipController.text,
        );

    if (!mounted || created == null) return;

    // Refresh before popping so the list is already current when it reappears.
    ref.read(userManagementProvider.notifier).load();
    AppUtils.showSnackBar(context, 'Created ${created.username}');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final formState = ref.watch(addUserProvider);

    // Only admins may create users (Permission.USER_CREATE). The backend would
    // reject anyone else with a 403, but bouncing here gives a clearer answer
    // than a form that submits and fails. Gated on isInitializing so a session
    // being restored does not flash the denial.
    final canManage = RolePermissions.canManageUsers(
      auth.user?.role ?? UserRole.user,
    );
    if (!auth.isInitializing && !canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add User')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to create users.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add User'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(context, 'ACCOUNT DETAILS'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Full name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) =>
                    Validators.required(value, field: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Username',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: Validators.username,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Temporary password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  ),
                ),
                // At least 8 characters with a letter and a digit.
                validator: Validators.strongPassword,
              ),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'ROLE'),
              const SizedBox(height: 4),
              Text(
                'Determines what the account can reach.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final role in UserRole.values) _buildRoleOption(role),
              if (_role.requiresRegion) ...[
                const SizedBox(height: 12),
                _buildSectionTitle(context, 'AREA'),
                const SizedBox(height: 4),
                Text(
                  _role.requiresTownship
                      ? 'This account will only see cameras in this township.'
                      : 'This account will only see cameras in this region.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AreaFields(
                  regionController: _regionController,
                  townshipController: _townshipController,
                  requireTownship: _role.requiresTownship,
                ),
              ],
              const SizedBox(height: 24),

              if (formState.error != null) ...[
                _buildErrorBanner(formState.error!),
                const SizedBox(height: 16),
              ],

              PrimaryButton(
                onPressed: formState.isSubmitting ? null : _submit,
                isLoading: formState.isSubmitting,
                child: const Text('Create User'),
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

  Widget _buildRoleOption(UserRole role) {
    final title = role.displayName;
    final description = role.description;
    final selected = _role == role;
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}