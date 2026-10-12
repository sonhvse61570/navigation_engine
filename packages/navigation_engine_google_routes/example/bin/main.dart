import 'dart:io';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';
import 'package:navigation_engine_google_routes_example/trip_report.dart';

/// Searches for a destination and prints the routes to it:
///
///     GOOGLE_ROUTES_KEY=... dart run bin/main.dart [query [from-lat,lng]]
///
/// Live requests, billed to the key's project.
Future<void> main(List<String> args) async {
  final key = Platform.environment['GOOGLE_ROUTES_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln(
      'Set GOOGLE_ROUTES_KEY to a Google Maps Platform API key that may '
      'call the Routes API and the Places API (New).',
    );
    exitCode = 64;
    return;
  }
  final query = args.isNotEmpty ? args[0] : 'Nhà thờ Đức Bà';
  final from = args.length > 1
      ? _point(args[1])
      : const GeoPoint(10.772431, 106.698048); // Ben Thanh Market
  final search = GooglePlacesSearch(
    apiKey: key,
    languageCode: 'vi',
    regionCodes: const ['vn'],
  );
  final router = GoogleRoutesRouteProvider(apiKey: key, languageCode: 'vi');
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
