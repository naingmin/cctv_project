import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/role_permissions.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/user_service.dart';

/// Form state for creating a user.
class AddUserState {
  final bool isSubmitting;
  final String? error;

  const AddUserState({this.isSubmitting = false, this.error});

  AddUserState copyWith({bool? isSubmitting, String? error}) {
    return AddUserState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

/// Drives the add-user form's `POST /users` call.
///
/// Kept separate from [UserManagementNotifier] because that notifier's `error`
/// renders as a full-screen [ErrorView] in place of the user list — wrong for
/// a submit failure, which should leave the list intact.
class AddUserNotifier extends StateNotifier<AddUserState> {
  final UserService _service;

  AddUserNotifier(this._service) : super(const AddUserState());

  /// Creates the user. Returns the new record on success, or null on failure
  /// with the reason in [AddUserState.error].
  Future<UserModel?> submit({
    required String username,
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? region,
    String? township,
  }) async {
    if (state.isSubmitting) return null;
    state = state.copyWith(isSubmitting: true);
    try {
      final user = await _service.createUser(
        username: username,
        name: name,
        email: email,
        password: password,
        role: role,
        region: region,
        township: township,
      );
      if (mounted) state = state.copyWith(isSubmitting: false);
      return user;
    } on ApiException catch (e) {
      // Covers duplicate username/email (409) and any validation the client
      // did not anticipate (422).
      if (mounted) state = state.copyWith(isSubmitting: false, error: e.message);
      return null;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isSubmitting: false,
          error: 'Could not create the user. Please try again.',
        );
      }
      return null;
    }
  }
}

/// Provider for the add-user form. Auto-disposed, so every visit to the
/// screen starts with a clean form and no stale error.
final addUserProvider =
    StateNotifierProvider.autoDispose<AddUserNotifier, AddUserState>((ref) {
  return AddUserNotifier(ref.watch(userServiceProvider));
});
