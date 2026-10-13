import 'dart:typed_data';

import 'package:cctv_manager/core/utils/picked_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// `XFile.fromData` keeps `name` on the web but derives `name` from `path`
/// on io platforms, so tests pass both - production picks supply whichever
/// their platform uses.
XFile _pick(Uint8List bytes, {required String filename}) =>
    XFile.fromData(bytes, name: filename, path: filename);

void main() {
  group('PickedImage', () {
    test('reads the bytes and filename off the picker result', () async {
      final image = await PickedImage.fromXFile(
        _pick(Uint8List.fromList([1, 2, 3]), filename: 'photo.png'),
      );

      expect(image.filename, 'photo.png');
      expect(image.bytes, [1, 2, 3]);
      expect(image.contentType, 'image/png');
    });

    test('falls back to image.jpg when the pick has no usable name', () async {
      // Web blob picks can arrive without a name or extension.
      final image = await PickedImage.fromXFile(
        _pick(Uint8List(4), filename: ''),
      );

      expect(image.filename, 'image.jpg');
      expect(image.contentType, 'image/jpeg');
    });

    test('unknown extensions default to JPEG, matching the backend', () async {
      final image = await PickedImage.fromXFile(
        _pick(Uint8List(1), filename: 'shot.heic'),
      );

      expect(image.filename, 'shot.heic');
      expect(image.contentType, 'image/jpeg');
    });
  });
}
