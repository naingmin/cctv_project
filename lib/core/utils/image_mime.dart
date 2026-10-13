import 'package:path/path.dart' as p;

/// Maps a filename's extension to the MIME type used for the upload.
///
/// The value has to agree with what the presigned URL was signed against: the
/// backend includes the content type in the SigV4 signature, so a mismatch
/// fails the PUT with a signature mismatch rather than a readable error.
///
/// Mirrors the extension map in `backend/app/services/storage_service.py`
/// (`ALLOWED_CONTENT_TYPES`). JPEG is the default because image_picker
/// transcodes to JPEG unless the source is PNG.
String imageContentTypeFor(String filename) {
  switch (p.extension(filename).toLowerCase()) {
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}