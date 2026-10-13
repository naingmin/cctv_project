import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Persists the backend address the user sets on the login screen.
///
/// Uses secure storage rather than preferences for consistency with the token
/// store and to avoid adding a dependency. The value is not a secret — it is
/// an address — but it is app configuration that must survive reinstall-free
/// app restarts, and keeping one storage mechanism avoids a second
/// initialization step in `main`.
class ServerConfigStore {
  const ServerConfigStore();

  static const String _key = 'api_base_url';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Reads the stored address, or null when none is set.
  ///
  /// Never throws: a storage failure must not stop the app from starting, and
  /// falling back to the compiled-in address is always safe.
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value == null || value.trim().isEmpty) return null;
      return AppConfig.normalizeBaseUrl(value);
    } catch (_) {
      return null;
    }
  }

  /// Stores [value], or clears the override when null.
  Future<void> write(String? value) async {
    try {
      final normalized =
          value == null ? null : AppConfig.normalizeBaseUrl(value);
      if (normalized == null || normalized.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: normalized);
      }
    } catch (_) {
      // A failed write only means the address has to be re-entered next
      // launch; it must not break the screen that triggered it.
    }
  }

  /// Removes the stored address, restoring the compiled-in default.
  Future<void> clear() => write(null);
}