import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  test('GeoPoint has value equality', () {
    expect(const GeoPoint(10.5, 106.7), const GeoPoint(10.5, 106.7));
    expect(
      const GeoPoint(10.5, 106.7).hashCode,
      const GeoPoint(10.5, 106.7).hashCode,
    );
    expect(const GeoPoint(10.5, 106.7), isNot(const GeoPoint(10.5, 106.8)));
    expect(const GeoPoint(1, 2).toString(), 'GeoPoint(1.0, 2.0)');
  });

  test('distanceBetween: 0.001 degrees of latitude is ~110.5 m', () {
    expect(
      distanceBetween(const GeoPoint(10, 106), const GeoPoint(10.001, 106)),
      closeTo(110.54, 0.01),
    );
  });

  test('bearingBetween: north is 0, east is 90', () {
    const o = GeoPoint(10, 106);
    expect(bearingBetween(o, const GeoPoint(10.001, 106)), closeTo(0, 1e-9));
    expect(bearingBetween(o, const GeoPoint(10, 106.001)), closeTo(90, 1e-9));
  });

  test('offsetPoint round-trips through distance and bearing', () {
    const o = GeoPoint(10.77, 106.69);
    final p = offsetPoint(o, 37, 250);
    expect(distanceBetween(o, p), closeTo(250, 0.5));
    expect(bearingBetween(o, p), closeTo(37, 0.1));
  });

  test('angleDelta takes the short way round', () {
    expect(angleDelta(350, 10), closeTo(20, 1e-9));
    expect(angleDelta(10, 350), closeTo(-20, 1e-9));
    expect(angleDelta(0, 180), closeTo(180, 1e-9));
  });
}
