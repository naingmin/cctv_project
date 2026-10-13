import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'image_mime.dart';

/// An image the user picked, held in memory as bytes.
///
/// Replaces `dart:io` `File` in the upload path: a browser has no file
/// system, so on web `File(picked.path)` cannot be read. `XFile.readAsBytes`
/// works on Android, iOS, desktop and web alike, and picked images are small
/// (already resized by the picker), so keeping them in memory is cheap.
class PickedImage {
  final String filename;
  final Uint8List bytes;

  const PickedImage({required this.filename, required this.bytes});

  /// Server content type for the pick, based on the filename extension.
  String get contentType => imageContentTypeFor(filename);

  /// Reads [file] once. Throws if the picker or the read fails.
  static Future<PickedImage> fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    // Web blob paths can have no name or extension; the backend accepts
    // any filename, and [imageContentTypeFor] defaults to JPEG.
    final name = file.name.trim();
    return PickedImage(
      filename: name.isEmpty || !name.contains('.') ? 'image.jpg' : name,
      bytes: bytes,
    );
  }
}
