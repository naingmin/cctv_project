import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/picked_image.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/services/cctv_service.dart';
import '../../../data/services/location_service.dart';

/// CCTV form state for add/edit.
class CctvFormState {
  final bool isLoading;
  final bool isUploading;
  final double uploadProgress;
  final int totalImages;
  final int uploadedImages;
  final String? currentStatusMessage;
  final String? error;
  final String? cctvId;
  final String? description;
  final String? ipAddress;
  final String? username;
  final String? password;
  final List<String> tags;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final PickedImage? cctvViewImage;
  final List<PickedImage> environmentImages;
  final String? region;
  final String? township;
  final String? street;
  final String? direction;
  final String status;

  const CctvFormState({
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.totalImages = 0,
    this.uploadedImages = 0,
    this.currentStatusMessage,
    this.error,
    this.cctvId,
    this.description,
    this.ipAddress,
    this.username,
    this.password,
    this.tags = const [],
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.cctvViewImage,
    this.environmentImages = const [],
    this.region,
    this.township,
    this.street,
    this.direction,
    this.status = 'ACTIVE',
  });

  CctvFormState copyWith({
    bool? isLoading,
    bool? isUploading,
    double? uploadProgress,
    int? totalImages,
    int? uploadedImages,
    String? currentStatusMessage,
    String? error,
    String? cctvId,
    String? description,
    String? ipAddress,
    String? username,
    String? password,
    List<String>? tags,
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    PickedImage? cctvViewImage,
    List<PickedImage>? environmentImages,
    String? region,
    String? township,
    String? street,
    String? direction,
    String? status,
    bool clearGpsAccuracy = false,
    bool clearCctvViewImage = false,
  }) {
    return CctvFormState(
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      totalImages: totalImages ?? this.totalImages,
      uploadedImages: uploadedImages ?? this.uploadedImages,
      currentStatusMessage: currentStatusMessage ?? this.currentStatusMessage,
      error: error,
      cctvId: cctvId ?? this.cctvId,
      description: description ?? this.description,
      ipAddress: ipAddress ?? this.ipAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      tags: tags ?? this.tags,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy: clearGpsAccuracy ? null : (gpsAccuracy ?? this.gpsAccuracy),
      cctvViewImage:
          clearCctvViewImage ? null : (cctvViewImage ?? this.cctvViewImage),
      environmentImages: environmentImages ?? this.environmentImages,
      region: region ?? this.region,
      township: township ?? this.township,
      street: street ?? this.street,
      direction: direction ?? this.direction,
      status: status ?? this.status,
    );
  }
}

/// CCTV form notifier.
class CctvFormNotifier extends StateNotifier<CctvFormState> {
  final CctvService _cctvService;
  final LocationService _locationService;
  final ImagePicker _imagePicker;

  CctvFormNotifier(this._cctvService, this._locationService)
      : _imagePicker = ImagePicker(),
        super(const CctvFormState());

  /// Clear all form fields and picked images.
  void reset() {
    state = const CctvFormState();
  }

  /// Set the location manually (e.g. a pin dropped on the map).
  void setManualLocation(double latitude, double longitude,
      {double? accuracy}) {
    state = state.copyWith(
      latitude: latitude,
      longitude: longitude,
      gpsAccuracy: accuracy,
      clearGpsAccuracy: accuracy == null,
      error: null,
    );
  }

