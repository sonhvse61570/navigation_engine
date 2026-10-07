import 'package:navigation_engine/navigation_engine.dart';

/// A GeoJSON FeatureCollection with one LineString (empty for fewer than
/// two points), for map SDKs that draw lines from GeoJSON sources.
Map<String, Object> lineFeatureCollection(List<GeoPoint> points) => {
  'type': 'FeatureCollection',
  'features': [
    if (points.length >= 2)
      {
        'type': 'Feature',
        'properties': <String, Object>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lng, p.lat],
          ],
        },
      },
  ],
};

/// A GeoJSON FeatureCollection with one Point carrying a `bearing`
/// property (degrees), or no feature when [position] is null.
Map<String, Object> pointFeatureCollection(
  GeoPoint? position, {
  double bearing = 0,
}) => {
  'type': 'FeatureCollection',
  'features': [
    if (position != null)
      {
        'type': 'Feature',
        'properties': {'bearing': bearing},
        'geometry': {
          'type': 'Point',
          'coordinates': [position.lng, position.lat],
        },
      },
  ],
};
