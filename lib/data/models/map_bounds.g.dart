// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_bounds.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MapBounds _$MapBoundsFromJson(Map<String, dynamic> json) => MapBounds(
      north: (json['north'] as num).toDouble(),
      south: (json['south'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
      zoom: (json['zoom'] as num).toDouble(),
    );

Map<String, dynamic> _$MapBoundsToJson(MapBounds instance) => <String, dynamic>{
      'north': instance.north,
      'south': instance.south,
      'east': instance.east,
      'west': instance.west,
      'zoom': instance.zoom,
    };
