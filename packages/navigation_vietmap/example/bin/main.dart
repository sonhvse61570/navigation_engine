import 'dart:io';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:navigation_vietmap_example/trip_report.dart';

/// Searches for a destination and prints the routes to it:
///
///     VIETMAP_SERVICES_KEY=... dart run bin/main.dart [query [from-lat,lng]]
///
/// Live requests, billed to the key. An app should keep the services key
/// on a server (see the package README).
Future<void> main(List<String> args) async {
  final key = Platform.environment['VIETMAP_SERVICES_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set VIETMAP_SERVICES_KEY to a Vietmap services key.');
    exitCode = 64;
    return;
  }
  final query = args.isNotEmpty ? args[0] : 'Landmark 81';
  final from = args.length > 1
      ? _point(args[1])
      : const GeoPoint(10.771897, 106.698226); // Ben Thanh market
  final search = VietmapPlaceSearch(apiKey: key);
  final router = VietmapRouteProvider(apiKey: key);
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
