import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// What a [NavigationFlowScaffold] gives the map it builds: the look of the
/// moment and the callbacks the map calls back into the flow.
///
/// The scaffold builds the map only when the flow's state or night mode
/// changes, never for progress ticks.
final class NavigationMapConfig {
  /// Creates a map config.
  const NavigationMapConfig({
    required this.isNight,
    required this.onRouteOptionTap,
    required this.onMapReady,
    required this.bottomOverlayHeight,
    this.startOverlayWidth = const AlwaysStoppedAnimation<double>(0),
  });

  /// Whether the map should use its night style.
  final bool isNight;

  /// Call with the index of the route option the user tapped on the map. It
  /// selects that route in the overview and does nothing in other states.
  final void Function(int index) onRouteOptionTap;

  /// Call once the map SDK's map exists (for example from its "map created"
  /// callback): the overview is drawn and fitted on the new map.
  final VoidCallback onMapReady;

  /// The height of what the screen shows over the bottom of the map: the
  /// panel, the trip footer or the arrival panel, whichever shows, plus the
  /// speed's band (the speed and its gap) while the speed shows above the
  /// footer; 0 when nothing does. It changes without a new config. A map
  /// keeps its own attribution and logo above it, as map providers' terms
  /// require them to stay visible.
  final ValueListenable<double> bottomOverlayHeight;

  /// The width of what covers the start side of the map (a landscape side
  /// panel, with its margins and the start inset); 0 when nothing does. It
  /// changes without a new config. A map shifts its follow focus to the
  /// middle of the rest.
  final ValueListenable<double> startOverlayWidth;
}
