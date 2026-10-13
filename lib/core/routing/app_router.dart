import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/role_permissions.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/cctv/screens/cctv_list_screen.dart';
import '../../features/cctv/screens/cctv_detail_screen.dart';
import '../../features/cctv/screens/add_cctv_screen.dart';
import '../../features/cctv/screens/edit_cctv_screen.dart';
import '../../features/cctv/screens/live_stream_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/users/screens/add_user_screen.dart';
import '../../features/users/screens/user_management_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Pure authentication + role guard.
///
/// Returns the location to redirect to, or null to stay put. Extracted from
/// the router so the rules can be unit tested without a live auth stack.
///
/// The role check only stops deep links into screens a role cannot use (the
/// screen would just show server errors); the backend still enforces every
/// permission on its own.
String? authRedirect({
  required bool isInitializing,
  required bool isAuthenticated,
  required UserRole role,
  required String location,
}) {
  // Restoring a stored session is async. Stay put until we know whether the
  // user is signed in, otherwise a valid refresh flashes /login.
  if (isInitializing) return null;

  final atLogin = location == '/login';

  if (!isAuthenticated) {
    // Covers logout, session expiry, and deep links opened while signed out.
    return atLogin ? null : '/login';
  }

  final home = homeRouteForRole(role);
  if (atLogin) return home;
  if (!canOpenRoute(role, location)) return home;
  return null;
}

/// Whether [role] may open the screen at [location].
bool canOpenRoute(UserRole role, String location) {
  if (location == '/dashboard') return RolePermissions.canViewDashboard(role);
  if (location == '/users' || location.startsWith('/users/')) {
    return RolePermissions.canManageUsers(role);
  }
  if (location == '/cctv/add') return RolePermissions.canCreateCctv(role);
  if (location.startsWith('/cctv/') && location.endsWith('/edit')) {
    return RolePermissions.canEditCctv(role);
  }
  return true;
}

/// Application router with authentication guard.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  /// Builds the router with a live authentication guard.
  ///
  /// The caller must call [GoRouter.refresh] whenever [authProvider] changes
  /// (see `main.dart`) so the guard re-evaluates on logout or session expiry
  /// even when no navigation happens.
  static GoRouter create(WidgetRef ref) => GoRouter(
        navigatorKey: _rootNavigatorKey,
        initialLocation: '/login',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          // Read the role straight off the auth state. `isAdminProvider` is a
          // derived provider and ref.read caches it without a dependency edge, so
          // it stays frozen at whatever it was when the router booted.
          return authRedirect(
            isInitializing: auth.isInitializing,
            isAuthenticated: auth.isAuthenticated,
            role: auth.user?.role ?? UserRole.user,
            location: state.matchedLocation,
          );
        },
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginScreen(),
          ),
          ShellRoute(
            navigatorKey: _shellNavigatorKey,
            builder: (context, state, child) => AppScaffold(child: child),
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
              GoRoute(
                path: '/cctv',
                builder: (context, state) => const CctvListScreen(),
              ),
              GoRoute(
                path: '/cctv/add',
                builder: (context, state) => const AddCctvScreen(),
              ),
              GoRoute(
                path: '/cctv/:id',
                builder: (context, state) => CctvDetailScreen(
                  cctvId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/cctv/:id/edit',
                builder: (context, state) => EditCctvScreen(
                  cctvId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/cctv/:id/live',
                builder: (context, state) => LiveStreamScreen(
                  cctvId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/map',
                builder: (context, state) => MapScreen(
                  focusRecordId: state.uri.queryParameters['focus'],
                ),
              ),
              GoRoute(
                path: '/users/add',
                builder: (context, state) => const AddUserScreen(),
              ),
              GoRoute(
                path: '/users',
                builder: (context, state) => const UserManagementScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
        errorBuilder: (context, state) => Scaffold(
          body: Center(
            child: Text('Page not found: ${state.error}'),
          ),
        ),
      );
}
