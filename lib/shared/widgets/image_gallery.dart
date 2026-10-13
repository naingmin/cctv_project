import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/local_image_store.dart';
import 'resilient_image.dart';

/// Image gallery with full-screen viewer.
class ImageGallery extends StatelessWidget {
  final List<String> imageUrls;
  final String title;
  final List<String>? captions;

  /// CCTV record ID used to resolve fresh URLs from the API when
  /// presigned URLs become stale (e.g. after a server IP change).
  final String? cctvId;

  const ImageGallery({
    super.key,
    required this.imageUrls,
    this.title = 'Images',
    this.captions,
    this.cctvId,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 1,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openGallery(context, index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: cctvId != null
                      ? ResilientImage(
                          source: imageUrls[index],
                          cctvId: cctvId!,
                          width: 100,
                          height: 100,
                        )
                      : _GalleryThumbnail(
                          source: imageUrls[index],
                          width: 100,
                          height: 100,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openGallery(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          title: title,
          captions: captions,
        ),
      ),
    );
  }
}

/// Thumbnail that renders either a network image or a local file.
class _GalleryThumbnail extends StatelessWidget {
  final String source;
  final double width;
  final double height;

  const _GalleryThumbnail({
    required this.source,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (LocalImageStore.isRemote(source)) {
      return CachedNetworkImage(
        imageUrl: source,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _error(),
      );
    }
    // No file system in the browser; local paths only exist on devices.
    if (kIsWeb) return _error();
    return Image.file(
      File(source),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _error(),
    );
  }

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceVariant,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _error() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.broken_image, color: AppColors.textTertiary),
      );
}

/// Full-screen image viewer with pinch zoom and swipe.
class _ImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String title;
  final List<String>? captions;

  const _ImageViewer({
    required this.imageUrls,
    required this.initialIndex,
    required this.title,
    this.captions,
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A local path cannot resolve in a browser (no file system). Render a
    // clear message rather than letting FileImage fail mid-zoom.
    if (kIsWeb && !LocalImageStore.isRemote(widget.imageUrls[_currentIndex])) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Image', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Icon(Icons.broken_image, color: AppColors.textTertiary, size: 48),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        builder: (context, index) {
          final source = widget.imageUrls[index];
          final ImageProvider provider;
          if (LocalImageStore.isRemote(source)) {
            provider = CachedNetworkImageProvider(source);
          } else {
            provider = FileImage(File(source));
          }
          return PhotoViewGalleryPageOptions(
            imageProvider: provider,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: source),
          );
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
      bottomNavigationBar: widget.captions != null && widget.captions!.isNotEmpty
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.captions![_currentIndex],
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }
}
