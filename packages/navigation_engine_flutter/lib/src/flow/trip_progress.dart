/// How much of the trip is left, for a trip-progress bar.
final class TripProgress {
  /// Creates the progress of a trip.
  const TripProgress({
    required this.remainingDistance,
    required this.remainingDuration,
    required this.eta,
    required this.fraction,
  });

  /// Metres to the destination along the route.
  final double remainingDistance;

  /// Time to the destination, from the route's durations.
  final Duration remainingDuration;

  /// Estimated arrival time, on the controller's clock.
  final DateTime eta;

  /// Share of the route driven, 0 to 1.
  final double fraction;

  @override
  String toString() =>
      'TripProgress(${remainingDistance.toStringAsFixed(0)} m, '
      '$remainingDuration, eta $eta)';
}

/// The vehicle's speed and the speed limit where it is.
final class SpeedInfo {
  /// Creates the [speed] and the [limit], both in metres per second.
  const SpeedInfo({required this.speed, this.limit});

  /// Metres per second.
  final double speed;

  /// Metres per second; null when unknown or not navigating.
  final double? limit;

  /// More than 5 % over the limit.
  bool get isOverLimit {
    final l = limit;
    return l != null && speed > l * 1.05;
  }

  @override
  String toString() => 'SpeedInfo($speed m/s, limit $limit)';
}

/// How [NavigationFlowController.isNight] is decided.
enum NightMode {
  /// From sunrise and sunset where the vehicle is.
  auto,

  /// Always day.
  alwaysDay,

  /// Always night.
  alwaysNight,
}
