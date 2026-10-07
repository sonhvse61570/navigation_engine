import '../geo/geo_point.dart';

/// One raw GPS fix, whatever its source (device, simulator, recording).
final class NavFix {
  const NavFix({
    required this.position,
    required this.accuracy,
    required this.time,
    this.speed,
    this.heading,
  });

  final GeoPoint position;

  /// Horizontal accuracy radius in metres.
  final double accuracy;

  /// When the fix was measured. It reaches the app later than that
  /// (typically 0.3–1 s); the motion engines compensate for the delay.
  ///
  /// Must be on the same clock as the `now` given to the motion engines,
  /// i.e. the `NavigationSession`'s clock (`DateTime.now` by default):
  /// the delay is the difference between the two.
  final DateTime time;

  /// Metres per second, or null when unknown. When null, the motion engines
  /// estimate it from consecutive fixes (the distance driven over the last
  /// few seconds), which is noisier than a measured speed.
  final double? speed;

  /// Degrees clockwise from north, or null when unknown. Unreliable below
  /// ~2 m/s on every platform.
  final double? heading;
}
