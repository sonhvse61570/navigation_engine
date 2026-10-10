import 'dart:ui';

import 'alternate_route_labels.dart';
import 'mapbox_style/mapbox_style_colors.dart';
import 'route_label.dart';

/// The colours every bundled map view (Google Maps, MapLibre, flutter_map,
/// Mapbox) gives what an app leaves unset, so a view looks the same on any
/// adapter: the route option labels, the bubbles of faster and slower
/// alternate routes, the alternate lines and the search pins.
///
/// They are day colours. The drop-ins pass their own theme's colours, day
/// and night; an app that builds a view itself passes `labelColors`,
/// `alternateColor`, `fasterLabelColors`, `slowerLabelColors` and
/// `searchPinColor` to follow its theme and night mode.
abstract final class MapDefaultColors {
  /// The route option labels: the [RouteLabelColors] defaults (a blue
  /// selected bubble, white ones with dark text).
  static const RouteLabelColors routeLabels = RouteLabelColors();

  /// The bubble of a faster alternate: the accent text of
  /// [MapboxStyleColors.day] ([alternateLabelColorsOf]).
  static final RouteLabelColors fasterLabels = alternateLabelColorsOf(
    MapboxStyleColors.day,
  ).faster;

  /// The bubble of a slower (or as fast) alternate: the muted text of
  /// [MapboxStyleColors.day] ([alternateLabelColorsOf]).
  static final RouteLabelColors slowerLabels = alternateLabelColorsOf(
    MapboxStyleColors.day,
  ).slower;

  /// The alternate route lines: grey.
  static const Color alternate = Color(0xFF9AA0A6);

  /// The search pins: the warning red of [MapboxStyleColors.day].
  static final Color searchPin = MapboxStyleColors.day.warning;
}
