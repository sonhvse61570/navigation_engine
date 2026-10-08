import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

// The 256 dp Web Mercator projection, as fractions of the world (0..1).
double worldX(double lng) => (lng + 180) / 360;
double worldY(double lat) {
  final phi = lat * math.pi / 180;
  return (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2;
}

double latOf(double y) =>
    math.atan(_sinh(math.pi * (1 - 2 * y))) * 180 / math.pi;
double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

void main() {
  test('fits a quarter of the world width into 512 dp at zoom 3', () {
    final t = fitCameraToBounds(
      const [GeoPoint(-1, -45), GeoPoint(1, 45)],
      const Size(512, 512),
      EdgeInsets.zero,
    );
    expect(t.zoom, closeTo(3, 1e-6));
    expect(t.position.lat, closeTo(0, 1e-6));
    expect(t.position.lng, closeTo(0, 1e-6));
    expect(t.bearing, 0);
    expect(t.tilt, 0);
  });

  test('a single point uses maxZoom', () {
    final t = fitCameraToBounds(
      const [GeoPoint(10.77, 106.7)],
      const Size(400, 800),
      EdgeInsets.zero,
      maxZoom: 17,
    );
    expect(t.zoom, 17);
    expect(t.position.lat, closeTo(10.77, 1e-9));
  });

  test('bottom padding moves the centre south of the bounds centre', () {
    const pts = [GeoPoint(10.77, 106.69), GeoPoint(10.80, 106.72)];
    final plain = fitCameraToBounds(pts, const Size(400, 800), EdgeInsets.zero);
    final padded = fitCameraToBounds(
      pts,
      const Size(400, 800),
      const EdgeInsets.only(bottom: 300),
    );
    expect(padded.zoom, lessThanOrEqualTo(plain.zoom));
    expect(padded.position.lat, lessThan(plain.position.lat));
    expect(padded.position.lng, closeTo(plain.position.lng, 1e-9));
  });

  test('zoom is clamped and padding larger than the view does not throw', () {
    final t = fitCameraToBounds(
      const [GeoPoint(10, 106), GeoPoint(10.00001, 106.00001)],
      const Size(400, 800),
      const EdgeInsets.all(500),
      maxZoom: 18,
      minZoom: 2,
    );
    expect(t.zoom, inInclusiveRange(2, 18));
    expect(t.zoom.isFinite, isTrue);
    expect(math.log(2), isPositive); // keeps the math import used
  });

  test('the map padding shifts the target by half of it', () {
    // GoogleMap.padding top 320 puts the camera target at y = 560 of an
    // 800 dp view; the bounds centre must still show at y = 400, 160 dp
    // above the target, so the target is 160 dp south of the bounds centre.
    const pts = [GeoPoint(10.77, 106.69), GeoPoint(10.80, 106.72)];
    const view = Size(400, 800);
    final plain = fitCameraToBounds(pts, view, EdgeInsets.zero);
    final t = fitCameraToBounds(
      pts,
      view,
      EdgeInsets.zero,
      mapPadding: const EdgeInsets.only(top: 320),
    );
    expect(t.zoom, plain.zoom, reason: 'the zoom ignores the map padding');
    final world = 256 * math.pow(2, t.zoom);
    final centreY = (worldY(10.77) + worldY(10.80)) / 2;
    expect(t.position.lat, closeTo(latOf(centreY + 160 / world), 1e-9));
    expect(t.position.lat, lessThan(plain.position.lat));
    expect(t.position.lng, closeTo(plain.position.lng, 1e-9));
  });

  test('left padding moves the target west by half of it', () {
    const point = GeoPoint(10.77, 106.7);
    final t = fitCameraToBounds(
      const [point],
      const Size(400, 800),
      const EdgeInsets.only(left: 100),
    );
    expect(t.zoom, 18);
    final world = 256 * math.pow(2, t.zoom);
    expect(t.position.lng, closeTo(point.lng - 50 / world * 360, 1e-9));
    expect(t.position.lat, closeTo(point.lat, 1e-9));
  });

  test('map padding and overview padding that match cancel out', () {
    const pts = [GeoPoint(10.77, 106.69), GeoPoint(10.80, 106.72)];
    const padding = EdgeInsets.fromLTRB(10, 300, 30, 50);
    final t = fitCameraToBounds(
      pts,
      const Size(400, 800),
      padding,
      mapPadding: padding,
    );
    expect(
      t.position.lat,
      closeTo(latOf((worldY(10.77) + worldY(10.80)) / 2), 1e-9),
    );
    expect(t.position.lng, closeTo((106.69 + 106.72) / 2, 1e-9));
  });
}
