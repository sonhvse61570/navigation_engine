import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';

/// Searches [search] for [query] in one session, resolves the best
/// suggestion (which ends the session), asks [router] for the routes from
/// [from] to it, and describes them, or the error (a transport failure
/// included), one line each.
Future<List<String>> tripReport(
  GooglePlacesSearch search,
  GoogleRoutesRouteProvider router,
  GeoPoint from,
  String query,
) async {
  try {
    final session = PlaceSearchSession();
    final suggestions = await search.autocomplete(
      query,
      near: from,
      session: session,
    );
    if (suggestions.isEmpty) return ['No place found for "$query"'];
    final place = await search.resolve(suggestions.first, session: session);
    final routes = await router.routes(from, place.position);
    return [
      'To ${place.name}${place.address == null ? '' : ' (${place.address})'}',
      ...describeRoutes(routes),
    ];
  } on GoogleRoutesException catch (e) {
    return ['$e'];
  } on GooglePlacesSearchException catch (e) {
    return ['$e'];
  } on Exception catch (e) {
    // A transport failure (offline, DNS, TLS), from the route provider.
    return ['$e'];
  }
}

/// One header line per route (Google's best first), then its manoeuvres.
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
