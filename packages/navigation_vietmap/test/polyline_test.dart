// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml): under dart2js, bitwise operators work on unsigned
// 32-bit values, which would turn every negative polyline delta into a huge
// positive one.
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:navigation_vietmap/src/polyline.dart';
import 'package:test/test.dart';

void expectPoints(List<GeoPoint> actual, List<(double, double)> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].lat, closeTo(expected[i].$1, 1e-9), reason: 'lat $i');
    expect(actual[i].lng, closeTo(expected[i].$2, 1e-9), reason: 'lng $i');
  }
}

void main() {
  test('the reference vector', () {
    // From the polyline algorithm's documentation.
    expectPoints(decodePolyline5('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), [
      (38.5, -120.2),
      (40.7, -120.95),
      (43.252, -126.453),
    ]);
  });

  test('every hemisphere and the largest jumps', () {
    expectPoints(
      decodePolyline5('b_vmEca|y[bpnC`vf~f@odvyQu~k}EhsofKtquc]_cidP{ngtcA'),
      [
        (-33.86882, 151.20930),
        (-34.60372, -58.38159),
        (64.14660, -21.94260),
        (-0.00001, -179.99999),
        (89.99999, 179.99999),
      ],
    );
  });

  test('an empty polyline has no points', () {
    expect(decodePolyline5(''), isEmpty);
  });

  test('a character outside the alphabet, or a value cut short, throws', () {
    expect(() => decodePolyline5('_p~iF ps|U'), throwsFormatException);
    expect(() => decodePolyline5('_p~iF'), throwsFormatException);
    expect(() => decodePolyline5('_p~iF~ps|'), throwsFormatException);
    expect(() => decodePolyline5('~~~~~~~~~'), throwsFormatException);
  });

  test('a route through the provider', () async {
    final body = jsonEncode({
      'code': 'OK',
      'paths': [
        {
          'distance': 3000,
          'time': 0,
          // (10.8, 106.7) -> (10.79, 106.69) -> (10.81, 106.68): negative
          // and positive deltas.
          'points': '_k|`A_zfjSn}@n}@_|Bn}@',
          'instructions': <Object?>[],
        },
      ],
    });
    final provider = VietmapRouteProvider(
      apiKey: null,
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
