import 'package:cctv_manager/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the compile-time configuration layer.
///
/// These run without a bundled `.env`, so they exercise the last two steps of
/// the resolution order: `--dart-define` (absent here) then the hardcoded
/// fallback. That is exactly what a release build with no `--dart-define`
/// would get, so a regression in the fallback logic is caught.
void main() {
  group('AppConfig', () {
    test('apiBaseUrl falls back to the emulator host alias', () {
      // 10.0.2.2 is how the Android emulator reaches the host machine. Plain
      // localhost would resolve to the emulator itself.
      expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('apiPrefix defaults to /api/v1', () {
      expect(AppConfig.apiPrefix, '/api/v1');
    });

    test('apiV1 joins the base and prefix', () {
      expect(AppConfig.apiV1, '${AppConfig.apiBaseUrl}/api/v1');
    });

    test('map settings have OpenStreetMap defaults', () {
      expect(AppConfig.mapTileUrl, contains('openstreetmap.org'));
      expect(AppConfig.mapAttribution, isNotEmpty);
    });

    test('apiEndpoint reduces the base URL to host:port', () {
      expect(AppConfig.apiEndpoint, '10.0.2.2:8000');
    });

    test('apiEndpoint survives a malformed base URL', () {
      // Must not throw: this is rendered on the login screen, where a bad
      // value would otherwise crash the app instead of being displayed.
      addTearDown(() => AppConfig.apiBaseUrlOverride = null);
      for (final bad in ['http://[::1', 'http://', '::::', 'http://exa mple']) {
        AppConfig.apiBaseUrlOverride = bad;
        expect(() => AppConfig.apiEndpoint, returnsNormally, reason: bad);
        expect(AppConfig.apiEndpoint, isNotEmpty, reason: bad);
      }
    });

    test('a runtime override wins and is normalised', () {
      addTearDown(() => AppConfig.apiBaseUrlOverride = null);
      AppConfig.apiBaseUrlOverride = '192.168.1.5:8000/';
      expect(AppConfig.apiBaseUrl, 'http://192.168.1.5:8000');
      expect(AppConfig.apiEndpoint, '192.168.1.5:8000');

      AppConfig.apiBaseUrlOverride = null;
      expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8000');
    });
  });
}