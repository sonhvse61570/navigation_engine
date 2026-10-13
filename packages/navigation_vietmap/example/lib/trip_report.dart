import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';

/// Searches [search] for [query], resolves the best suggestion, asks
/// [router] for the routes from [from] to it, and describes them, or the
/// error (a transport failure included), one line each.
Future<List<String>> tripReport(
  VietmapPlaceSearch search,
  VietmapRouteProvider router,
  GeoPoint from,
  String query,
) async {
  try {
    final suggestions = await search.autocomplete(query, near: from);
    if (suggestions.isEmpty) return ['No place found for "$query"'];
    final place = await search.resolve(suggestions.first);
    final routes = await router.routes(from, place.position);
    return [
      'To ${place.name}${place.address == null ? '' : ' (${place.address})'}',
      ...describeRoutes(routes),
    ];
  } on VietmapException catch (e) {
    return ['$e'];
  } on VietmapSearchException catch (e) {
    return ['$e'];
  } on Exception catch (e) {
    // A transport failure (offline, DNS, TLS), from the route provider.
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
          '${s.roadName.isEmpty ? '' : ' onto ${s.roadName}'}',
  ],
];
