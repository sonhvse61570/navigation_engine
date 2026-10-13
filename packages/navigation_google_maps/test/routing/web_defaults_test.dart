// Runs on the VM, and in Chrome with `flutter test --platform chrome --tags js`
// (see dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_google_maps/src/routing/google_routes_route_provider.dart';
import 'package:navigation_google_maps/src/search/google_places_search.dart';

/// True under dart2js (the Chrome platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

/// [points] as a precision-5 polyline, encoded by hand (Google's
/// algorithm): from Ben Thanh Market south-west, across both signs' large
/// jumps, to (-33.85678, -70.648) and back up near Notre-Dame Cathedral.
const jump = 'u~v`AymfjSpskoGx{ly`@samoGwamy`@';

const points = [
  GeoPoint(10.77243, 106.69805),
  GeoPoint(-33.85678, -70.648),
  GeoPoint(10.7798, 106.699),
];

/// An answer with one route of two steps over [points], the second with a
/// fractional staticDuration.
String routeBody() => jsonEncode({
  'routes': [
    {
      'distanceMeters': 1000,
      'duration': '61.5s',
      'staticDuration': '61.5s',
      'polyline': {'encodedPolyline': jump},
      'legs': [
        {
          'steps': [
            {
              'distanceMeters': 500,
              'staticDuration': '20s',
              'polyline': {'encodedPolyline': 'u~v`AymfjSpskoGx{ly`@'},
              'navigationInstruction': {
                'maneuver': 'DEPART',
                'instructions': 'Đi về hướng tây nam trên Lê Lợi',
              },
            },
            {
              'distanceMeters': 500,
              'staticDuration': '41.5s',
              'polyline': {'encodedPolyline': 'zssmE~lenLsamoGwamy`@'},
              'navigationInstruction': {
                'maneuver': 'TURN_SLIGHT_RIGHT',
                'instructions': 'Chếch sang phải vào <b>Nguyễn Huệ</b>',
              },
            },
          ],
        },
      ],
      'routeLabels': ['DEFAULT_ROUTE'],
    },
  ],
});

MockClient recording(List<http.Request> requests, String body) =>
    MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(utf8.encode(body), 200);
    });

void main() {
  const from = GeoPoint(10.77243, 106.69805);
  const to = GeoPoint(10.7798, 106.699);

  test('step polylines, negative coordinates and large jumps included, '
      'decode the same on every platform', () async {
    final router = GoogleRoutesRouteProvider(
      apiKey: null,
      client: recording([], routeBody()),
    );
    final route = await router.route(from, to);
    expect(route.points, points);
    expect(
      [for (final s in route.steps) (s.type, s.modifier, s.roadName)],
      [
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.turn, ManeuverModifier.slightRight, 'Nguyễn Huệ'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ],
    );
    expect(route.duration, closeTo(61.5, 1e-9));
    expect(route.durationAt(route.distanceAtVertex(1)), closeTo(20, 1e-9));
  });

  test('the heading and the coordinates are sent the same on every '
      'platform', () async {
    final requests = <http.Request>[];
    final router = GoogleRoutesRouteProvider(
      apiKey: null,
      client: recording(requests, routeBody()),
    );
    await router.route(
      const GeoPoint(10.0, -106.0),
      const GeoPoint(-0.0, 1e-7),
      heading: 359.6,
    );
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['origin'], {
      'location': {
        'latLng': {'latitude': 10, 'longitude': -106},
        'heading': 0,
      },
    });
    expect(((body['destination']! as Map)['location']! as Map)['latLng'], {
      'latitude': 0,
      'longitude': 1e-7,
    });
  });

  test('the Geocoding latlng is written the same on every platform', () async {
    final requests = <http.Request>[];
    final search = GooglePlacesSearch(
      apiKey: null,
      client: recording(requests, '{"status": "ZERO_RESULTS", "results": []}'),
    );
    await search.reverse(const GeoPoint(10, -106));
    await search.reverse(const GeoPoint(-0.0, 1e-7));
    await search.reverse(const GeoPoint(10.7724297123456, 106.698048412345));
    expect(
      [for (final r in requests) r.url.query],
      [
        'latlng=10,-106',
        'latlng=0,0.0000001',
        'latlng=10.7724297123456,106.698048412345',
      ],
    );
  });

  test('the default userAgent is null on the web, so no User-Agent header '
      'forces a CORS preflight; elsewhere it names the package', () async {
    final requests = <http.Request>[];
    final router = GoogleRoutesRouteProvider(
      apiKey: null,
      client: recording(requests, routeBody()),
    );
    final search = GooglePlacesSearch(
      apiKey: null,
      client: recording(requests, '{"suggestions": []}'),
    );
    await router.route(from, to);
    await search.autocomplete('phở', session: PlaceSearchSession());
    expect(requests, hasLength(2));
    for (final r in requests) {
      if (compiledToJs) {
        expect(r.headers.containsKey('User-Agent'), isFalse);
      } else {
        expect(r.headers['User-Agent'], 'navigation_google_maps/0.1.0');
      }
    }
    if (compiledToJs) {
      expect(router.userAgent, isNull);
      expect(search.userAgent, isNull);
    } else {
      expect(router.userAgent, GoogleRoutesRouteProvider.defaultUserAgent);
      expect(search.userAgent, GooglePlacesSearch.defaultUserAgent);
    }
  });

  test('an explicit userAgent is sent on every platform', () async {
    final requests = <http.Request>[];
    final router = GoogleRoutesRouteProvider(
      apiKey: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, routeBody()),
    );
    final search = GooglePlacesSearch(
      apiKey: null,
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
