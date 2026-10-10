// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';
import 'package:test/test.dart';

/// True under dart2js (the `node` platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

final String body = jsonEncode({
  'code': 'Ok',
  'routes': [
    {
      'distance': 1000,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [106.7, 10.8],
          [106.7, 10.809],
        ],
      },
      'legs': [
        {'steps': <Object?>[], 'summary': ''},
      ],
    },
  ],
});

({OsrmRouteProvider provider, List<http.Request> requests}) serve({
  String? userAgent,
  bool passUserAgent = false,
}) {
  final requests = <http.Request>[];
  final client = MockClient((req) async {
    requests.add(req);
    return http.Response.bytes(utf8.encode(body), 200);
  });
  return (
    provider: passUserAgent
        ? OsrmRouteProvider(client: client, userAgent: userAgent)
        : OsrmRouteProvider(client: client),
    requests: requests,
  );
}

void main() {
  const from = GeoPoint(10.8, 106.7);
  const to = GeoPoint(10.809, 106.7);

  test('the default userAgent is null on the web, so no User-Agent header '
      'forces a CORS preflight; elsewhere it names the package', () async {
    final s = serve();
    await s.provider.route(from, to);
    final headers = s.requests.single.headers;
    if (compiledToJs) {
      expect(s.provider.userAgent, isNull);
      expect(headers.containsKey('User-Agent'), isFalse);
    } else {
      expect(s.provider.userAgent, OsrmRouteProvider.defaultUserAgent);
      expect(headers['User-Agent'], OsrmRouteProvider.defaultUserAgent);
    }
  });

  test('an explicit userAgent is sent on every platform', () async {
    final s = serve(userAgent: 'my_app/2.0', passUserAgent: true);
    await s.provider.route(from, to);
    expect(s.requests.single.headers['User-Agent'], 'my_app/2.0');
  });
}
