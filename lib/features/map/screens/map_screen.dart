import 'dart:ui' as ui;

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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadMarkersForViewport());
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
      final statusColor = _getStatusColor(record.status);
      final direction = record.direction?.trim().toUpperCase();
      final directionOffset = _directionOffsets[direction];
      final directionAngle = _directionAngles[direction];
      final markerSize = isFocused ? 104.0 : 96.0;
      final center = markerSize / 2;
      final arrowDistance = isFocused ? 35.0 : 31.0;
      return Marker(
        point: LatLng(record.latitude, record.longitude),
        width: markerSize,
        height: markerSize,
        child: GestureDetector(
          onTap: () => _showMarkerPopup(record),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: isFocused ? 48 : 40,
                height: isFocused ? 48 : 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: statusColor,
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
                  child: Center(
                    child: Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: isFocused ? 26 : 20,
                    ),
                  ),
                ),
              ),
              if (directionOffset != null && directionAngle != null)
                Positioned(
                  left: center + directionOffset.dx * arrowDistance - 12,
                  top: center + directionOffset.dy * arrowDistance - 10,
                  child: Transform.rotate(
                    angle: directionAngle,
                    child: const CustomPaint(
                      size: Size(24, 20),
                      painter: _DirectionArrowPainter(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  static const _directionOffsets = <String, Offset>{
    'N': Offset(0, -1),
    'NE': Offset(0.7071, -0.7071),
    'E': Offset(1, 0),
    'SE': Offset(0.7071, 0.7071),
    'S': Offset(0, 1),
    'SW': Offset(-0.7071, 0.7071),
    'W': Offset(-1, 0),
    'NW': Offset(-0.7071, -0.7071),
  };

  static const _directionAngles = <String, double>{
    'N': -1.5707963267948966,
    'NE': -0.7853981633974483,
    'E': 0,
    'SE': 0.7853981633974483,
    'S': 1.5707963267948966,
    'SW': 2.356194490192345,
    'W': 3.141592653589793,
    'NW': -2.356194490192345,
  };

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
              context.push('/cctv/${record.id}');
            },
            child: const Text('View Details'),
          ),
        ],
      ),
    );
  }
}

class _DirectionArrowPainter extends CustomPainter {
  const _DirectionArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final arrow = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..lineTo(size.width * 0.25, size.height / 2)
      ..close();

    canvas.drawShadow(arrow, Colors.black54, 2, true);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.fill,
    );

    final shadedFacet = ui.Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width * 0.25, size.height / 2)
      ..close();
    canvas.drawPath(
      shadedFacet,
      Paint()
        ..color = const Color(0xFFC62828)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) => false;
}
