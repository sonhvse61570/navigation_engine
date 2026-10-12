import 'package:navigation_engine/navigation_engine.dart';

/// Decodes an encoded polyline with five decimals (Google's algorithm, as
/// Goong's direction v2 sends it in each step's `polyline.points`), with
/// the core's JS-safe [decodePolyline].
///
/// Throws [FormatException] for a character outside the alphabet, a value
/// cut short (a latitude without its longitude included) or a value too
/// long to be a coordinate.
List<GeoPoint> decodePolyline5(String encoded) =>
    decodePolyline(encoded, precision: 5);
