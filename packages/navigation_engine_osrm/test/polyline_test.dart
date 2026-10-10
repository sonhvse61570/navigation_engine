// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml):
// under dart2js, bitwise operators work on unsigned 32-bit values, which
// once turned every negative polyline delta into a huge positive one.
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';
import 'package:navigation_engine_osrm/src/polyline.dart';
import 'package:test/test.dart';

void expectPoints(List<GeoPoint> actual, List<(double, double)> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].lat, closeTo(expected[i].$1, 1e-9), reason: 'lat $i');
    expect(actual[i].lng, closeTo(expected[i].$2, 1e-9), reason: 'lng $i');
  }
}

void main() {
  test('the reference vector at precision 5', () {
    // From the polyline algorithm's documentation.
    expectPoints(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5), [
      (38.5, -120.2),
      (40.7, -120.95),
      (43.252, -126.453),
    ]);
  });

  test('the same points at precision 6', () {
    expectPoints(
      decodePolyline('_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI', precision: 6),
      [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)],
    );
  });

  test('every hemisphere and the largest jumps at precision 6', () {
    expectPoints(
      decodePolyline(
        'f`er_A_tal_Hjjzk@nelwnKcvfj{D_|`odApiejyBlz`nlH_gdtjD{~ssmT',
        precision: 6,
      ),
      [
        (-33.868820, 151.209296),
        (-34.603722, -58.381592),
        (64.146600, -21.942600),
        (-0.000001, -179.999999),
        (89.999999, 179.999999),
      ],
    );
  });

  test('a polyline6 route through the provider', () async {
    final body = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 3000,
          // (10.8, 106.7) -> (10.79, 106.69) -> (10.81, 106.68): negative
          // and positive deltas.
          'geometry': '_wdrS_mmojE~oR~oR_af@~oR',
          'legs': [
            {'steps': <Object?>[], 'summary': ''},
          ],
        },
      ],
    });
    final provider = OsrmRouteProvider(
      geometries: OsrmGeometries.polyline6,
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode(body), 200),
      ),
    );
    final route = await provider.route(
      const GeoPoint(10.8, 106.7),
      const GeoPoint(10.81, 106.68),
    );
    expectPoints(route.points, [
      (10.8, 106.7),
      (10.79, 106.69),
      (10.81, 106.68),
    ]);
  });
}
