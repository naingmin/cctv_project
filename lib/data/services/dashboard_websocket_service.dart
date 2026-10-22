import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/prefs_token_store.dart';
import '../models/dashboard_stats.dart';

class DashboardUpdate {
  final DashboardStats stats;
  final String? cctvId;
  final String? status;
  final DateTime? lastChecked;

  const DashboardUpdate({
    required this.stats,
    this.cctvId,
    this.status,
    this.lastChecked,
  });

  factory DashboardUpdate.fromJson(Map<String, dynamic> json) {
    final cctv = json['cctv'] as Map<String, dynamic>?;
    return DashboardUpdate(
      stats: DashboardStats.fromJson(json['stats'] as Map<String, dynamic>),
      cctvId: cctv?['id'] as String?,
      status: cctv?['status'] as String?,
      lastChecked: cctv?['last_checked'] == null
          ? null
          : DateTime.parse(cctv!['last_checked'] as String),
    );
  }
}

final dashboardUpdatesProvider =
    StreamProvider.autoDispose<DashboardUpdate>((ref) async* {
  final token = await ref.read(tokenStorageProvider).readAccessToken();
  if (token == null || token.isEmpty) {
    throw StateError('An access token is required for dashboard updates.');
  }

  final apiUri = Uri.parse(AppConfig.apiV1);
  final path = '${apiUri.path.replaceFirst(RegExp(r'/$'), '')}/ws/dashboard';
  final uri = apiUri.replace(
    scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
    path: path,
  );
  final channel = WebSocketChannel.connect(uri);
  ref.onDispose(() => channel.sink.close());

  await channel.ready;
  channel.sink.add(jsonEncode({'type': 'authenticate', 'token': token}));
  await for (final message in channel.stream) {
    if (message is! String) {
      throw const FormatException('Invalid dashboard WebSocket message.');
    }
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid dashboard WebSocket message.');
    }
    if (decoded['type'] == 'dashboard_update') {
      yield DashboardUpdate.fromJson(decoded);
    }
  }
});
