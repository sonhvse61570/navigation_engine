import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreMapController;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'maplibre_navigation_view.dart';

/// A complete navigation screen on MapLibre in the style of Mapbox's
/// navigation apps: the map, the route overview, turn-by-turn guidance and
/// the arrival, bound to [flow] and [session]. It is named apart from the
/// Mapbox package's `MapboxStyleNavigation`, so an app can import both.
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
/// The map is a [MapLibreNavigationView] showing [styleString] by day and
/// [nightStyleString] (when set) at night: it attaches itself to [session]
/// and ticks it while on screen; its attribution button and logo stay
/// above the panels. The pieces and the flow binding (the
/// states, the back, the overview padding, the step sheet, the recenter)
/// are a [MapboxStyleFlowScaffold]. The app owns, starts and disposes
/// [session] and [flow].
class MapLibreStyleNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const MapLibreStyleNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    required this.styleString,
    this.nightStyleString,
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
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// The map style by day: a style URL, asset path or style JSON; see
  /// [MapLibreNavigationView.styleString].
  final String styleString;

  /// The map style at night. When null, [styleString] is used at night too.
  /// A switch reloads the style; the route, the vehicle and the route
  /// options are drawn again once it has loaded.
  final String? nightStyleString;

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
  /// [MapLibreNavigationView.puck].
  final Widget puck;

  /// Renders the vehicle marker drawn by the map; see
  /// [MapLibreNavigationView.vehicleImage].
  final VehicleImageBuilder? vehicleImage;

  /// Where the vehicle sits on the screen while followed; see
  /// [MapLibreNavigationView.focus].
  final double focus;

  /// The zoom of the map before the first camera move.
  final double initialZoom;

  /// Called when the map controller is created, after the route overview
  /// is drawn on the new map; see [MapLibreNavigationView.onMapCreated].
  final void Function(MapLibreMapController controller)? onMapCreated;

  @override
  State<MapLibreStyleNavigation> createState() =>
      _MapLibreStyleNavigationState();
}

class _MapLibreStyleNavigationState extends State<MapLibreStyleNavigation> {
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
          builder: (context, bottomInset, _) => MapLibreNavigationView(
            key: _mapKey,
            session: widget.session,
            styleString: widget.styleString,
            nightStyleString: widget.nightStyleString,
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
            onMapCreated: (controller) {
              config.onMapReady();
              widget.onMapCreated?.call(controller);
            },
            // The attribution and the logo keep above the panels.
            bottomInset: bottomInset,
          ),
        ),
  );
}
