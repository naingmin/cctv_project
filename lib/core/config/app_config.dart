import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration values.
///
/// Resolution order for every setting:
///  1. A runtime override persisted on the device (API base URL only).
///  2. `--dart-define=KEY=value` — compiled into the binary.
///  3. The `.env` file bundled as an asset (debug convenience).
///  4. A hardcoded fallback.
///
/// The runtime override deliberately outranks `--dart-define` for the API
/// address. A compiled-in host is correct only until the machine's DHCP lease
/// changes, and a stale one presents as an unexplained timeout on a device
/// that has working Wi-Fi. Letting the address be corrected on the login
/// screen removes the rebuild-and-reinstall cycle entirely.
///
/// Only non-secret client configuration belongs here — backend secrets (JWT,
/// MinIO, MongoDB) must never reach the app.
class AppConfig {
  AppConfig._();

  // Compile-time overrides. Empty unless supplied via --dart-define.
  static const _defineApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _defineApiPrefix = String.fromEnvironment('API_PREFIX');
  static const _defineMapTileUrl = String.fromEnvironment('MAP_TILE_URL');
  static const _defineMapAttribution =
      String.fromEnvironment('MAP_ATTRIBUTION');

  /// Address chosen on the login screen, or null to use the compiled-in value.
  static String? _runtimeApiBaseUrl;

  /// The device-level override, if one has been set.
  static String? get apiBaseUrlOverride => _runtimeApiBaseUrl;

  /// Sets or clears the override. Null/blank clears it.
  ///
  /// The stored value is normalised on the way in, so a user who types
  /// `192.168.1.5:8000` without a scheme does not end up with a URL Dio
  /// rejects at request time.
  static set apiBaseUrlOverride(String? value) {
    final trimmed = value?.trim() ?? '';
    _runtimeApiBaseUrl = trimmed.isEmpty ? null : normalizeBaseUrl(trimmed);
  }

  /// Normalises user-entered server text into a URL usable as a Dio baseUrl.
  ///
  /// Adds a scheme when absent and strips trailing slashes, which would
  /// otherwise double up against [apiPrefix] (`http://host:8000//api/v1`).
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(value)) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// The loaded `.env` map, or empty when no file was loaded.
  ///
  /// `dotenv.env` throws `NotInitializedError` until `load()` succeeds, so it
  /// must never be touched unguarded — a release build with no bundled `.env`
  /// would otherwise throw from inside a getter at the first API call, long
  /// after the failed load was swallowed in `main`.
  static Map<String, String> get _env =>
      dotenv.isInitialized ? dotenv.env : const <String, String>{};

  /// Single resolution point: compile-time value, else `.env`, else default.
  static String _setting(String fromDefine, String key, String fallback) =>
      fromDefine.isNotEmpty ? fromDefine : _env[key] ?? fallback;

  /// Base URL of the FastAPI backend, e.g. `http://169.58.39.152:8000`.
  ///
  /// Note `localhost` on a physical device resolves to the phone itself; use
  /// the machine's LAN IP (or a public host) for real builds. The fallback
  /// targets the deployment VPS.
  static String get apiBaseUrl => _runtimeApiBaseUrl ??
      _setting(_defineApiBaseUrl, 'API_BASE_URL', 'http://192.168.50.252:8000');

  /// API version prefix.
  static String get apiPrefix =>
      _setting(_defineApiPrefix, 'API_PREFIX', '/api/v1');

  /// Full base including version, e.g. `http://host:8000/api/v1`.
  static String get apiV1 => '$apiBaseUrl$apiPrefix';

  /// `host:port` of the API, e.g. `192.168.1.20:8000`.
  ///
  /// Surfaced in the UI so a misconfigured address is visible before login
  /// rather than surfacing later as an unexplained connection error.
  static String get apiEndpoint {
    final uri = Uri.tryParse(apiV1);
    if (uri == null || uri.host.isEmpty) return apiBaseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// Map tile URL template (OpenStreetMap by default).
  static String get mapTileUrl => _setting(
        _defineMapTileUrl,
        'MAP_TILE_URL',
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );

  /// Required map attribution.
  static String get mapAttribution => _setting(
        _defineMapAttribution,
        'MAP_ATTRIBUTION',
        '© OpenStreetMap contributors',
      );
}
