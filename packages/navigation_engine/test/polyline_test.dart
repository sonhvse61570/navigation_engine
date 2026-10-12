// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml): under dart2js, bitwise operators work on unsigned
// 32-bit values, which would turn every negative polyline delta into a huge
// positive one.
@Tags(['js'])
library;

import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void expectPoints(List<GeoPoint> actual, List<(double, double)> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].lat, closeTo(expected[i].$1, 1e-9), reason: 'lat $i');
    expect(actual[i].lng, closeTo(expected[i].$2, 1e-9), reason: 'lng $i');
  }
}

void main() {
  test('the reference vector, at precision 5 by default', () {
    // From the polyline algorithm's documentation.
    const reference = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)];
    expectPoints(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), reference);
    expectPoints(
      decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5),
      reference,
    );
  });

  test('the same points at precision 6', () {
    expectPoints(
      decodePolyline('_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI', precision: 6),
      [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)],
    );
  });

  test('every hemisphere and the largest jumps at precision 5', () {
    expectPoints(
      decodePolyline('b_vmEca|y[bpnC`vf~f@odvyQu~k}EhsofKtquc]_cidP{ngtcA'),
      [
        (-33.86882, 151.20930),
        (-34.60372, -58.38159),
        (64.14660, -21.94260),
        (-0.00001, -179.99999),
        (89.99999, 179.99999),
      ],
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

  test('negative and positive deltas between close points', () {
    // (10.8, 106.7) -> (10.79, 106.69) -> (10.81, 106.68).
    expectPoints(decodePolyline('_k|`A_zfjSn}@n}@_|Bn}@'), [
      (10.8, 106.7),
      (10.79, 106.69),
      (10.81, 106.68),
    ]);
  });

  test('an empty polyline has no points', () {
    expect(decodePolyline(''), isEmpty);
    expect(decodePolyline('', precision: 6), isEmpty);
  });

  test('a character outside the alphabet throws, with its offset', () {
    expect(
      () => decodePolyline('_p~iF ps|U'),
      throwsA(
        isA<FormatException>()
            .having((e) => e.message, 'message', 'invalid polyline character')
            .having((e) => e.offset, 'offset', 5),
      ),
    );
  });

  test('a value cut short throws', () {
    // A latitude without its longitude.
    expect(
      () => decodePolyline('_p~iF'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'the polyline ends inside a value',
        ),
      ),
    );
    // A longitude whose last chunk is missing.
    expect(() => decodePolyline('_p~iF~ps|'), throwsFormatException);
  });

  test('a value too long to be a coordinate throws', () {
    expect(
      () => decodePolyline('~~~~~~~~~'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'a polyline value is too long',
        ),
      ),
    );
  });
}
