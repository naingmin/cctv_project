import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/cctv_record_model.dart';

/// Upload status for queue items.
enum UploadStatus {
  pending,
  uploading,
  uploaded,
  failed;

  String get displayName {
    switch (this) {
      case UploadStatus.pending:
        return 'Pending';
      case UploadStatus.uploading:
        return 'Uploading';
      case UploadStatus.uploaded:
        return 'Uploaded';
      case UploadStatus.failed:
        return 'Failed';
    }
  }
}

/// Upload queue item for offline draft management.
class UploadQueueItem {
  final String id;
  final CctvRecord record;
  final List<String> cctvViewImagePaths;
  final List<String> environmentImagePaths;
  UploadStatus status;
  final DateTime createdAt;
  DateTime? uploadedAt;
  String? errorMessage;
  double progress;

  UploadQueueItem({
    required this.id,
    required this.record,
    this.cctvViewImagePaths = const [],
    this.environmentImagePaths = const [],
    this.status = UploadStatus.pending,
    required this.createdAt,
    this.uploadedAt,
    this.errorMessage,
    this.progress = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'record': record.toJson(),
        'cctvViewImagePaths': cctvViewImagePaths,
        'environmentImagePaths': environmentImagePaths,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'uploadedAt': uploadedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'progress': progress,
      };

  factory UploadQueueItem.fromJson(Map<String, dynamic> json) {
    return UploadQueueItem(
      id: json['id'] as String,
      record: CctvRecord.fromJson(json['record'] as Map<String, dynamic>),
      cctvViewImagePaths: List<String>.from(json['cctvViewImagePaths'] ?? []),
      environmentImagePaths: List<String>.from(json['environmentImagePaths'] ?? []),
      status: UploadStatus.values[json['status'] as int? ?? 0],
      createdAt: DateTime.parse(json['createdAt'] as String),
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.parse(json['uploadedAt'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Upload queue service for managing offline drafts.
class UploadQueueService {
  Box? _box;

  Future<void> init() async {
    _box = await Hive.openBox(AppConstants.hiveBoxUploadQueue);
  }

  List<UploadQueueItem> get items {
    if (_box == null) return [];
    return _box!.values
        .map((e) => UploadQueueItem.fromJson(jsonDecode(jsonEncode(e))))
        .toList();
  }

  Future<void> addItem(UploadQueueItem item) async {
    await _box?.put(item.id, jsonDecode(jsonEncode(item.toJson())));
  }

  Future<void> updateItem(UploadQueueItem item) async {
    await _box?.put(item.id, jsonDecode(jsonEncode(item.toJson())));
  }

  Future<void> removeItem(String id) async {
    await _box?.delete(id);
  }

  Future<void> clearUploaded() async {
    if (_box == null) return;
    final uploaded = items.where((i) => i.status == UploadStatus.uploaded);
    for (final item in uploaded) {
      await _box!.delete(item.id);
    }
  }

  int get pendingCount => items.where((i) => i.status == UploadStatus.pending).length;
  int get failedCount => items.where((i) => i.status == UploadStatus.failed).length;
}

/// Provider for UploadQueueService.
final uploadQueueServiceProvider = Provider<UploadQueueService>((ref) {
  return UploadQueueService();
});
