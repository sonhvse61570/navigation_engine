// Runs on the VM, and in Chrome with `flutter test --platform chrome --tags
// js test/routing` (see dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_mapbox/src/routing/mapbox_directions_route_provider.dart';
import 'package:navigation_mapbox/src/search/mapbox_search.dart';
import 'package:navigation_osrm/navigation_osrm.dart' show OsrmGeometries;

/// True under dart2js (the Chrome platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

/// An Ok answer with one route over [geometry] (polyline6 or GeoJSON),
/// from (21.028772, 105.852379) south-west, across both signs' large
/// jumps, to (-33.856784, -70.648) and back up to (21.04, 105.844).
String routeBody(Object geometry) => jsonEncode({
  'code': 'Ok',
  'routes': [
    {
      'geometry': geometry,
      'distance': 1000,
      'duration': 60,
      'legs': [
        {
          'summary': '',
          'duration': 60,
          'annotation': {
            'duration': [20, 40],
            'maxspeed': [
              {'speed': 60, 'unit': 'km/h'},
              {'speed': 35, 'unit': 'mph'},
            ],
          },
          'steps': [
            {
              'name': 'Đinh Tiên Hoàng',
              'maneuver': {
                'type': 'depart',
                'location': [105.852379, 21.028772],
              },
            },
            {
              'name': '',
              'maneuver': {
                'type': 'arrive',
                'location': [105.844, 21.04],
              },
            },
          ],
        },
      ],
    },
  ],
});

const points = [
  GeoPoint(21.028772, 105.852379),
  GeoPoint(-33.856784, -70.648),
  GeoPoint(21.04, 105.844),
];

/// [points] as polyline6, encoded by hand (Google's algorithm, 1e6).
const polyline6 = 'gynbg@u|u{hEfj}tgBthvsoI_hsugB_}esoI';

MockClient recording(List<http.Request> requests, String body) =>
    MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(utf8.encode(body), 200);
    });

void main() {
  const from = GeoPoint(21.028772, 105.852379);
  const to = GeoPoint(21.04, 105.844);

  test('a polyline6 route, negative coordinates and large jumps included, '
      'decodes the same on every platform', () async {
    final router = MapboxDirectionsRouteProvider(
      accessToken: null,
      client: recording([], routeBody(polyline6)),
    );
    final route = await router.route(from, to);
    expect(route.points, points);
    expect(route.steps.first.roadName, 'Đinh Tiên Hoàng');
    expect(route.speedLimitAt(1), closeTo(60 / 3.6, 1e-9));
    expect(route.speedLimitAt(route.length - 1), closeTo(35 * 0.44704, 1e-9));
  });

  test('a GeoJSON route reads the same points', () async {
    final router = MapboxDirectionsRouteProvider(
      accessToken: null,
      geometries: OsrmGeometries.geojson,
      client: recording(
        [],
        routeBody({
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lng, p.lat],
          ],
        }),
      ),
    );
    expect((await router.route(from, to)).points, points);
  });

  test('coordinates are written the same on every platform', () async {
    final requests = <http.Request>[];
    final router = MapboxDirectionsRouteProvider(
      accessToken: null,
      client: recording(requests, routeBody(polyline6)),
    );
    await router.route(const GeoPoint(10, -106), const GeoPoint(-0.0, 1e-7));
    await router.route(
      const GeoPoint(21.0287721234567, 105.852379123456),
      const GeoPoint(-33.5, 151.25),
    );
    expect(
      [for (final r in requests) r.url.pathSegments.last],
      ['-106,10;0.0000001,0', '105.852379123456,21.0287721234567;151.25,-33.5'],
    );
  });

  test('the default userAgent is null on the web, so no User-Agent header '
      'forces a CORS preflight; elsewhere it names the package', () async {
    final requests = <http.Request>[];
    final router = MapboxDirectionsRouteProvider(
      accessToken: null,
      client: recording(requests, routeBody(polyline6)),
    );
    final search = MapboxSearch(
      accessToken: null,
      client: recording(requests, '{"suggestions": []}'),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    expect(requests, hasLength(2));
    for (final r in requests) {
      if (compiledToJs) {
        expect(r.headers.containsKey('User-Agent'), isFalse);
      } else {
        expect(r.headers['User-Agent'], 'navigation_mapbox/0.1.0');
      }
    }
    if (compiledToJs) {
      expect(router.userAgent, isNull);
      expect(search.userAgent, isNull);
    } else {
      expect(router.userAgent, MapboxDirectionsRouteProvider.defaultUserAgent);
      expect(search.userAgent, MapboxSearch.defaultUserAgent);
    }
  });

  test('an explicit userAgent is sent on every platform', () async {
    final requests = <http.Request>[];
    final router = MapboxDirectionsRouteProvider(
      accessToken: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, routeBody(polyline6)),
    );
    final search = MapboxSearch(
      accessToken: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, '{"suggestions": []}'),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    expect(
      [for (final r in requests) r.headers['User-Agent']],
      ['my_app/2.0', 'my_app/2.0'],
    );
  });
}
