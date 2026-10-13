import 'package:cctv_manager/core/routing/app_router.dart';
import 'package:cctv_manager/core/utils/role_permissions.dart';
import 'package:cctv_manager/features/auth/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the router's authentication guard.
///
/// Logout previously navigated to /dashboard and the guard was a no-op
/// stub, so signed-out users stayed on authenticated screens.
void main() {
  group('authRedirect', () {
    test('stays put while the stored session is being restored', () {
      // Otherwise a valid refresh would flash the login screen.
      for (final location in ['/login', '/dashboard', '/settings', '/cctv']) {
        expect(
          authRedirect(
            isInitializing: true,
            isAuthenticated: false,
            role: UserRole.user,
            location: location,
          ),
          isNull,
          reason: 'must not redirect while initializing ($location)',
        );
      }
    });

    test('signed-out user on /login stays there', () {
      expect(
        authRedirect(
          isInitializing: false,
          isAuthenticated: false,
          role: UserRole.user,
          location: '/login',
        ),
        isNull,
      );
    });

    test('signed-out user is bounced from every protected route', () {
      // Covers logout, session expiry and deep links opened while signed out.
      for (final location in [
        '/dashboard',
        '/cctv',
        '/cctv/add',
        '/cctv/abc123',
        '/cctv/abc123/edit',
        '/cctv/abc123/live',
        '/map',
        '/users',
        '/users/add',
        '/settings',
      ]) {
        expect(
          authRedirect(
            isInitializing: false,
            isAuthenticated: false,
            role: UserRole.user,
            location: location,
          ),
          '/login',
          reason: 'must bounce $location to /login',
        );
      }
    });

    test('admin on /login is sent to the dashboard', () {
      expect(
        authRedirect(
          isInitializing: false,
          isAuthenticated: true,
          role: UserRole.admin,
          location: '/login',
        ),
        '/dashboard',
      );
    });

    test('non-admin on /login is sent to the camera list', () {
      expect(
        authRedirect(
          isInitializing: false,
          isAuthenticated: true,
          role: UserRole.user,
          location: '/login',
        ),
        '/cctv',
      );
    });

    test('signed-in user browsing protected routes is left alone', () {
      for (final location in [
        '/dashboard',
        '/cctv',
        '/cctv/abc123',
        '/map',
        '/users',
        '/users/add',
        '/settings',
      ]) {
        expect(
          authRedirect(
            isInitializing: false,
            isAuthenticated: true,
            role: UserRole.admin,
            location: location,
          ),
          isNull,
          reason: 'must not redirect an authenticated user away from $location',
        );
      }
    });
  });

  group('role guard', () {
    String? redirect(UserRole role, String location) => authRedirect(
          isInitializing: false,
          isAuthenticated: true,
          role: role,
          location: location,
        );

    test('admin-only screens bounce everyone else home', () {
      for (final role in [
        UserRole.regionalAdmin,
        UserRole.supervisor,
        UserRole.user,
      ]) {
        for (final location in ['/dashboard', '/users', '/users/add']) {
          expect(redirect(role, location), '/cctv', reason: '$role $location');
        }
      }
    });

    test('only roles that can edit reach the add/edit screens', () {
      for (final location in ['/cctv/add', '/cctv/abc123/edit']) {
        expect(redirect(UserRole.admin, location), isNull);
        expect(redirect(UserRole.regionalAdmin, location), isNull);
        expect(redirect(UserRole.supervisor, location), '/cctv');
        expect(redirect(UserRole.user, location), '/cctv');
      }
    });

    test('every role can browse cameras, the map and settings', () {
      for (final role in UserRole.values) {
        for (final location in [
          '/cctv',
          '/cctv/abc123',
          '/cctv/abc123/live',
          '/map',
          '/settings',
        ]) {
          expect(redirect(role, location), isNull, reason: '$role $location');
        }
      }
    });
  });

  group('homeRouteForRole', () {
    test('maps roles to their landing route', () {
      expect(homeRouteForRole(UserRole.admin), '/dashboard');
      expect(homeRouteForRole(UserRole.regionalAdmin), '/cctv');
      expect(homeRouteForRole(UserRole.supervisor), '/cctv');
      expect(homeRouteForRole(UserRole.user), '/cctv');
    });
  });
}
