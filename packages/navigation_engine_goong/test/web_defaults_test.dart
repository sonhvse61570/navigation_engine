// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_goong/navigation_engine_goong.dart';
import 'package:test/test.dart';

/// True under dart2js (the `node` platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

final String routeBody = jsonEncode({
  'routes': [
    {
      'legs': [
        {
          'distance': {'text': '', 'value': 1000},
          'duration': {'text': '', 'value': 120},
          'steps': [
            {
              'duration': {'text': '', 'value': 120},
              'html_instructions': 'Bắt đầu đi từ Trần Cung',
              'polyline': {'points': 'oin_C_awdSo}@?'},
            },
          ],
        },
      ],
    },
  ],
});

const String searchBody = '{"predictions":[],"status":"ZERO_RESULTS"}';

MockClient recording(List<http.Request> requests, String body) =>
    MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(utf8.encode(body), 200);
    });

void main() {
  const from = GeoPoint(21.05, 105.8);
  const to = GeoPoint(21.06, 105.8);

  test('the route decodes the same on every platform', () async {
    final router = GoongRouteProvider(
      apiKey: null,
      client: recording([], routeBody),
    );
    final route = await router.route(from, to);
    expect(route.points, [
      const GeoPoint(21.05, 105.8),
      const GeoPoint(21.06, 105.8),
    ]);
    expect(route.steps.first.roadName, 'Trần Cung');
  });

  test('the default userAgent is null on the web, so no User-Agent header '
      'forces a CORS preflight; elsewhere it names the package', () async {
    final requests = <http.Request>[];
    final router = GoongRouteProvider(
      apiKey: null,
      client: recording(requests, routeBody),
    );
    final search = GoongPlaceSearch(
      apiKey: null,
      client: recording(requests, searchBody),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    expect(requests, hasLength(2));
    for (final r in requests) {
      if (compiledToJs) {
        expect(r.headers.containsKey('User-Agent'), isFalse);
      } else {
        expect(r.headers['User-Agent'], 'navigation_engine_goong/0.1.0');
      }
    }
    if (compiledToJs) {
      expect(router.userAgent, isNull);
      expect(search.userAgent, isNull);
    } else {
      expect(router.userAgent, GoongRouteProvider.defaultUserAgent);
      expect(search.userAgent, GoongPlaceSearch.defaultUserAgent);
    }
  });

  test('an explicit userAgent is sent on every platform', () async {
    final requests = <http.Request>[];
    final router = GoongRouteProvider(
      apiKey: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, routeBody),
    );
    final search = GoongPlaceSearch(
      apiKey: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, searchBody),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    expect(
      [for (final r in requests) r.headers['User-Agent']],
      ['my_app/2.0', 'my_app/2.0'],
    );
  });
}
