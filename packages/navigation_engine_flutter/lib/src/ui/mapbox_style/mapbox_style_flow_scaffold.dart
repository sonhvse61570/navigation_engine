import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../flow/navigation_flow_controller.dart';
import '../../flow/navigation_flow_scaffold.dart';
import '../../flow/navigation_flow_state.dart';
import '../../flow/navigation_map_config.dart';
import '../../route_colors.dart';
import '../navigation_strings.dart';
import '../speed_limit_sign.dart';
import 'mapbox_style_arrival_panel.dart';
import 'mapbox_style_colors.dart';
import 'mapbox_style_maneuver_banner.dart';
import 'mapbox_style_recenter_button.dart';
import 'mapbox_style_route_panel.dart';
import 'mapbox_style_speed_limit.dart';
import 'mapbox_style_step_list.dart';
import 'mapbox_style_trip_progress.dart';

/// A [NavigationFlowScaffold] dressed with the Mapbox-style pieces: the
/// navigation screen of the adapters' Mapbox-style drop-ins, without the
/// map, which [mapBuilder] provides.
///
/// It shows, per [NavigationFlowController.state]:
/// - idle: [idleBuilder]'s overlay, or nothing;
/// - loading, overview, error: [MapboxStyleRoutePanel] at the bottom (Steps
///   only in the overview, Retry only in an error);
/// - navigating: [MapboxStyleManeuverBanner] at the top (once there is
///   guidance), [MapboxStyleSpeedLimit] at the bottom start,
///   [MapboxStyleTripProgress] at the bottom (end, steps and overview
///   buttons), and [MapboxStyleRecenterButton] at the bottom end once the
///   user has moved the map: beside the speed, or above it when the two
///   would share a row (see [NavigationFlowScaffold.recenterAlignment]);
/// - arrived: [MapboxStyleArrivalPanel];
/// - the step sheet: [MapboxStyleStepList] on the colours' surface.
///
/// The pieces use [dayColors] or [nightColors] as
/// [NavigationFlowController.isNight] says. [mapBuilder] gets the colours of
/// the moment, the route line colours ([dayRouteColors] / [nightRouteColors],
/// or `RouteColors(driven: alternative, ahead: accent)` of the colours) and
/// the route option labels' text (the route's duration through
/// [formatter]). The map should turn its own recenter button off and call
/// [NavigationMapConfig.onMapReady] once it is ready.
///
/// The app owns, starts and disposes [session] and [flow].
class MapboxStyleFlowScaffold extends StatelessWidget {
  /// Creates the Mapbox-style screen of [flow] on [session].
  const MapboxStyleFlowScaffold({
    super.key,
    required this.session,
    required this.flow,
    required this.mapBuilder,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors = MapboxStyleColors.day,
    this.nightColors = MapboxStyleColors.night,
    this.dayRouteColors,
    this.nightRouteColors,
    this.speedLimitSign = SpeedLimitSign.circular,
    this.idleBuilder,
    this.onEnd,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Builds the map, which fills the screen under the pieces, with the
  /// colours, the route line colours and the route label text of the
  /// moment. It is built again only when the state or the night mode
  /// changes (see [NavigationFlowScaffold.mapBuilder]).
  final Widget Function(
    BuildContext context,
    NavigationMapConfig config,
    MapboxStyleColors colors,
    RouteColors routeColors,
    String Function(NavRoute route) routeLabel,
  )
  mapBuilder;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  final MapboxStyleColors dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  final MapboxStyleColors nightColors;

  /// The route line colours by day. When null they come from [dayColors]:
  /// `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? dayRouteColors;

  /// The route line colours at night. When null they come from
  /// [nightColors]: `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? nightRouteColors;

  /// The shape of the speed limit sign.
  final SpeedLimitSign speedLimitSign;

  /// Builds the overlay shown while the flow is idle, such as a search bar;
  /// it fills the screen above the map. Nothing is shown when null.
  final WidgetBuilder? idleBuilder;

  /// Called by the end button and by the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  MapboxStyleColors _colorsAt(bool night) => night ? nightColors : dayColors;

  /// The colours of the moment: the scaffold rebuilds the pieces when the
  /// night mode changes.
  MapboxStyleColors get _colors => _colorsAt(flow.isNight.value);

  String _routeLabel(NavRoute route) =>
      formatter.duration(Duration(seconds: route.duration.round()));

  Widget _map(BuildContext context, NavigationMapConfig config) {
    final night = config.isNight;
    final colors = _colorsAt(night);
    final routeColors =
        (night ? nightRouteColors : dayRouteColors) ??
        RouteColors(driven: colors.alternative, ahead: colors.accent);
    return mapBuilder(context, config, colors, routeColors, _routeLabel);
  }

  @override
  Widget build(BuildContext context) => NavigationFlowScaffold(
    session: session,
    flow: flow,
    idleBuilder: idleBuilder,
    onEnd: onEnd,
    recenterAlignment: AlignmentDirectional.bottomEnd,
    stepSheetColor: (night) => _colorsAt(night).surface,
    mapBuilder: _map,
    panelBuilder: (context, state, actions) => MapboxStyleRoutePanel(
      state: state,
      tripOverview: flow.isTripOverview,
      formatter: formatter,
      strings: strings,
      colors: _colors,
      onSelect: actions.select,
      onStart: actions.start,
      onSteps: state is FlowOverview ? actions.showSteps : null,
      onRetry: state is FlowError ? actions.retry : null,
      onCancel: actions.cancel,
      onClose: actions.close,
    ),
    headerBuilder: (context, guidance) => MapboxStyleManeuverBanner(
      state: guidance,
      formatter: formatter,
      strings: strings,
      colors: _colors,
    ),
    speedBuilder: (context, speed) => MapboxStyleSpeedLimit(
      info: speed,
      sign: speedLimitSign,
      formatter: formatter,
      strings: strings,
      colors: _colors,
    ),
    footerBuilder: (context, progress, rerouting, actions) =>
        MapboxStyleTripProgress(
          progress: progress,
          rerouting: rerouting,
          formatter: formatter,
          strings: strings,
          colors: _colors,
          onEnd: actions.end,
          onSteps: actions.showSteps,
          onOverview: actions.backToOverview,
        ),
    arrivalBuilder: (context, route, actions) => MapboxStyleArrivalPanel(
      route: route,
      strings: strings,
      colors: _colors,
      onDone: actions.end,
    ),
    stepListBuilder: (context, route, currentStep) => MapboxStyleStepList(
      route: route,
      currentStep: currentStep,
      formatter: formatter,
      colors: _colors,
    ),
    recenterBuilder: (context, recenter) => MapboxStyleRecenterButton(
      onPressed: recenter,
      strings: strings,
      colors: _colors,
    ),
  );
}
