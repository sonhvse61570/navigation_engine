import 'dart:math' as math;

import 'geo_point.dart';

/// Metres per degree of latitude.
const mPerDegLat = 110540.0;

/// Metres per degree of longitude at the equator.
const _mPerDegLngEquator = 111320.0;

/// Metres per degree of longitude at latitude [lat].
double metresPerDegLng(double lat) =>
    math.cos(lat * math.pi / 180) * _mPerDegLngEquator;

double hypot(double x, double y) => math.sqrt(x * x + y * y);

/// Heading (degrees clockwise from north) of the planar vector
/// ([dx] east, [dy] north).
double bearingOf(double dx, double dy) =>
    (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;

/// Metres between two points (equirectangular; fine below a few km).
double distanceBetween(GeoPoint a, GeoPoint b) {
  final k = metresPerDegLng((a.lat + b.lat) / 2);
  return hypot((b.lng - a.lng) * k, (b.lat - a.lat) * mPerDegLat);
}

/// Heading (degrees clockwise from north) from [a] to [b].
double bearingBetween(GeoPoint a, GeoPoint b) {
  final k = metresPerDegLng((a.lat + b.lat) / 2);
  return bearingOf((b.lng - a.lng) * k, (b.lat - a.lat) * mPerDegLat);
}

/// [p] moved [metres] towards [bearing] (degrees clockwise from north).
GeoPoint offsetPoint(GeoPoint p, double bearing, double metres) {
  final b = bearing * math.pi / 180;
  return GeoPoint(
    p.lat + metres * math.cos(b) / mPerDegLat,
    p.lng + metres * math.sin(b) / metresPerDegLng(p.lat),
  );
}

/// Signed shortest rotation from [from] to [to] (degrees), in (-180, 180].
double angleDelta(double from, double to) {
  final d = (to - from) % 360;
  return d > 180 ? d - 360 : d;
}
