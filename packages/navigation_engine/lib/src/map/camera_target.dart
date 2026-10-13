import '../geo/geo_point.dart';

/// Where a map camera should be, in renderer-neutral terms.
///
/// [zoom] is a web-mercator zoom level, as used by Google Maps, Mapbox and
/// flutter_map alike.
final class CameraTarget {
  /// Creates a target at [position] with the given [bearing], [zoom] and
  /// [tilt].
  const CameraTarget({
    required this.position,
    required this.bearing,
    required this.zoom,
    required this.tilt,
  });

  /// The point the camera is centred on.
  final GeoPoint position;

  /// Degrees clockwise from north; the map is rotated so it points up.
  final double bearing;

  /// The web-mercator zoom level; higher is closer.
  final double zoom;

  /// Degrees from looking straight down. Renderers without tilt ignore it.
  final double tilt;
}
