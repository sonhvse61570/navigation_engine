import '../geo/geo_point.dart';
import '../route/nav_route.dart';

/// Computes driving routes (OSRM, Google Routes, your own back end…).
///
/// Extend it: [route] is required, and [routes] has a default that returns
/// only the best route.
abstract class RouteProvider {
  const RouteProvider();

  /// A route from [from] to [to]. [heading] (degrees clockwise from north)
  /// is the way the vehicle is facing, so a reroute does not start with a
  /// U-turn. Throws when no route can be found.
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading});

  /// The best route first, then up to [maxAlternatives] alternatives, for a
  /// route overview. The default returns `[await route(...)]`; override it
  /// when the back end can return alternatives. Throws when no route can be
  /// found.
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) async => [await route(from, to, heading: heading)];
}
