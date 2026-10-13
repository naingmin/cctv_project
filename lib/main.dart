import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/storage/server_config_store.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Entry point.
// ---------------------------------------------------------------------------
Future<void> main() async {
  // Required before any plugin (secure storage, asset bundle) is used.
  WidgetsFlutterBinding.ensureInitialized();

  // Optional debug configuration. A missing or malformed file must not stop
  // the app from starting; AppConfig falls back to --dart-define / defaults.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  // Restore the backend address chosen on the login screen, if any.
  AppConfig.apiBaseUrlOverride = await const ServerConfigStore().read();

  runApp(const ProviderScope(child: CCTVManagerApp()));
}

// ---------------------------------------------------------------------------
// Root widget. Provides MaterialApp (Directionality, MediaQuery, Navigator,
// theme) and the go_router configuration with its authentication guard.
// ---------------------------------------------------------------------------
class CCTVManagerApp extends ConsumerStatefulWidget {
  const CCTVManagerApp({super.key});

  @override
  ConsumerState<CCTVManagerApp> createState() => _CCTVManagerAppState();
}

class _CCTVManagerAppState extends ConsumerState<CCTVManagerApp> {
  // Created once: rebuilding the router would reset navigation history.
  late final GoRouter _router = AppRouter.create(ref);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-run the router's redirect when auth changes (session restored,
    // login, logout, session expiry) so the guard applies without navigation.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated ||
          previous?.isInitializing != next.isInitializing ||
          previous?.user?.role != next.user?.role) {
        _router.refresh();
      }
    });

    return MaterialApp.router(
      title: 'CCTV Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
