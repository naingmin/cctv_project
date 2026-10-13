import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/user_service.dart';

/// User management state.
class UserManagementState {
  final bool isLoading;
  final List<UserModel> users;
  final String? error;
  final String search;
  final int page;
  final bool hasNext;

  const UserManagementState({
    this.isLoading = false,
    this.users = const [],
    this.error,
    this.search = '',
    this.page = 1,
    this.hasNext = false,
  });

  UserManagementState copyWith({
    bool? isLoading,
    List<UserModel>? users,
    String? error,
    String? search,
    int? page,
    bool? hasNext,
  }) {
    return UserManagementState(
      isLoading: isLoading ?? this.isLoading,
      users: users ?? this.users,
      error: error,
      search: search ?? this.search,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
    );
  }
}

/// User management notifier (API-driven).
///
/// Actions return null on success or a user-facing error message, so the
/// screen can tell the admin why something was refused (e.g. "Cannot disable
/// the last active admin") instead of the change silently snapping back.
class UserManagementNotifier extends StateNotifier<UserManagementState> {
  final UserService _service;
  int _generation = 0;

  UserManagementNotifier(this._service) : super(const UserManagementState()) {
    load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _service.getUsers(
        page: 1,
        search: state.search.isNotEmpty ? state.search : null,
      );
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        users: response.items,
        page: response.page,
        hasNext: response.hasNext,
        error: null,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        error: e is ApiException ? e.message : 'Failed to load users.',
      );
    }
  }

  Future<String?> toggleUserStatus(UserModel user) =>
      _apply(user, () => _service.setUserStatus(user.id, !user.isActive));

  Future<String?> updateAccess(
    UserModel user, {
    required UserRole role,
    String? region,
    String? township,
  }) =>
      _apply(
        user,
        () => _service.updateAccess(
          user.id,
          role: role,
          region: region,
          township: township,
        ),
      );

  /// Runs a change and replaces the user with the server's version of it.
  Future<String?> _apply(
    UserModel user,
    Future<UserModel> Function() change,
  ) async {
    try {
      final updated = await change();
      if (mounted) {
        state = state.copyWith(
          users: [for (final u in state.users) u.id == user.id ? updated : u],
        );
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update ${user.username}. Please try again.';
    }
  }

  void setSearch(String search) {
    if (search == state.search) return;
    state = state.copyWith(search: search);
    load();
  }
}

/// Provider for user management.
final userManagementProvider =
    StateNotifierProvider<UserManagementNotifier, UserManagementState>((ref) {
  final service = ref.watch(userServiceProvider);
  return UserManagementNotifier(service);
});
