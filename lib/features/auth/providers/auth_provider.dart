import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/network/api_client.dart';

/// Authentication state.
class AuthState {
  final bool isAuthenticated;
  final bool isInitializing;
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isInitializing = true,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isInitializing,
    bool? isLoading,
    UserModel? user,
    String? error,
    bool clearUser = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isInitializing: isInitializing ?? this.isInitializing,
      isLoading: isLoading ?? this.isLoading,
      user: clearUser ? null : (user ?? this.user),
      error: error,
    );
  }
}

/// Authentication service provider.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider), ref);
});

/// Authentication state notifier backed by the FastAPI backend.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      if (await _authService.hasSession()) {
        final user = await _authService.me();
        if (!mounted) return;
        state = AuthState(
          isAuthenticated: true,
          isInitializing: false,
          user: user,
        );
        return;
      }
    } catch (_) {
      // Session invalid/expired.
    }
    // A login can complete while this restore is still awaiting storage, so
    // only clear the state if nothing has authenticated in the meantime.
    if (!mounted || state.isAuthenticated) return;
    state = const AuthState(isAuthenticated: false, isInitializing: false);
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.login(username, password);
      if (!mounted) return false;
      state = AuthState(
        isAuthenticated: true,
        isInitializing: false,
        user: user,
      );
      return true;
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        error: 'Login failed. Please try again.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    if (!mounted) return;
    state = const AuthState(isAuthenticated: false, isInitializing: false);
  }

  /// Force a logout (e.g. when the API client detects an expired session).
  void forceLogout() {
    if (!mounted || !state.isAuthenticated) return;
    state = const AuthState(
      isAuthenticated: false,
      isInitializing: false,
      error: 'Your session has expired. Please log in again.',
    );
  }
}

/// Provider for authentication state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  final notifier = AuthNotifier(ref.watch(authServiceProvider));
  // Surface irrecoverable session loss (refresh token rejected) to the UI.
  // The router listens to this provider and redirects to /login.
  api.onSessionExpired = notifier.forceLogout;
  ref.onDispose(() {
    if (api.onSessionExpired == notifier.forceLogout) {
      api.onSessionExpired = null;
    }
  });
  return notifier;
});

/// Convenience provider for current user role.
final userRoleProvider = Provider<UserRole>((ref) {
  return ref.watch(authProvider).user?.role ?? UserRole.user;
});

/// Convenience provider for admin check.
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(userRoleProvider) == UserRole.admin;
});

/// Landing route for an authenticated user, based on role.
///
/// Shared by the login screen and the router guard so both agree on where
/// a signed-in user belongs. Takes the role rather than a `Ref` because
/// callers hold either a `Ref` or a `WidgetRef`.
String homeRouteForRole(UserRole role) =>
    role == UserRole.admin ? '/dashboard' : '/cctv';