import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../errors/api_exception.dart';
import '../storage/prefs_token_store.dart';

/// Callback invoked when authentication is irrecoverably lost.
typedef SessionExpiredCallback = void Function();

/// Outcome of a refresh attempt.
enum RefreshOutcome {
  /// New tokens were stored; the request can be retried.
  refreshed,

  /// The server rejected the refresh token: the session is over.
  rejected,

  /// The server could not be reached or failed (timeout, 5xx, 429). The
  /// session may still be valid, so tokens are kept.
  unavailable,
}

/// Endpoints that must never trigger a refresh: a 401 from them means bad
/// credentials or a bad refresh token, not an expired access token.
const _noRefreshPaths = {'/auth/login', '/auth/refresh', '/auth/logout'};

/// Dio HTTP client for the FastAPI backend.
class ApiClient {
  final Dio _dio;
  final Ref _ref;

  SessionExpiredCallback? onSessionExpired;

  /// The refresh currently in flight, shared by every caller and every
  /// [ApiClient] instance. The backend rotates refresh tokens, so two
  /// parallel refreshes with the same token would make one of them fail and
  /// wipe the tokens the other one just saved.
  static Future<RefreshOutcome>? _inflightRefresh;

  ApiClient(this._ref)
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiV1,
            connectTimeout: AppConstants.connectionTimeout,
            receiveTimeout: AppConstants.receiveTimeout,
            contentType: 'application/json',
            validateStatus: (_) => true,
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _ref.read(tokenStorageProvider).readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          handler.next(options);
        },
      ),
    );
  }

  /// Perform a request and normalize the result.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
    bool retryOnUnauthorized = true,
  }) async {
    late Response response;
    try {
      response = await _dio.request(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (e) {
      throw ApiException.network(e);
    }

    final isAuthEndpoint = _noRefreshPaths.contains(path);

    // Handle 401 with a single refresh-and-retry.
    if (response.statusCode == 401 && retryOnUnauthorized && !isAuthEndpoint) {
      final sentHeader = response.requestOptions.headers['Authorization'];
      switch (await _refreshAfter(sentHeader is String ? sentHeader : null)) {
        case RefreshOutcome.refreshed:
          return request(
            path,
            method: method,
            data: data,
            query: query,
            retryOnUnauthorized: false,
          );
        case RefreshOutcome.unavailable:
          // Keep the session; the user can retry once the server is back.
          throw ApiException(
            'Could not renew your session because the server is unavailable. '
            'Please try again.',
            statusCode: response.statusCode,
          );
        case RefreshOutcome.rejected:
          onSessionExpired?.call();
          throw ApiException.fromResponse(response);
      }
    }

    if (response.statusCode! >= 200 && response.statusCode! < 300) {
      return response.data;
    }
    throw ApiException.fromResponse(response, isAuthEndpoint: isAuthEndpoint);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      request(path, method: 'GET', query: query);

  Future<dynamic> post(String path, {Object? data}) =>
      request(path, method: 'POST', data: data);

  Future<dynamic> put(String path, {Object? data}) =>
      request(path, method: 'PUT', data: data);

  Future<dynamic> delete(String path, {Object? data}) =>
      request(path, method: 'DELETE', data: data);

  Dio get raw => _dio;

  /// Ensures a fresh access token after a 401 on a request that was sent
  /// with [sentAuthHeader].
  Future<RefreshOutcome> _refreshAfter(String? sentAuthHeader) async {
    // Join a refresh that is already running.
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;

    // A refresh may have finished between this request being sent and its
    // 401 arriving. If the stored token has changed, just retry with it.
    final current = await _ref.read(tokenStorageProvider).readAccessToken();
    if (current != null &&
        current.isNotEmpty &&
        sentAuthHeader != 'Bearer $current') {
      return RefreshOutcome.refreshed;
    }

    // Re-check after the await above: another caller may have started one.
    final started = _inflightRefresh ??= _refresh();
    try {
      return await started;
    } finally {
      if (identical(_inflightRefresh, started)) _inflightRefresh = null;
    }
  }

  Future<RefreshOutcome> _refresh() async {
    final storage = _ref.read(tokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await storage.clear();
      return RefreshOutcome.rejected;
    }

    final Response response;
    try {
      response = await Dio(
        BaseOptions(
          baseUrl: AppConfig.apiV1,
          connectTimeout: AppConstants.connectionTimeout,
          receiveTimeout: AppConstants.receiveTimeout,
          contentType: 'application/json',
          validateStatus: (_) => true,
        ),
      ).post('/auth/refresh', data: {'refresh_token': refreshToken});
    } on DioException {
      return RefreshOutcome.unavailable;
    }

    final status = response.statusCode ?? 0;
    final body = response.data;
    if (status == 200 && body is Map && body['success'] == true) {
      final data = body['data'];
      if (data is Map &&
          data['access_token'] is String &&
          data['refresh_token'] is String) {
        await storage.writeAccessToken(data['access_token'] as String);
        await storage.writeRefreshToken(data['refresh_token'] as String);
        return RefreshOutcome.refreshed;
      }
      return RefreshOutcome.unavailable;
    }

    // Only an explicit rejection ends the session. Rate limiting, server
    // errors and unexpected responses keep the tokens for a later retry.
    if (status == 400 || status == 401 || status == 403 || status == 422) {
      await storage.clear();
      return RefreshOutcome.rejected;
    }
    return RefreshOutcome.unavailable;
  }
}

/// Provider for the API client.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref);
});
