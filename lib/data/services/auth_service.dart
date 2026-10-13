import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/prefs_token_store.dart';
import '../models/user_model.dart';

/// Authentication service backed by the FastAPI `/auth` endpoints.
class AuthService {
  final ApiClient _api;
  final Ref _ref;

  AuthService(this._api, this._ref);

  /// Longest a logout waits for the server before signing out locally.
  static const _logoutTimeout = Duration(seconds: 5);

  Future<UserModel> login(String username, String password) async {
    final response = await _api.post(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    final data = response['data'] as Map<String, dynamic>;

    final storage = _ref.read(tokenStorageProvider);
    await storage.writeAccessToken(data['access_token'] as String);
    await storage.writeRefreshToken(data['refresh_token'] as String);

    return me();
  }

  /// Fetch the current user profile (`/auth/me`).
  Future<UserModel> me() async {
    final response = await _api.get('/auth/me');
    final data = response['data'] as Map<String, dynamic>;
    return UserModel.fromJson(data);
  }

  /// Revokes the refresh token on the server, then clears local tokens.
  ///
  /// The server call is best-effort: being offline or having an expired
  /// access token must never prevent signing out on this device.
  Future<void> logout() async {
    final storage = _ref.read(tokenStorageProvider);
    try {
      final refreshToken = await storage.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        ).timeout(_logoutTimeout);
      }
    } catch (_) {
      // Ignore: the local sign-out below always happens.
    }
    await storage.clear();
  }

  /// Whether a stored access token exists.
  Future<bool> hasSession() async {
    final token = await _ref.read(tokenStorageProvider).readAccessToken();
    return token != null && token.isNotEmpty;
  }
}