  Future<void> captureLocation() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        state = state.copyWith(
          isLoading: false,
          latitude: position.latitude,
          longitude: position.longitude,
          gpsAccuracy: position.accuracy,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Unable to get GPS location. Please check permissions.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'GPS error: ${e.toString()}',
      );
    }
  }

  Future<void> pickCctvViewImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked != null) {
        state =
            state.copyWith(cctvViewImage: await PickedImage.fromXFile(picked));
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick image');
    }
  }

  Future<void> pickEnvironmentImage(ImageSource source) async {
    if (state.environmentImages.length >= 10) {
      state = state.copyWith(error: 'Maximum 10 environment images allowed');
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked != null) {
        state = state.copyWith(
          environmentImages: [
            ...state.environmentImages,
            await PickedImage.fromXFile(picked),
          ],
        );
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick image');
    }
  }

  void removeEnvironmentImage(int index) {
    final images = List<PickedImage>.from(state.environmentImages);
    images.removeAt(index);
    state = state.copyWith(environmentImages: images);
  }

  void clearCctvViewImage() {
    state = state.copyWith(clearCctvViewImage: true);
  }

  void updateField(String field, dynamic value) {
    switch (field) {
      case 'cctvId':
        state = state.copyWith(cctvId: value);
        break;
      case 'description':
        state = state.copyWith(description: value);
        break;
      case 'ipAddress':
        state = state.copyWith(ipAddress: value);
        break;
      case 'username':
        state = state.copyWith(username: value);
        break;
      case 'password':
        state = state.copyWith(password: value);
        break;
      case 'tags':
        state = state.copyWith(tags: List<String>.from(value as List));
        break;
      case 'region':
        state = state.copyWith(
          region: value,
          township: state.region == value ? state.township : '',
        );
        break;
      case 'township':
        state = state.copyWith(township: value);
        break;
      case 'street':
        state = state.copyWith(street: value);
        break;
      case 'direction':
        state = state.copyWith(direction: value);
        break;
      case 'status':
        state = state.copyWith(status: value);
        break;
    }
  }

  Future<CctvRecord?> submit() async {
    if (state.cctvId == null || state.cctvId!.trim().isEmpty) {
      state = state.copyWith(error: 'CCTV ID is required');
      return null;
    }
    if (state.latitude == null || state.longitude == null) {
      state = state.copyWith(error: 'Location is required');
      return null;
    }

    final totalImages =
        (state.cctvViewImage != null ? 1 : 0) + state.environmentImages.length;
    state = state.copyWith(
      isUploading: true,
      uploadProgress: 0.0,
      totalImages: totalImages,
      uploadedImages: 0,
      error: null,
      currentStatusMessage: 'Creating record...',
    );

    try {
      final record = CctvRecord(
        id: '',
        cctvId: state.cctvId!.trim().toUpperCase(),
        latitude: state.latitude!,
        longitude: state.longitude!,
        region: state.region,
        township: state.township,
        street: state.street,
        direction: state.direction,
        ipAddress: state.ipAddress,
        username: state.username,
        password: state.password,
        tags: state.tags,
        status: state.status,
        description: state.description,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final created = await _cctvService.createCctv(record);

      final failedImages = await _uploadImages(created.id);

      // The record is already persisted at this point, so an image failure is
      // a partial success, not a total one. `copyWith` always overwrites
      // `error` (it takes the value verbatim), so the outcome has to be
      // restated here - otherwise the message _uploadImages set is silently
      // dropped, this returns a non-null record, and the caller reports
      // success while the images are missing.
      state = state.copyWith(
        isUploading: false,
        uploadProgress: 1.0,
        currentStatusMessage:
            failedImages > 0 ? 'Saved without images' : 'Completed',
        error: failedImages > 0
            ? 'Record saved, but $failedImages image'
                '${failedImages == 1 ? '' : 's'} failed to upload. '
                'The record is missing ${failedImages == 1 ? 'its image' : 'those images'}.'
            : null,
      );
      return created;
    } on ApiException catch (e) {
      state = state.copyWith(isUploading: false, error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        error: 'Upload failed: ${e.toString()}',
      );
      return null;
    }
  }

  /// Uploads every selected image and returns how many did not make it.
  ///
  /// A non-zero result means "the record exists but is missing images", which
  /// the caller must surface - the record itself is already saved by this
  /// point, so returning null/failure here would be wrong.
  Future<int> _uploadImages(String cctvId) async {
    final jobs = <MapEntry<PickedImage, String>>[];
    if (state.cctvViewImage != null) {
      jobs.add(MapEntry(state.cctvViewImage!, 'CCTV_VIEW'));
    }
    for (final file in state.environmentImages) {
      jobs.add(MapEntry(file, 'ENVIRONMENT'));
    }
    if (jobs.isEmpty) return 0;

    var completed = 0;
    for (final job in jobs) {
      final file = job.key;
      final imageType = job.value;
      state = state.copyWith(
        currentStatusMessage:
            'Uploading image ${completed + 1} / ${jobs.length}',
      );
      try {
        await _uploadSingle(cctvId, file, imageType);
        completed++;
        state = state.copyWith(
          uploadedImages: completed,
          uploadProgress: completed / jobs.length,
        );
      } catch (_) {
        // Abandon the rest. Presigned URLs are single-use and short-lived, so
        // continuing would just burn through them; images can be re-picked
        // from the record's detail screen.
        return jobs.length - completed;
      }
    }
    return 0;
  }

  Future<void> _uploadSingle(
    String cctvId,
    PickedImage image,
    String imageType,
  ) async {
    final filename = image.filename;
    final contentType = image.contentType;

    final presign = await _cctvService.presign(
      cctvId: cctvId,
      imageType: imageType,
      filename: filename,
      contentType: contentType,
    );

    final uploadUrl = presign['upload_url'] as String;
    if (uploadUrl.isEmpty) {
      throw Exception('Upload was not authorised.');
    }

    // Bytes go straight to object storage; FastAPI never sees them.
    await _cctvService.uploadToStorage(
      uploadUrl,
      image.bytes,
      contentType: contentType,
      onProgress: (sent, total) {
        if (total > 0) {
          state = state.copyWith(uploadProgress: sent / total);
        }
      },
    );

    await _cctvService.completeImage(
      cctvId: cctvId,
      objectKey: presign['object_key'] as String,
      imageType: imageType,
      mimeType: contentType,
      fileSize: image.bytes.length,
    );
  }
}

/// Provider for CCTV form.
final cctvFormProvider =
    StateNotifierProvider<CctvFormNotifier, CctvFormState>((ref) {
  final cctvService = ref.watch(cctvServiceProvider);
  final locationService = ref.watch(locationServiceProvider);
  return CctvFormNotifier(cctvService, locationService);
});
