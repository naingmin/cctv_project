import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Access/refresh token storage backed by FlutterSecureStorage (Android
/// Keystore / iOS Keychain). No initialization step is needed.
class _TokenStorage {
  final FlutterSecureStorage _secureStorage;

  _TokenStorage() : _secureStorage = const FlutterSecureStorage();

  /// The JWT access token.
  Future<String?> readAccessToken() async {
    return await _secureStorage.read(key: 'access_token');
  }

  /// Saves the JWT access token.
  Future writeAccessToken(String token) async {
    await _secureStorage.write(key: 'access_token', value: token);
  }

  /// The refresh token.
  Future<String?> readRefreshToken() async {
    return await _secureStorage.read(key: 'refresh_token');
  }

  /// Saves the refresh token.
  Future writeRefreshToken(String token) async {
    await _secureStorage.write(key: 'refresh_token', value: token);
  }

  /// Clears both tokens.
  Future<void> clear() async {
    await _secureStorage.delete(key: 'access_token');
    await _secureStorage.delete(key: 'refresh_token');
  }
}

/// Riverpod provider for the token storage.
final tokenStorageProvider = Provider<_TokenStorage>((ref) {
  return _TokenStorage();
});