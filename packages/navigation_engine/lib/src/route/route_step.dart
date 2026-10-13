import '../geo/geo_point.dart';
import 'lane.dart';
import 'maneuver.dart';

/// A manoeuvre as a routing back end delivers it, before it is placed on the
/// route: either at a vertex index of the polyline or at a location.
final class RouteStepSeed {
  /// At `points[vertex]` of the route.
  const RouteStepSeed.atVertex(
    int this.vertex, {
    required this.type,
    this.modifier = ManeuverModifier.none,
    this.roadName = '',
    this.lanes = const [],
  }) : location = null;

  /// At [location], which should be (within 0.5 m of) a route vertex, as
  /// OSRM and Google return them. Resolved by searching forward from the
  /// previous step, so a U-turn back over the same road is placed on the way
  /// back, not on the way out.
  const RouteStepSeed.atLocation(
    GeoPoint this.location, {
    required this.type,
    this.modifier = ManeuverModifier.none,
    this.roadName = '',
    this.lanes = const [],
  }) : vertex = null;

  /// The index of the route point the manoeuvre is at; null when [location]
  /// places it.
  final int? vertex;

  /// Where the manoeuvre is; null when [vertex] places it.
  final GeoPoint? location;

  /// What the driver has to do.
  final ManeuverType type;

  /// The direction of the manoeuvre.
  final ManeuverModifier modifier;

  /// The road the manoeuvre leads onto; empty when unnamed.
  final String roadName;

  /// The lanes before the manoeuvre, left to right (empty when unknown).
  final List<Lane> lanes;
}

/// A manoeuvre placed on a route.
final class RouteStep {
  /// Creates a step [distance] metres along the route.
  const RouteStep({
    required this.distance,
    required this.type,
    this.modifier = ManeuverModifier.none,
    this.roadName = '',
    this.lanes = const [],
  });

  /// Metres from the start of the route to the manoeuvre.
  final double distance;

  /// What the driver has to do.
  final ManeuverType type;

  /// The direction of the manoeuvre.
  final ManeuverModifier modifier;

  /// The road the manoeuvre leads onto; empty when unnamed.
  final String roadName;

  /// The lanes before the manoeuvre, left to right (empty when unknown).
  final List<Lane> lanes;

  /// Whether this is the arrival at the destination.
  bool get isArrival => type == ManeuverType.arrive;

  @override
  String toString() {
    final lanesNote = switch (lanes.length) {
      0 => '',
      1 => ', 1 lane',
      final n => ', $n lanes',
    };
    return 'RouteStep(${type.name}, ${modifier.name}, "$roadName", '
        '${distance.toStringAsFixed(1)} m$lanesNote)';
  }
}
