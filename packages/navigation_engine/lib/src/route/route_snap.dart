import '../geo/geo_point.dart';

/// The result of projecting a position onto a route.
final class RouteSnap {
  const RouteSnap({
    required this.distance,
    required this.segment,
    required this.point,
    required this.offset,
  });

  /// Metres along the route of the projected point.
  final double distance;

  /// Index of the segment (`points[segment]` → `points[segment + 1]`).
  final int segment;

  /// The projected point (on the route).
  final GeoPoint point;

  /// Metres between the input position and [point].
  final double offset;
}
