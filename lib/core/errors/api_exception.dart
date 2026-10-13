import 'package:dio/dio.dart';

/// Normalized API error with a user-safe message.
class ApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  ApiException(this.message, {this.code, this.statusCode});

  factory ApiException.network(DioException e) {
    // Naming the target is the whole point. "No internet connection" was
    // actively misleading: a refused connection to the API host is
    // indistinguishable at this layer from a dead network, and it sent
    // debugging toward the phone's Wi-Fi when the real fault was the
    // configured address (e.g. localhost on a device).
    final host = _target(e.requestOptions.uri);

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('No response from $host. The request timed out.');
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        'Cannot reach $host. Check the server address and that this device '
        'is on the same network as the server.',
      );
    }
    return ApiException('Network error contacting $host.');
  }

  /// `host:port` of the failed request, falling back to the raw URI.
  static String _target(Uri uri) {
    if (uri.host.isEmpty) return uri.toString();
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// [isAuthEndpoint] keeps the server's own message for 401s from login /
  /// refresh / logout, where "session expired" would be wrong (e.g. a typo
  /// in the password).
  factory ApiException.fromResponse(
    Response response, {
    bool isAuthEndpoint = false,
  }) {
    final status = response.statusCode;
    final body = response.data;
    String? code;
    String message;

    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      code = error['code'] as String?;
      message = (error['message'] as String?) ?? 'Request failed.';
    } else {
      message = _defaultMessage(status);
    }

    // Friendlier messages for common cases.
    switch (status) {
      case 401:
        message = code == 'UNAUTHORIZED' && !isAuthEndpoint
            ? 'Your session has expired. Please log in again.'
            : message;
        break;
      case 403:
        message = 'You do not have permission to perform this action.';
        break;
      case 404:
        message = 'The requested resource was not found.';
        break;
      case 429:
        message = 'Too many requests. Please try again later.';
        break;
      case 500:
      case 502:
      case 503:
        message = 'Something went wrong on the server. Please try again.';
        break;
    }

    return ApiException(message, code: code, statusCode: status);
  }

  static String _defaultMessage(int? status) {
    switch (status) {
      case 400:
        return 'Invalid request.';
      case 422:
        return 'Please check the submitted data.';
      default:
        return 'Request failed.';
    }
  }

  @override
  String toString() => message;
}

extension ApiResponseX on dynamic {
  /// Extract the `data` payload from the standard success envelope.
  dynamic get payload {
    if (this is Map && (this as Map)['data'] != null) {
      return (this as Map)['data'];
    }
    return this;
  }
}
