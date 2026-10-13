import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/server_config_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../core/utils/validators.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/primary_button.dart';

/// Login screen with email/password authentication.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  final _serverFormKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _serverExpanded = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  /// Applies a new backend address and rebuilds the HTTP client against it.
  ///
  /// `apiClientProvider` captures the base URL when it constructs `ApiClient`,
  /// so invalidating it is what actually redirects subsequent requests. Every
  /// service `ref.watch`es that provider, so they are rebuilt with it.
  Future<void> _saveServer() async {
    if (!_serverFormKey.currentState!.validate()) return;
    final value = AppConfig.normalizeBaseUrl(_serverController.text);

    AppConfig.apiBaseUrlOverride = value;
    await const ServerConfigStore().write(value);
    ref.invalidate(apiClientProvider);

    if (!mounted) return;
    setState(() => _serverExpanded = false);
    AppUtils.showSnackBar(context, 'Server set to ${AppConfig.apiEndpoint}');
  }

  /// Drops the override and restores the address compiled into the build.
  Future<void> _resetServer() async {
    AppConfig.apiBaseUrlOverride = null;
    await const ServerConfigStore().clear();
    ref.invalidate(apiClientProvider);

    if (!mounted) return;
    setState(() {
      _serverExpanded = false;
      _serverController.clear();
    });
    AppUtils.showSnackBar(context, 'Server reset to ${AppConfig.apiEndpoint}');
  }

  void _toggleServerEditor() {
    setState(() {
      _serverExpanded = !_serverExpanded;
      if (_serverExpanded) {
        _serverController.text = AppConfig.apiBaseUrl;
      } else {
        _serverController.clear();
      }
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (success && mounted) {
      // Same reason as the router guard: read the role off the auth state so a
      // cached derived provider cannot hand back the pre-login value.
      final role = ref.read(authProvider).user?.role ?? UserRole.user;
      context.go(homeRouteForRole(role));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.maxWidth * 0.4;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: size,
                            height: size,
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'CCTV Manager',
                      style: Theme.of(context).textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Security Operations Center',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      // Not emailAddress: that keyboard still allows
                      // autocorrect, which capitalises the first character and
                      // turns "admin" into "Admin". The backend's username
                      // lookup is case-sensitive, so that silently fails.
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Username or email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      // Accepts either identifier; see
                      // Validators.usernameOrEmail.
                      validator: Validators.usernameOrEmail,
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 24),

                    // Error
                    if (authState.error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.danger.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authState.error!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Login Button
                    PrimaryButton(
                      onPressed: authState.isLoading ? null : _handleLogin,
                      isLoading: authState.isLoading,
                      child: const Text('Sign In'),
                    ),
                    const SizedBox(height: 24),

                    // Which backend this build targets, and the only place it
                    // can be corrected without a rebuild. Login is where people
                    // get stranded when the address is wrong, and the address
                    // changes whenever the host machine's DHCP lease does.
                    Form(
                      key: _serverFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: _toggleServerEditor,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Server: ${AppConfig.apiEndpoint}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textTertiary,
                                          fontFamily: 'monospace',
                                        ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _serverExpanded
                                        ? Icons.expand_less
                                        : Icons.edit_outlined,
                                    size: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_serverExpanded) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _serverController,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              enableSuggestions: false,
                              textCapitalization: TextCapitalization.none,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'monospace',
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '192.168.1.5:8000',
                                prefixIcon: const Icon(Icons.dns_outlined),
                                suffixIcon: IconButton(
                                  tooltip: 'Reset to build default',
                                  icon: const Icon(Icons.restart_alt),
                                  onPressed: _resetServer,
                                ),
                              ),
                              validator: Validators.apiBaseUrl,
                            ),
                            // `localhost` is right on a desktop and fatal on a
                            // phone, where it resolves to the phone itself.
                            if (Validators.isLoopbackHost(
                              _serverController.text,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'localhost points at this device, not the '
                                  'server. Use the PC\'s LAN IP.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.warning),
                                ),
                              ),
                            // Release builds block plain http unless the build
                            // explicitly allows it (see android/gradle.properties).
                            if (kReleaseMode &&
                                Validators.isPlainHttp(_serverController.text))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'This address is not encrypted (http). Use an '
                                  'https:// address, or the app may be unable '
                                  'to connect.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.warning),
                                ),
                              ),
                            const SizedBox(height: 8),
                            PrimaryButton(
                              onPressed: _saveServer,
                              child: const Text('Save Server'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Authorized personnel only',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
