with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'r') as f:
    content = f.read()

# Remove direction from the CctvFormState constructor
old_constructor = """const CctvFormState({
    isLoading: false,
    isUploading: false,
    uploadProgress: 0.0,
    totalImages: 0,
    uploadedImages: 0,
    currentStatusMessage,
    error,
    cctvId,
    description,
    latitude,
    longitude,
    gpsAccuracy,
    cctvViewImage,
    environmentImages = const [],
    region,
    township,
    street,
    direction,
    status = 'ACTIVE',
  });"""

new_constructor = """const CctvFormState({
    isLoading: false,
    isUploading: false,
    uploadProgress: 0.0,
    totalImages: 0,
    uploadedImages: 0,
    currentStatusMessage,
    error,
    cctvId,
    description,
    latitude,
    longitude,
    gpsAccuracy,
    cctvViewImage,
    environmentImages = const [],
    region,
    township,
    street,
    status = 'ACTIVE',
  });"""

if old_constructor in content:
    content = content.replace(old_constructor, new_constructor)
    print('SUCCESS: Removed direction from CctvFormState constructor')
else:
    print('Pattern not found for constructor')

# Remove direction from copyWith method
old_copywith = """direction,
    String? status,
    bool clearGpsAccuracy = false,
    bool clearCctvViewImage = false,
  ) {
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
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy:
          clearGpsAccuracy ? null : (gpsAccuracy ?? this.gpsAccuracy),
      cctvViewImage:
          clearCctvViewImage ? null : (cctvViewImage ?? this.cctvViewImage),
      environmentImages: environmentImages ?? this.environmentImages,
      region: region ?? this.region,
      township: township ?? this.township,
      street: street ?? this.street,
      status: status ?? this.status,
    );"""

new_copywith = """String? status,
    bool clearGpsAccuracy = false,
    bool clearCctvViewImage = false,
  ) {
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
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy:
          clearGpsAccuracy ? null : (gpsAccuracy ?? this.gpsAccuracy),
      cctvViewImage:
          clearCctvViewImage ? null : (cctvViewImage ?? this.cctvViewImage),
      environmentImages: environmentImages ?? this.environmentImages,
      region: region ?? this.region,
      township: township ?? this.township,
      street: street ?? this.street,
      status: status ?? this.status,
    );"""

if old_copywith in content:
    content = content.replace(old_copywith, new_copywith)
    print('SUCCESS: Removed direction from copyWith method')
else:
    print('Pattern not found for copyWith')

# Write back
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'w') as f:
    f.write(content)

print('SUCCESS: cctv_form_provider.dart fixed')