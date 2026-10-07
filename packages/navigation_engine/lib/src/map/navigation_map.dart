import '../geo/geo_point.dart';
import 'camera_target.dart';

/// The map a `NavigationSession` draws on. Implement it once per map
/// renderer (Google Maps, Mapbox, flutter_map, …); the session never touches
/// renderer types.
abstract interface class NavigationMap {
  /// Puts the camera at [target] immediately (no animation: the session
  /// animates by calling this every frame). Completes when the renderer has
  /// applied it; the session sends the next update only after that.
  Future<void> moveCamera(CameraTarget target);

  /// Draws the route: the part already driven and the part still ahead
  /// (they share their junction point).
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead);

  /// Removes the route line.
  void clearRoute();
}
