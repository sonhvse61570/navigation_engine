import '../geo/geo_point.dart';

/// Where the vehicle is on one display frame.
final class MotionFrame {
  const MotionFrame({
    required this.position,
    required this.bearing,
    required this.speed,
    this.routeDistance,
    this.offRoute = false,
  });

  final GeoPoint position;

  /// Degrees clockwise from north (the vehicle's heading).
  final double bearing;

  /// Displayed speed in m/s.
  final double speed;

  /// Metres along the route (route-following engine only).
  final double? routeDistance;

  /// Whether the fixes have been away from the route for a while.
  final bool offRoute;
}
