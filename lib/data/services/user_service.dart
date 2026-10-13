import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/role_permissions.dart';
import '../models/paginated_response.dart';
import '../models/user_model.dart';

/// User management service backed by the FastAPI `/users` endpoints.
class UserService {
  final ApiClient _api;

  UserService(this._api);

  Future<PaginatedResponse<UserModel>> getUsers({
    int page = 1,
    int limit = AppConstants.defaultPageSize,
    String? search,
    String? role,
    bool? isActive,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (role != null && role.isNotEmpty) query['role'] = role;
    if (isActive != null) query['is_active'] = isActive;

    final response = await _api.get('/users', query: query);
    final data = response['data'] as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = data['pagination'] as Map<String, dynamic>;
    return PaginatedResponse<UserModel>(
      items: items,
      page: pagination['page'] as int,
      limit: pagination['limit'] as int,
      total: pagination['total'] as int,
      hasNext: pagination['has_next'] as bool,
    );
  }

  Future<UserModel> createUser({
    required String username,
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? region,
    String? township,
  }) async {
    final response = await _api.post('/users', data: {
      'username': username,
      'full_name': name,
      'email': email,
      'password': password,
      'role': roleToString(role),
      if (role.requiresRegion) 'region': _blankToNull(region),
      if (role.requiresTownship) 'township': _blankToNull(township),
    });
    return UserModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<UserModel> updateUser(
    String userId, {
    String? name,
    UserRole? role,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['full_name'] = name;
    if (role != null) data['role'] = roleToString(role);
    if (isActive != null) data['is_active'] = isActive;
    final response = await _api.put('/users/$userId', data: data);
    return UserModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Sets role and area together, so the backend validates them as one
  /// change. Roles without an area send explicit nulls to clear it.
  Future<UserModel> updateAccess(
    String userId, {
    required UserRole role,
    String? region,
    String? township,
  }) async {
    final response = await _api.put('/users/$userId', data: {
      'role': roleToString(role),
      'region': role.requiresRegion ? _blankToNull(region) : null,
      'township': role.requiresTownship ? _blankToNull(township) : null,
    });
    return UserModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<UserModel> setUserStatus(String userId, bool enabled) =>
      updateUser(userId, isActive: enabled);

  Future<void> deleteUser(String userId) async {
    await _api.delete('/users/$userId');
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

final userServiceProvider = Provider<UserService>((ref) {
  return UserService(ref.watch(apiClientProvider));
});
