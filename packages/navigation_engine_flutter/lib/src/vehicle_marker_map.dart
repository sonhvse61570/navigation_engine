import 'package:navigation_engine/navigation_engine.dart';

/// A map that can draw the vehicle as one of its own markers.
///
/// While the camera follows the vehicle, `NavigationMapFrame` paints the
/// vehicle as a fixed Flutter widget over the map. Once the user pans away it
/// asks the map to draw the vehicle instead, so the vehicle stays where it is
/// on the map. Map adapters implement this next to `NavigationMap`.
abstract interface class VehicleMarkerMap {
  /// Draws (or moves) the vehicle marker at [position], rotated to [bearing]
  /// (degrees clockwise from north).
  void showVehicle(GeoPoint position, double bearing);

  /// Removes the vehicle marker.
  void hideVehicle();
}
