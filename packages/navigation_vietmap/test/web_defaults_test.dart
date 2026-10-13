// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:test/test.dart';

/// True under dart2js (the `node` platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

final String routeBody = jsonEncode({
  'code': 'OK',
  'paths': [
    {
      'distance': 1000,
      'time': 120000,
      'points': '_k|`A_zfjSo}@?',
      'instructions': <Object?>[],
    },
  ],
});

MockClient recording(List<http.Request> requests, String body) =>
    MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(utf8.encode(body), 200);
    });

void main() {
  const from = GeoPoint(10.8, 106.7);
  const to = GeoPoint(10.81, 106.7);

  test('the default userAgent is null on the web, so no User-Agent header '
      'forces a CORS preflight; elsewhere it names the package', () async {
    final requests = <http.Request>[];
    final router = VietmapRouteProvider(
      apiKey: null,
      client: recording(requests, routeBody),
    );
    final search = VietmapPlaceSearch(
      apiKey: null,
      client: recording(requests, '[]'),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    for (final r in requests) {
      if (compiledToJs) {
        expect(r.headers.containsKey('User-Agent'), isFalse);
      } else {
        expect(r.headers['User-Agent'], 'navigation_vietmap/0.1.0');
      }
    }
    if (compiledToJs) {
      expect(router.userAgent, isNull);
      expect(search.userAgent, isNull);
    } else {
      expect(router.userAgent, VietmapRouteProvider.defaultUserAgent);
      expect(search.userAgent, VietmapPlaceSearch.defaultUserAgent);
    }
  });

  test('an explicit userAgent is sent on every platform', () async {
    final requests = <http.Request>[];
    final router = VietmapRouteProvider(
      apiKey: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, routeBody),
    );
    final search = VietmapPlaceSearch(
      apiKey: null,
      userAgent: 'my_app/2.0',
      client: recording(requests, '[]'),
    );
    await router.route(from, to);
    await search.autocomplete('phở');
    expect(
      [for (final r in requests) r.headers['User-Agent']],
      ['my_app/2.0', 'my_app/2.0'],
    );
  });
}
