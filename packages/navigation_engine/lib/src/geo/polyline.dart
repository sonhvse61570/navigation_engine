import 'dart:math' as math;

import 'geo_point.dart';

/// Decodes an encoded polyline (Google's polyline algorithm) whose
/// coordinates have [precision] decimals: 5 by default, as Google, Goong
/// and Vietmap send them; 6 for OSRM's and Mapbox's `polyline6`.
///
/// ```dart
/// decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
/// // [GeoPoint(38.5, -120.2), GeoPoint(40.7, -120.95),
/// //  GeoPoint(43.252, -126.453)]
/// ```
///
/// It is safe on the web: under dart2js, where bitwise operators work on
/// 32-bit values, negative coordinates and large jumps decode as on the VM.
/// An empty string has no points.
///
/// Throws [FormatException] for a character outside the alphabet (with its
/// offset), a value cut short (a latitude without its longitude included)
/// or a value too long to be a coordinate.
List<GeoPoint> decodePolyline(String encoded, {int precision = 5}) {
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
