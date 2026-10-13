import 'package:json_annotation/json_annotation.dart';

part 'map_bounds.g.dart';

/// Map bounding box for viewport-based queries.
@JsonSerializable()
class MapBounds {
  final double north;
  final double south;
  final double east;
  final double west;
  final double zoom;

  const MapBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.zoom,
  });

  factory MapBounds.fromJson(Map<String, dynamic> json) =>
      _$MapBoundsFromJson(json);

  Map<String, dynamic> toJson() => _$MapBoundsToJson(this);

  /// Convert to query parameters for the API.
  Map<String, String> toQueryParams() {
    return {
      'north': north.toString(),
      'south': south.toString(),
      'east': east.toString(),
      'west': west.toString(),
      'zoom': zoom.toString(),
    };
  }
}
