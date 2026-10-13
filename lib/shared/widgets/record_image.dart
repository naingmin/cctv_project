import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/local_image_store.dart';

/// Displays a CCTV image from either a network URL or a local file path.
///
/// Records created while offline store an absolute file path, while synced
/// records store an `http(s)` URL. This widget renders whichever is available.
class RecordImage extends StatelessWidget {
  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? errorBuilder;

  const RecordImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final value = source;
    if (value == null || value.isEmpty) {
      return _fallback(context);
    }

    if (LocalImageStore.isRemote(value)) {
      return CachedNetworkImage(
        imageUrl: value,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _fallback(context),
      );
    }

    // A local path cannot resolve in a browser (no file system), and no
    // record stores one there anyway - show the fallback instead of
    // letting Image.file fail.
    if (kIsWeb) return _fallback(context);

    return Image.file(
      File(value),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _fallback(context),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceVariant,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    if (errorBuilder != null) return errorBuilder!(context);
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.broken_image, color: AppColors.textTertiary),
    );
  }
}
