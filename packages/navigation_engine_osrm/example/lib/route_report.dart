import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';

/// Asks [provider] for the routes from [from] to [to] and describes them,
/// or the error, one line each.
Future<List<String>> routeReport(
  OsrmRouteProvider provider,
  GeoPoint from,
  GeoPoint to,
) async {
  try {
    return describeRoutes(await provider.routes(from, to));
  } on OsrmException catch (e) {
    return ['$e'];
  }
}

/// One header line per route (best first), then its manoeuvres.
List<String> describeRoutes(List<NavRoute> routes) => [
  for (final (i, r) in routes.indexed) ...[
    '${i == 0 ? 'Best' : 'Alternative $i'}: '
        '${(r.length / 1000).toStringAsFixed(1)} km, '
        '${(r.duration / 60).round()} min, via ${r.summary}',
    for (final s in r.steps)
      '  ${s.distance.round().toString().padLeft(6)} m  '
          '${s.type.name} ${s.modifier.name}'
          '${s.roadName.isEmpty ? '' : ' onto ${s.roadName}'}'
          '${s.lanes.isEmpty ? '' : ' (${s.lanes.length} lanes)'}',
  ],
];
