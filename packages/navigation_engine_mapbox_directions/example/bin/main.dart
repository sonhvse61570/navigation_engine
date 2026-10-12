import 'dart:io';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_mapbox_directions/navigation_engine_mapbox_directions.dart';
import 'package:navigation_engine_mapbox_directions_example/trip_report.dart';

/// Searches for a destination and prints the routes to it:
///
///     MAPBOX_TOKEN=pk.... dart run bin/main.dart [query [from-lat,lng]]
///
/// Live requests, billed to the token's account.
Future<void> main(List<String> args) async {
  final token = Platform.environment['MAPBOX_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('Set MAPBOX_TOKEN to a Mapbox access token (pk....).');
    exitCode = 64;
    return;
  }
  final query = args.isNotEmpty ? args[0] : 'Hồ Tây';
  final from = args.length > 1
      ? _point(args[1])
      : const GeoPoint(21.028772, 105.852379); // Hoan Kiem Lake
  final search = MapboxSearch(accessToken: token, language: 'vi');
  final router = MapboxDirectionsRouteProvider(
    accessToken: token,
    language: 'vi',
  );
  try {
    (await tripReport(search, router, from, query)).forEach(print);
  } finally {
    search.close();
    router.close();
  }
}

GeoPoint _point(String latLng) {
  final [lat, lng] = latLng.split(',').map(double.parse).toList();
  return GeoPoint(lat, lng);
}
