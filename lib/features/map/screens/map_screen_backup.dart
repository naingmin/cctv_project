import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/cctv_record_model.dart';
import '../../../data/models/map_bounds.dart';
import '../providers/map_provider.dart';

/// CCTV map screen using OpenStreetMap with viewport-based marker loading.
class MapScreen extends ConsumerStatefulWidget {
  /// Optional CCTV record id to focus when the screen opens.
  final String? focusRecordId;

  const MapScreen({super.key, this.focusRecordId});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _didInitialLoad = false;
  bool _didFocus = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      _loadMarkersForViewport();
    }
  }

  Future<void> _loadMarkersForViewport() async {
    final bounds = _mapController.camera.visibleBounds;
    final zoom = _mapController.camera.zoom;

    final mapBounds = MapBounds(
      north: bounds.north,
      south: bounds.south,
      east: bounds.east,
      west: bounds.west,
      zoom: zoom,
    );

    await ref.read(mapProvider.notifier).loadMarkers(mapBounds);
    _focusIfRequested();
  }

  /// Move the camera to the requested record and open its popup once.
  Future<void> _focusIfRequested() async {
    if (_didFocus || widget.focusRecordId == null) return;

    final record =
        await ref.read(mapProvider.notifier).focusRecord(widget.focusRecordId!);
    if (record == null || !mounted) return;

    _didFocus = true;
    _mapController.move(
      LatLng(record.latitude, record.longitude),
      16,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showMarkerPopup(record);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapProvider);

    if (!_didInitialLoad) {
      _didInitialLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMarkersForViewport());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CCTV Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMarkersForViewport,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              _mapController.move(
                const LatLng(
                  AppConstants.defaultLatitude,
                  AppConstants.defaultLongitude,
                ),
                AppConstants.defaultZoom,
              );
            },
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(
            AppConstants.defaultLatitude,
            AppConstants.defaultLongitude,
          ),
          initialZoom: AppConstants.defaultZoom,
          minZoom: 3,
          maxZoom: 19,
          onMapEvent: _onMapEvent,
        ),
        children: [
          // OpenStreetMap tile layer
          TileLayer(
            urlTemplate: AppConfig.mapTileUrl,
            userAgentPackageName: 'com.cctvmanager.app',
            maxZoom: 19,
          ),
          // CCTV markers
          MarkerLayer(
            markers: _buildMarkers(state.markers, state.focusedRecordId),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(List<CctvRecord> markers, String? focusedId) {
    return markers.map((record) {
      final isFocused = record.id == focusedId;
      return Marker(
        point: LatLng(record.latitude, record.longitude),
        width: isFocused ? 52 : 40,
        height: isFocused ? 52 : 40,
        child: GestureDetector(
          onTap: () => _showMarkerPopup(record),
          child: Container(
            decoration: BoxDecoration(
              color: _getStatusColor(record.status),
              shape: BoxShape.circle,
              border: Border.all(
                color: isFocused ? AppColors.primary : Colors.white,
                width: isFocused ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildDirectionIcon(record.direction, isFocused),
          ),
        ),
      );
    }).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'operational':
        return AppColors.success;
      case 'maintenance':
        return AppColors.warning;
      case 'inactive':
        return AppColors.danger;
      default:
        return AppColors.primary;
    }
  }

  // Helper method to get direction icon data
  Icon _buildDirectionIcon(String? direction, bool isFocused) {
    // Map direction to icon and rotation
    final icons = {
      'N': Icons.arrow_upward,
      'NE': Icons.arrow_upper_right,
      'E': Icons.arrow_right,
      'SE': Icons.arrow_lower_right,
      'S': Icons.arrow_downward,
      'SW': Icons.arrow_lower_left,
      'W': Icons.arrow_left,
      'NW': Icons.arrow_upper_left,
    };
    final icon = icons[direction] ?? Icons.compass;
    return Icon(
      icon,
      color: Colors.white,
      size: isFocused ? 26 : 20,
    );
  }

  void _showMarkerPopup(CctvRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.cctvId),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.description != null) ...[
              Text(record.description!),
              const SizedBox(height: 8),
            ],
            Text('Status: ${record.operationalStatus}'),
            const SizedBox(height: 4),
            Text(
              'Location: ${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/cctv/${record.id}');
            },
            child: const Text('View Details'),
          ),
        ],
      ),
    );
  }
}
