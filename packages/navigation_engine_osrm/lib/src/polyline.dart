import 'dart:math' as math;

import 'package:navigation_engine/navigation_engine.dart';

/// Decodes an encoded polyline (Google's algorithm, as OSRM sends with
/// `geometries=polyline` or `polyline6`) with [precision] decimals.
///
/// Throws [FormatException] for a character outside the alphabet, a value
/// cut short (a latitude without its longitude included).
List<GeoPoint> decodePolyline(String encoded, {required int precision}) {
  final factor = math.pow(10, precision).toDouble();
  final points = <GeoPoint>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int next() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (index >= encoded.length) {
        throw FormatException('the polyline ends inside a value', encoded);
      }
      final b = encoded.codeUnitAt(index) - 63;
      if (b < 0 || b > 63) {
        throw FormatException('invalid polyline character', encoded, index);
      }
      index++;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
      if (shift >= 35) {
        throw FormatException('a polyline value is too long', encoded, index);
      }
    }
    // Not `~(result >> 1)`: under dart2js `~` works on unsigned 32-bit
    // values, so every negative delta would come out huge and positive.
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    lng += next(); // a latitude without its longitude ends inside a value
    points.add(GeoPoint(lat / factor, lng / factor));
  }
  return points;
}
