import '../flow/alternate_route.dart';
import 'map_default_colors.dart';
import 'mapbox_style/mapbox_style_colors.dart';
import 'navigation_strings.dart';
import 'route_label.dart';

/// The text of the bubble on [alternate] in [strings], from its time
/// difference rounded to whole minutes ([AlternateRoute.minutesDelta]):
/// [NavigationStrings.minFaster] when it is sooner ("2 min faster"),
/// [NavigationStrings.minSlower] when it is later ("+3 min"), else
/// [NavigationStrings.similarEta].
///
/// The drop-ins pass it (with their strings) as the views' `alternateLabel`;
/// an app that builds its own screen can do the same.
String alternateRouteLabel(
  AlternateRoute alternate,
  NavigationStrings strings,
) {
  final m = alternate.minutesDelta;
  return m < 0
      ? strings.minFaster(-m)
      : m > 0
      ? strings.minSlower(m)
      : strings.similarEta;
}

/// The bubble colours of a faster and of a slower alternate route in the
/// Mapbox-style colours [c]: the text in the accent (`faster`) or in the
/// muted text colour (`slower`), on the surface, with a faint border.
///
/// The Mapbox-style drop-ins of the MapLibre, flutter_map and Mapbox
/// adapters pass them as the views' `fasterLabelColors` and
/// `slowerLabelColors`; every map starts with the ones of
/// [MapboxStyleColors.day] ([MapDefaultColors]).
({RouteLabelColors faster, RouteLabelColors slower}) alternateLabelColorsOf(
  MapboxStyleColors c,
) => (
  faster: RouteLabelColors(
    fill: c.surface,
    text: c.accent,
    border: c.onSurface.withAlpha(0x33),
  ),
  slower: RouteLabelColors(
    fill: c.surface,
    text: c.onSurfaceVariant,
    border: c.onSurface.withAlpha(0x33),
  ),
);
