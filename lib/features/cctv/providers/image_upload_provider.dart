import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/utils/picked_image.dart';
import '../../../data/services/cctv_service.dart';

/// Progress of attaching an image to an already-saved record.
class ImageUploadState {
  final bool isUploading;
  final double progress;
  final String? error;

  const ImageUploadState({
    this.isUploading = false,
    this.progress = 0,
    this.error,
  });

  /// `error` is sticky unless explicitly cleared.
  ///
  /// The reverse of this default is a real bug in this codebase: the create
  /// form's `copyWith` takes `error` verbatim, so a follow-up state update
  /// silently erased the upload failure and the screen reported success.
  /// Errors should have to be removed on purpose.
  ImageUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? error,
    bool clearError = false,
  }) {
    return ImageUploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Attaches a picked image to an existing CCTV record.
///
/// Same three-step flow as record creation — presign, PUT the bytes straight to
/// object storage, then complete — so a record saved without images can be
/// repaired later instead of being stuck empty.
class ImageUploadNotifier extends StateNotifier<ImageUploadState> {
  final Ref _ref;
  final String recordId;
  final ImagePicker _picker;

  ImageUploadNotifier(this._ref, this.recordId)
      : _picker = ImagePicker(),
        super(const ImageUploadState());

  /// Picks an image and attaches it to the record.
  ///
  /// Returns true only when the image is fully attached. Returns false when the
  /// user cancels, which is not an error and must not surface one.
  Future<bool> pickAndUpload(
    ImageSource source, {
    required String imageType,
  }) async {
    if (state.isUploading) return false;

    final PickedImage image;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: AppConstants.maxImageWidth.toDouble(),
        maxHeight: AppConstants.maxImageHeight.toDouble(),
        imageQuality: AppConstants.imageQuality,
      );
      if (picked == null) return false;
      image = await PickedImage.fromXFile(picked);
    } catch (_) {
      state = state.copyWith(
        error: 'Could not open the picker. Check camera and photo permissions.',
      );
      return false;
    }

    state = state.copyWith(isUploading: true, progress: 0, clearError: true);

    try {
      final service = _ref.read(cctvServiceProvider);
      final filename = image.filename;
      final contentType = image.contentType;

      final presign = await service.presign(
        cctvId: recordId,
        imageType: imageType,
        filename: filename,
        contentType: contentType,
      );

      final uploadUrl = presign['upload_url'] as String? ?? '';
      final objectKey = presign['object_key'] as String? ?? '';
      if (uploadUrl.isEmpty || objectKey.isEmpty) {
        throw ApiException('Upload was not authorised.');
      }

      // Bytes go straight to object storage; the backend never sees them.
      await service.uploadToStorage(
        uploadUrl,
        image.bytes,
        contentType: contentType,
        onProgress: (sent, total) {
          if (total > 0) state = state.copyWith(progress: sent / total);
        },
      );

      await service.completeImage(
        cctvId: recordId,
        objectKey: objectKey,
        imageType: imageType,
        mimeType: contentType,
        fileSize: image.bytes.length,
      );

      state = state.copyWith(isUploading: false, progress: 1);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isUploading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isUploading: false, error: 'Upload failed: $e');
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

/// Per-record image upload state, keyed by CCTV record id.
final imageUploadProvider = StateNotifierProvider.family<ImageUploadNotifier,
    ImageUploadState, String>((ref, recordId) {
  return ImageUploadNotifier(ref, recordId);
});