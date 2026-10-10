import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';
import 'package:navigation_engine_osrm_example/route_report.dart';

/// Prints the routes between two points:
///
///     dart run bin/main.dart [from-lat,lng to-lat,lng [server-url]]
///
/// Without a server it asks OSRM's public demo server, which is for
/// testing only.
Future<void> main(List<String> args) async {
  final from = args.isNotEmpty
      ? _point(args[0])
      : const GeoPoint(10.771897, 106.698226); // Ben Thanh market
  final to = args.length > 1
      ? _point(args[1])
      : const GeoPoint(10.795172, 106.721646); // Landmark 81
  final provider = OsrmRouteProvider(
    baseUrl: args.length > 2 ? Uri.parse(args[2]) : null,
    userAgent: 'navigation_engine_osrm_example/1.0',
  );
  try {
    (await routeReport(provider, from, to)).forEach(print);
  } finally {
    provider.close();
  }
}

GeoPoint _point(String latLng) {
  final [lat, lng] = latLng.split(',').map(double.parse).toList();
  return GeoPoint(lat, lng);
}
