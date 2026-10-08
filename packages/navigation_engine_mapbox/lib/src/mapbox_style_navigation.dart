import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show MapboxMap, MapboxStyles;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'mapbox_navigation_view.dart';

/// Shows [view] itself: the default [MapboxStyleNavigation.mapViewBuilder].
Widget _showView(BuildContext context, MapboxNavigationView view) => view;

/// A complete navigation screen on Mapbox in the style of Mapbox's
/// navigation apps: the map, the route overview, turn-by-turn guidance and
/// the arrival, bound to [flow] and [session]. The UI is inspired by those
/// apps; it is not an official Mapbox product.
///
/// It shows, per [NavigationFlowController.state]:
/// - idle: [idleBuilder]'s overlay, or nothing;
/// - loading, overview, error: [MapboxStyleRoutePanel] at the bottom;
/// - navigating: [MapboxStyleManeuverBanner] at the top (once there is
///   guidance), [MapboxStyleSpeedLimit] at the bottom start,
///   [MapboxStyleTripProgress] at the bottom, and
///   [MapboxStyleRecenterButton] at the bottom end once the user has moved
///   the map;
/// - arrived: [MapboxStyleArrivalPanel].
///
/// [dayColors] / [nightColors] reach the panels, the banner, the route
/// lines and the route option labels. [dayRouteColors] / [nightRouteColors]
/// override the selected option and the session's route line; the other
/// options use [MapboxStyleColors.alternative].
///
/// The map is a [MapboxNavigationView] showing [styleUri]. At night the
/// [MapboxStyles.STANDARD] style switches to its `night` light preset (no
/// reload); another style loads [nightStyleUri] when it is set. The view
/// attaches itself to [session] and ticks it while on screen; its logo and
/// attribution button stay above the panels. Call
/// `MapboxOptions.setAccessToken(...)` before building it. The pieces and
/// the flow binding (the states, the back, the overview padding, the step
/// sheet, the recenter) are a [MapboxStyleFlowScaffold]. The app owns,
/// starts and disposes [session] and [flow].
class MapboxStyleNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const MapboxStyleNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    this.styleUri = MapboxStyles.STANDARD,
    this.nightStyleUri,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors = MapboxStyleColors.day,
    this.nightColors = MapboxStyleColors.night,
    this.speedLimitSign = SpeedLimitSign.circular,
    this.idleBuilder,
    this.onEnd,
    this.dayRouteColors,
    this.nightRouteColors,
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.focus = 0.7,
    this.initialZoom = 17,
    this.onMapCreated,
    @visibleForTesting this.mapViewBuilder = _showView,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// The map style; see [MapboxNavigationView.styleUri]. On
  /// [MapboxStyles.STANDARD] night is the style's `night` light preset.
  final String styleUri;

  /// The style loaded at night, for styles other than
  /// [MapboxStyles.STANDARD]; see [MapboxNavigationView.nightStyleUri].
  /// When null, [styleUri] is kept at night.
  final String? nightStyleUri;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  final MapboxStyleColors dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  final MapboxStyleColors nightColors;

  /// The shape of the speed limit sign.
  final SpeedLimitSign speedLimitSign;

  /// Builds the overlay shown while the flow is idle, such as a search bar;
  /// it fills the screen above the map. Nothing is shown when null.
  final WidgetBuilder? idleBuilder;

  /// Called by the end button and by the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// The route line colours by day. When null they come from [dayColors]:
  /// `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? dayRouteColors;

  /// The route line colours at night. When null they come from
  /// [nightColors]: `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? nightRouteColors;

  /// The vehicle while the camera follows it; see
  /// [MapboxNavigationView.puck].
  final Widget puck;

  /// Renders the vehicle marker drawn by the map; see
  /// [MapboxNavigationView.vehicleImage].
  final VehicleImageBuilder? vehicleImage;

  /// Where the vehicle sits on the screen while followed; see
  /// [MapboxNavigationView.focus].
  final double focus;

  /// The zoom of the map before the first camera move.
  final double initialZoom;

  /// Called when the map is created, after the route overview is drawn on
  /// the new map; see [MapboxNavigationView.onMapCreated].
  final void Function(MapboxMap map)? onMapCreated;

  /// Builds the map from the [MapboxNavigationView] the screen would show;
  /// by default it shows that view. Widget tests, where the Mapbox map
  /// cannot be created, replace it with a stand-in for the view.
  final Widget Function(BuildContext context, MapboxNavigationView view)
  mapViewBuilder;

  @override
  State<MapboxStyleNavigation> createState() => _MapboxStyleNavigationState();
}

class _MapboxStyleNavigationState extends State<MapboxStyleNavigation> {
  /// Keeps the map view, and so the platform map, across rebuilds.
  final _mapKey = GlobalKey();

  @override
  Widget build(BuildContext context) => MapboxStyleFlowScaffold(
    session: widget.session,
    flow: widget.flow,
    formatter: widget.formatter,
    strings: widget.strings,
    dayColors: widget.dayColors,
    nightColors: widget.nightColors,
    dayRouteColors: widget.dayRouteColors,
    nightRouteColors: widget.nightRouteColors,
    speedLimitSign: widget.speedLimitSign,
    idleBuilder: widget.idleBuilder,
    onEnd: widget.onEnd,
    mapBuilder: (context, config, colors, routeColors, routeLabel) =>
        ValueListenableBuilder<double>(
          valueListenable: config.bottomOverlayHeight,
          builder: (context, bottomInset, _) => widget.mapViewBuilder(
            context,
            MapboxNavigationView(
              key: _mapKey,
              session: widget.session,
              styleUri: widget.styleUri,
              nightStyleUri: widget.nightStyleUri,
              night: config.isNight,
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              routeColors: routeColors,
              puck: widget.puck,
              vehicleImage: widget.vehicleImage,
              focus: widget.focus,
              // The scaffold shows the recenter button.
              recenterButton: (_) => const SizedBox.shrink(),
              routeLabel: routeLabel,
              onRouteOptionTap: config.onRouteOptionTap,
              labelColors: colors.routeLabelColors,
              alternativeRouteColor: colors.alternative,
              // Nullable so that the widget tests' stand-in view, which has
              // no MapboxMap, can call it; the app gets only a real map.
              onMapCreated: (MapboxMap? map) {
                config.onMapReady();
                if (map != null) widget.onMapCreated?.call(map);
              },
              // The logo and the attribution keep above the panels.
              bottomInset: bottomInset,
            ),
          ),
        ),
  );
}
