import 'package:flutter/foundation.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../flow/alternate_route.dart';
import '../../flow/navigation_map_config.dart';
import '../../route_colors.dart';
import 'google_style_colors.dart';

/// What a `GoogleStyleFlowScaffold` asks of the map it builds, beyond the
/// [NavigationMapConfig]: the layers the trip sheet's menu switches, where
/// the camera keeps the vehicle across the map, how much of the map's
/// bottom the screen covers, and the look of the moment.
///
/// The scaffold builds a new value whenever one of them changes; a map
/// applies them all on every build.
@immutable
final class GoogleStyleMapLayers {
  /// Creates the map layers.
  const GoogleStyleMapLayers({
    this.traffic = false,
    this.satellite = false,
    this.horizontalFocus = 0.5,
    this.bottomOverlay = 0,
    this.colors = GoogleStyleColors.day,
    this.routeColors = const RouteColors(),
    this.routeLabel,
    this.alternateLabel,
  });

  /// Whether the map shows the traffic layer (the menu's traffic switch).
  final bool traffic;

  /// Whether the map shows satellite imagery with roads and labels (the
  /// menu's satellite switch).
  final bool satellite;

  /// Where the followed vehicle sits across the map, as a fraction of its
  /// width from the left: 0.5 is the centre, and beside a landscape side
  /// panel it is the middle of the map area left uncovered (mirrored on a
  /// right-to-left screen). It is physical, not directional.
  final double horizontalFocus;

  /// How much of the map's bottom the screen covers, in logical pixels: the
  /// scaffold's [NavigationMapConfig.bottomOverlayHeight], held at the
  /// collapsed trip sheet's while the sheet is dragged, settles or stays
  /// open, so that neither the camera's focus nor the map's padding moves
  /// with it. A map keeps its logo and attribution above it.
  final double bottomOverlay;

  /// The colours of the moment (day or night): the map draws its alternate
  /// lines and route bubbles with them. [GoogleStyleColors] has no `==`, so
  /// layers are equal on this field only when it is the same instance (the
  /// scaffold passes its `dayColors` or `nightColors`).
  final GoogleStyleColors colors;

  /// The route line colours of the moment.
  final RouteColors routeColors;

  /// The text of a route option's bubble in the overview, such as its
  /// duration; null draws none.
  final String Function(NavRoute route)? routeLabel;

  /// The text of an alternate route's bubble while navigating, such as
  /// "2 min faster"; null draws none.
  final String Function(AlternateRoute alternate)? alternateLabel;

  @override
  bool operator ==(Object other) =>
      other is GoogleStyleMapLayers &&
      other.traffic == traffic &&
      other.satellite == satellite &&
      other.horizontalFocus == horizontalFocus &&
      other.bottomOverlay == bottomOverlay &&
      other.colors == colors &&
      other.routeColors.driven == routeColors.driven &&
      other.routeColors.ahead == routeColors.ahead &&
      other.routeColors.drivenWidth == routeColors.drivenWidth &&
      other.routeColors.aheadWidth == routeColors.aheadWidth &&
      other.routeLabel == routeLabel &&
      other.alternateLabel == alternateLabel;

  @override
  int get hashCode => Object.hash(
    traffic,
    satellite,
    horizontalFocus,
    bottomOverlay,
    colors,
    routeColors.driven,
    routeColors.ahead,
    routeColors.drivenWidth,
    routeColors.aheadWidth,
    routeLabel,
    alternateLabel,
  );

  @override
  String toString() =>
      'GoogleStyleMapLayers(traffic: $traffic, satellite: $satellite, '
      'horizontalFocus: $horizontalFocus, bottomOverlay: $bottomOverlay, '
      'colors: $colors, routeColors: (driven: ${routeColors.driven}, '
      'ahead: ${routeColors.ahead}, drivenWidth: ${routeColors.drivenWidth}, '
      'aheadWidth: ${routeColors.aheadWidth}), routeLabel: $routeLabel, '
      'alternateLabel: $alternateLabel)';
}
