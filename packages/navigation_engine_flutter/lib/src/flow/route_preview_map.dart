import 'package:flutter/widgets.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// A [NavigationMap] that can show route options for an overview. Map
/// adapters implement it; a [NavigationFlowController] uses it when the
/// session's map is one, and works without it.
abstract interface class RoutePreviewMap {
  /// Draws [routes], [selected] highlighted and the others muted.
  void showRouteOptions(List<NavRoute> routes, int selected);

  /// Removes what [showRouteOptions] drew.
  void clearRouteOptions();

  /// Moves the camera so all of [routes] fit inside [padding].
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding);
}
