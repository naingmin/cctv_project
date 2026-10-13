import 'dart:convert';
import 'dart:io';

import 'package:cctv_manager/core/config/app_config.dart';
import 'package:cctv_manager/core/errors/api_exception.dart';
import 'package:cctv_manager/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for the backend's auth behaviour.
class _FakeBackend {
  late HttpServer server;
  String validAccess = 'access-2';
  int refreshCalls = 0;
  int refreshStatus = 200;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    AppConfig.apiBaseUrlOverride = 'http://127.0.0.1:${server.port}';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType.json;
    final path = req.uri.path;

    if (path == '/api/v1/auth/refresh') {
      refreshCalls++;
      // Slow enough that concurrent callers overlap.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      res.statusCode = refreshStatus;
      res.write(jsonEncode(refreshStatus == 200
          ? {
              'success': true,
              'data': {
                'access_token': validAccess,
                'refresh_token': 'refresh-$refreshCalls',
              },
            }
          : {
              'success': false,
              'error': {'code': 'UNAUTHORIZED', 'message': 'nope'},
            }));
    } else if (path == '/api/v1/auth/login') {
      res.statusCode = 401;
      res.write(jsonEncode({
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'Invalid username or password.',
        },
      }));
    } else {
      final ok = req.headers.value('authorization') == 'Bearer $validAccess';
      res.statusCode = ok ? 200 : 401;
      res.write(jsonEncode(ok
          ? {'success': true, 'data': 'ok'}
          : {
              'success': false,
              'error': {'code': 'UNAUTHORIZED', 'message': 'expired'},
            }));
    }
    await res.close();
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;
  late ProviderContainer container;
  late ApiClient api;
  late int expiredCalls;

  setUp(() async {
    // The test binding stubs HttpClient to answer 400 to everything; these
    // tests talk to a real local server instead.
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'access-1', // expired
      'refresh_token': 'refresh-0',
    });
    backend = _FakeBackend();
    await backend.start();
    container = ProviderContainer();
    api = container.read(apiClientProvider);
    expiredCalls = 0;
    api.onSessionExpired = () => expiredCalls++;
  });

  tearDown(() async {
    container.dispose();
    await backend.stop();
    AppConfig.apiBaseUrlOverride = null;
  });

  Future<String?> stored(String key) => const FlutterSecureStorage().read(key: key);

  test('concurrent 401s share a single refresh and all succeed', () async {
    final results = await Future.wait(
      List.generate(5, (_) => api.get('/cctvs')),
    );

    expect(results.map((r) => r['data']), everyElement('ok'));
    expect(backend.refreshCalls, 1);
    expect(expiredCalls, 0);
    expect(await stored('access_token'), 'access-2');
    expect(await stored('refresh_token'), 'refresh-1');
  });

  test('server error during refresh keeps the session', () async {
    backend.refreshStatus = 500;

    await expectLater(api.get('/cctvs'), throwsA(isA<ApiException>()));

    expect(expiredCalls, 0);
    expect(await stored('refresh_token'), 'refresh-0');
  });

  test('rejected refresh token ends the session', () async {
    backend.refreshStatus = 401;

    await expectLater(api.get('/cctvs'), throwsA(isA<ApiException>()));

    expect(expiredCalls, greaterThan(0));
    expect(await stored('access_token'), isNull);
    expect(await stored('refresh_token'), isNull);
  });

  test('wrong password does not refresh or report an expired session', () async {
    await expectLater(
      api.post('/auth/login', data: {'username': 'a', 'password': 'b'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Invalid username or password.',
        ),
      ),
    );

    expect(backend.refreshCalls, 0);
    expect(expiredCalls, 0);
    expect(await stored('refresh_token'), 'refresh-0');
  });
}
