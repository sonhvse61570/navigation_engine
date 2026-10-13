import 'dart:io';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_goong/navigation_goong.dart';
import 'package:navigation_goong_example/trip_report.dart';

/// Searches for a destination and prints the routes to it:
///
///     GOONG_API_KEY=... dart run bin/main.dart [query [from-lat,lng]]
///
/// Live requests, billed to the key. An app should keep the API key on a
/// server (see the package README).
Future<void> main(List<String> args) async {
  final key = Platform.environment['GOONG_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set GOONG_API_KEY to a Goong API key (the REST key).');
    exitCode = 64;
    return;
  }
  final query = args.isNotEmpty ? args[0] : 'Hồ Tây';
  final from = args.length > 1
      ? _point(args[1])
      : const GeoPoint(21.028772, 105.852379); // Hoan Kiem Lake
  final search = GoongPlaceSearch(apiKey: key);
  final router = GoongRouteProvider(apiKey: key);
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
