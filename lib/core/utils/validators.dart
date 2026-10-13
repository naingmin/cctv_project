import '../config/app_config.dart';

/// Input validation utilities.
class Validators {
  Validators._();

  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? cctvId(String? value) {
    if (value == null || value.isEmpty) return 'CCTV ID is required';
    final idRegex = RegExp(r'^CCTV-\d{6}$');
    if (!idRegex.hasMatch(value)) return 'Format: CCTV-000001';
    return null;
  }

  static String? latitude(String? value) {
    if (value == null || value.isEmpty) return 'Latitude is required';
    final lat = double.tryParse(value);
    if (lat == null) return 'Enter a valid number';
    if (lat < -90 || lat > 90) return 'Latitude must be between -90 and 90';
    return null;
  }

  static String? longitude(String? value) {
    if (value == null || value.isEmpty) return 'Longitude is required';
    final lng = double.tryParse(value);
    if (lng == null) return 'Enter a valid number';
    if (lng < -180 || lng > 180) return 'Longitude must be between -180 and 180';
    return null;
  }

  /// Mirrors the backend's `UserCreate.username` rule: 3-64 characters,
  /// `[A-Za-z0-9_.-]+` (see `backend/app/schemas/user.py`).
  static String? username(String? value) {
    if (value == null || value.isEmpty) return 'Username is required';
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)) {
      return 'Use letters, numbers, dot, dash or underscore only';
    }
    if (value.length < 3 || value.length > 64) {
      return 'Username must be 3-64 characters';
    }
    return null;
  }

  /// Mirrors `validate_password_strength` in `backend/app/core/security.py`.
  ///
  /// Deliberately stricter than [password] (min 6): that one guards the login
  /// form, while this guards account creation, which the backend holds to the
  /// 8-character / letter / digit rule. The order of the checks matches the
  /// backend so the first message shown is the first one it would return.
  static String? strongPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (value.trim() != value) {
      return 'Password must not start or end with a space';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) {
      return 'Password must contain at least one letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  /// Accepts either a username or an email address.
  ///
  /// The login field is an identifier, not strictly an email: the backend's
  /// `LoginRequest.username` documents "accept either username or email" and
  /// resolves it via `get_by_username_or_email`. Validating it as an email
  /// only blocked username sign-in.
  ///
  /// Trimmed before checking, because `_handleLogin` trims anyway and the
  /// backend's lookup strips too — a stray space should not block a valid
  /// identifier.
  static String? usernameOrEmail(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return 'Username or email is required';
    if (identifier.contains('@')) return email(identifier);
    return username(identifier);
  }

  /// Validates a backend address typed on the login screen.
  ///
  /// A bare `host:port` is accepted and normalised with an `http://` scheme,
  /// so the common case does not require remembering to type one.
  static String? apiBaseUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Server address is required';
    final uri = Uri.tryParse(AppConfig.normalizeBaseUrl(raw));
    if (uri == null || uri.host.isEmpty) {
      return 'Enter a valid address, e.g. 192.168.1.5:8000';
    }
    return null;
  }

  /// Whether [value] addresses the device itself.
  ///
  /// `localhost` is correct on a desktop or emulator run and wrong on a real
  /// phone, where it silently resolves to the phone and the connection is
  /// refused. Worth calling out explicitly, because the failure looks exactly
  /// like being offline.
  static bool isLoopbackHost(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(AppConfig.normalizeBaseUrl(raw));
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  /// Whether [value] is an unencrypted `http://` address (including a bare
  /// `host:port`, which is normalised to http).
  static bool isPlainHttp(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return false;
    return Uri.tryParse(AppConfig.normalizeBaseUrl(raw))?.scheme == 'http';
  }

  static String? minLength(String? value, int min, {String field = 'Field'}) {
    if (value == null || value.length < min) {
      return '$field must be at least $min characters';
    }
    return null;
  }
}
