import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores picked images in the app's documents directory so they remain
/// available after the temporary image_picker file is cleaned up or the app
/// is restarted.
class LocalImageStore {
  LocalImageStore._();

  /// Copy [file] into persistent app storage and return its absolute path.
  ///
  /// Returns null if the file could not be persisted.
  static Future<String?> save(
    File file, {
    required String recordId,
    required String kind,
  }) async {
    try {
      if (!await file.exists()) return null;

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'cctv_images', recordId));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
      final destination = p.join(
        dir.path,
        '$kind-${DateTime.now().microsecondsSinceEpoch}$ext',
      );

      final saved = await file.copy(destination);
      return saved.path;
    } catch (_) {
      return null;
    }
  }

  /// Whether [reference] points to a remote (network) resource.
  static bool isRemote(String? reference) {
    if (reference == null || reference.isEmpty) return false;
    return reference.startsWith('http://') || reference.startsWith('https://');
  }
}
