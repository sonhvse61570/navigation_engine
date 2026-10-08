import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import '../google_maps_navigation_view.dart';
import 'google_style_arrival_panel.dart';
import 'google_style_colors.dart';
import 'google_style_compass_button.dart';
import 'google_style_maneuver_header.dart';
import 'google_style_overview_panel.dart';
import 'google_style_recenter_button.dart';
import 'google_style_round_button.dart';
import 'google_style_speedometer.dart';
import 'google_style_step_list.dart';
import 'google_style_trip_footer.dart';
import 'google_style_trip_progress_bar.dart';
import 'night_map_style.dart';

/// A complete navigation screen in the style of a phone navigation app: the
/// map, the route overview, turn-by-turn guidance and the arrival, bound to
/// [flow] and [session].
///
/// It shows, per [NavigationFlowController.state]:
/// - idle: [idleBuilder]'s overlay, or nothing;
/// - loading, overview, error: [GoogleStyleOverviewPanel] at the bottom;
/// - navigating: [GoogleStyleManeuverHeader] at the top (once there is
///   guidance), [GoogleStyleSpeedometer] at the bottom left,
///   [GoogleStyleTripFooter] at the bottom, [GoogleStyleRecenterButton] at
///   the bottom left once the user has moved the map (above the speedometer),
///   [GoogleStyleTripProgressBar] on the start edge, and below the header on
///   the end side the [GoogleStyleCompassButton] (while the camera follows
///   the vehicle) and the sound and report buttons;
/// - arrived: [GoogleStyleArrivalPanel].
///
/// Each control of the navigating state has a toggle, as in Google's
/// navigation SDK: [headerEnabled], [footerEnabled], [tripProgressBarEnabled],
/// [speedometerEnabled], [speedLimitIconEnabled], [recenterButtonEnabled],
/// [compassEnabled] and [routeOverviewButtonEnabled]. The sound and report
/// buttons show when [onMuteToggle] and [onReportIncident] are given.
///
/// The loading spinner has a cancel button and a route preview a close
/// button. A back (the system back button or gesture) leaves the screen only
/// while idle, navigating or arrived; otherwise it closes what is open:
/// loading and error cancel ([NavigationFlowController.cancel]), a route
/// preview closes ([NavigationFlowController.closeOverview]), and the trip
/// overview resumes the trip ([NavigationFlowController.start]). The step
/// list follows the guidance and closes when the flow moves on.
///
/// [dayColors] / [nightColors] reach the panels, the turn card, the route
/// lines and the route option labels. [dayRouteColors] / [nightRouteColors]
/// override the selected option and the session's route line; the other
/// options always use [GoogleStyleColors.alternative]. Speeds go through [formatter]
/// ([GuidanceFormatter.speedValue] and [GuidanceFormatter.speedUnit]).
///
/// The map is a [GoogleMapsNavigationView]: it attaches itself to [session]
/// and ticks it while on screen. The flow binding (the states, the back, the
/// overview padding, the step sheet, the recenter) is a
/// [NavigationFlowScaffold]. The app owns, starts and disposes [session] and
/// [flow].
class GoogleStyleNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const GoogleStyleNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors = GoogleStyleColors.day,
    this.nightColors = GoogleStyleColors.night,
    this.nightMapStyle = googleStyleNightMapStyle,
    this.speedLimitSign = SpeedLimitSign.circular,
    this.idleBuilder,
    this.onEnd,
    this.markers = const {},
    this.onMapCreated,
    this.dayRouteColors,
    this.nightRouteColors,
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.focus = 0.7,
    this.initialZoom = 17,
    this.headerEnabled = true,
    this.footerEnabled = true,
    this.tripProgressBarEnabled = true,
    this.speedometerEnabled = true,
    this.speedLimitIconEnabled = true,
    this.recenterButtonEnabled = true,
    this.compassEnabled = true,
    this.routeOverviewButtonEnabled = true,
    this.onMuteToggle,
    this.muted = false,
    this.onReportIncident,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  final GoogleStyleColors dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  final GoogleStyleColors nightColors;

  /// The map style used at night; null keeps the default map look.
  final String? nightMapStyle;

  /// The shape of the speed limit sign.
  final SpeedLimitSign speedLimitSign;

  /// Builds the overlay shown while the flow is idle, such as a search bar;
  /// it fills the screen above the map. Nothing is shown when null.
  final WidgetBuilder? idleBuilder;

  /// Called by the end button and by the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// The app's own markers, drawn on the map.
  final Set<Marker> markers;

  /// Called when the map controller is created, after the route overview is
  /// drawn on the new map.
  final void Function(GoogleMapController controller)? onMapCreated;

  /// The route line colours by day. When null they come from [dayColors]:
  /// `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? dayRouteColors;

  /// The route line colours at night. When null they come from
  /// [nightColors]: `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? nightRouteColors;

  /// The vehicle while the camera follows it; see
  /// [GoogleMapsNavigationView.puck].
  final Widget puck;

  /// Renders the vehicle marker drawn by the map; see
  /// [GoogleMapsNavigationView.vehicleImage].
  final VehicleImageBuilder? vehicleImage;

  /// Where the vehicle sits on the screen while followed; see
  /// [GoogleMapsNavigationView.focus].
  final double focus;

  /// The zoom of the map before the first camera move.
  final double initialZoom;

  /// Whether the turn card shows at the top while navigating.
  final bool headerEnabled;

  /// Whether the trip footer shows while navigating. The panel of the route
  /// overview shows regardless.
  final bool footerEnabled;

  /// Whether the trip progress bar shows on the start edge.
  final bool tripProgressBarEnabled;

  /// Whether the current speed shows.
  final bool speedometerEnabled;

  /// Whether the speed limit sign shows (when the limit is known).
  final bool speedLimitIconEnabled;

  /// Whether the recenter button shows once the user has moved the map.
  final bool recenterButtonEnabled;

  /// Whether the compass button shows, while the camera follows the vehicle.
  final bool compassEnabled;

  /// Whether the footer has its route overview button.
  final bool routeOverviewButtonEnabled;

  /// Called when the sound button is pressed; the button is hidden when
  /// null. The app owns the sound: it turns it on or off and sets [muted].
  final VoidCallback? onMuteToggle;

  /// Whether the sound is off: the sound button shows a muted icon.
  final bool muted;

  /// Called when the report button is pressed; the button is hidden when
  /// null.
  final VoidCallback? onReportIncident;

  @override
  State<GoogleStyleNavigation> createState() => _GoogleStyleNavigationState();
}

class _GoogleStyleNavigationState extends State<GoogleStyleNavigation> {
  /// Keeps the map view, and so the platform map, across rebuilds.
  final _mapKey = GlobalKey();

  GoogleStyleColors _colorsAt(bool night) =>
      night ? widget.nightColors : widget.dayColors;

  /// The colours of the moment: the scaffold rebuilds the pieces when the
  /// night mode changes.
  GoogleStyleColors get _colors => _colorsAt(widget.flow.isNight.value);

  Widget _map(BuildContext context, NavigationMapConfig config) {
    final night = config.isNight;
    final colors = _colorsAt(night);
    final routeColors =
        (night ? widget.nightRouteColors : widget.dayRouteColors) ??
        RouteColors(driven: colors.alternative, ahead: colors.accent);
    return GoogleMapsNavigationView(
      key: _mapKey,
      session: widget.session,
      initialCenter: widget.initialCenter,
      initialZoom: widget.initialZoom,
      routeColors: routeColors,
      puck: widget.puck,
      vehicleImage: widget.vehicleImage,
      focus: widget.focus,
      style: night ? widget.nightMapStyle : null,
      markers: widget.markers,
      // The scaffold shows the recenter button.
      showRecenterButton: false,
      routeLabel: (route) =>
          widget.formatter.duration(Duration(seconds: route.duration.round())),
      onRouteOptionTap: config.onRouteOptionTap,
      alternativeRouteColor: colors.alternative,
      labelColors: colors,
      onMapCreated: (controller) {
        config.onMapReady();
        widget.onMapCreated?.call(controller);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = widget.formatter;
    final strings = widget.strings;
    return NavigationFlowScaffold(
      session: widget.session,
      flow: widget.flow,
      idleBuilder: widget.idleBuilder,
      onEnd: widget.onEnd,
      // At the bottom start, above the speedometer, as in Google's UI.
      recenterAlignment: AlignmentDirectional.bottomStart,
      stepSheetColor: (night) => _colorsAt(night).surface,
      mapBuilder: _map,
      panelBuilder: (context, state, actions) => GoogleStyleOverviewPanel(
        state: state,
        tripOverview: widget.flow.isTripOverview,
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
      headerBuilder: (context, guidance) => widget.headerEnabled
          ? GoogleStyleManeuverHeader(
              state: guidance,
              formatter: formatter,
              strings: strings,
              colors: _colors,
            )
          : const SizedBox.shrink(),
      speedBuilder: widget.speedometerEnabled || widget.speedLimitIconEnabled
          ? (context, speed) => GoogleStyleSpeedometer(
              info: speed,
              sign: widget.speedLimitSign,
              strings: strings,
              colors: _colors,
              formatter: formatter,
              showSpeed: widget.speedometerEnabled,
              showLimit: widget.speedLimitIconEnabled,
            )
          : null,
      footerBuilder: (context, progress, rerouting, actions) =>
          widget.footerEnabled
          ? GoogleStyleTripFooter(
              progress: progress,
              rerouting: rerouting,
              formatter: formatter,
              strings: strings,
              colors: _colors,
              onEnd: actions.end,
              onSteps: actions.showSteps,
              onOverview: widget.routeOverviewButtonEnabled
                  ? actions.backToOverview
                  : null,
            )
          // Keeps the bottom inset the footer's own safe area gave.
          : const SafeArea(top: false, child: SizedBox.shrink()),
      edgeBuilder: widget.tripProgressBarEnabled
          ? (context, progress) => GoogleStyleTripProgressBar(
              fraction: progress.fraction,
              colors: _colors,
            )
          : null,
      topEndBuilder: _hasTopEnd ? _topEnd : null,
      arrivalBuilder: (context, route, actions) => GoogleStyleArrivalPanel(
        route: route,
        strings: strings,
        colors: _colors,
        onDone: actions.end,
      ),
      stepListBuilder: (context, route, currentStep) => GoogleStyleStepList(
        route: route,
        currentStep: currentStep,
        formatter: formatter,
        colors: _colors,
      ),
      recenterBuilder: widget.recenterButtonEnabled
          ? (context, recenter) => GoogleStyleRecenterButton(
              onPressed: recenter,
              strings: strings,
              colors: _colors,
            )
          : null,
    );
  }

  bool get _hasTopEnd =>
      widget.compassEnabled ||
      widget.onMuteToggle != null ||
      widget.onReportIncident != null;

  /// The compass, the sound button and the report button, under the header
  /// on the end side.
  Widget _topEnd(BuildContext context, NavigationFlowActions actions) {
    final strings = widget.strings;
    final colors = _colors;
    final onMuteToggle = widget.onMuteToggle;
    final onReportIncident = widget.onReportIncident;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 8,
      children: [
        // Shown while following; hidden once the user has panned away.
        if (widget.compassEnabled && widget.session.follow)
          _LiveCompass(
            session: widget.session,
            strings: strings,
            colors: colors,
          ),
        if (onMuteToggle != null)
          GoogleStyleRoundButton(
            icon: Icon(widget.muted ? Icons.volume_off : Icons.volume_up),
            tooltip: widget.muted ? strings.unmute : strings.mute,
            onPressed: onMuteToggle,
            colors: colors,
          ),
        if (onReportIncident != null)
          GoogleStyleRoundButton(
            icon: const Icon(Icons.report_outlined),
            tooltip: strings.reportIncident,
            onPressed: onReportIncident,
            colors: colors,
          ),
      ],
    );
  }
}

/// The compass of [session]'s camera. The scaffold rebuilds its overlays
/// about once a second, too seldom for a needle, so it listens to the
/// session's frames itself and rebuilds only when the camera's bearing
/// changed by 1 degree or more, or the camera switched between heading up
/// and north up.
class _LiveCompass extends StatefulWidget {
  const _LiveCompass({
    required this.session,
    required this.strings,
    required this.colors,
  });

  final NavigationSession session;
  final NavigationStrings strings;
  final GoogleStyleColors colors;

  @override
  State<_LiveCompass> createState() => _LiveCompassState();
}

class _LiveCompassState extends State<_LiveCompass> {
  StreamSubscription<MotionFrame>? _sub;

  /// What the compass shows now.
  late double _bearing;
  late bool _headingUp;

  /// The bearing of the camera: the vehicle's when it turns with it, else
  /// north.
  static double _bearingOf(NavigationSession session) =>
      session.camera.headingUp ? session.frame?.bearing ?? 0 : 0;

  @override
  void initState() {
    super.initState();
    _bearing = _bearingOf(widget.session);
    _headingUp = widget.session.camera.headingUp;
    _subscribe();
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    _sub = widget.session.frames.listen((_) => _sync());
  }

  @override
  void didUpdateWidget(_LiveCompass old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _subscribe();
      _bearing = _bearingOf(widget.session);
      _headingUp = widget.session.camera.headingUp;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _sync() {
    final camera = widget.session.camera;
    final bearing = _bearingOf(widget.session);
    final turned = ((bearing - _bearing + 540) % 360 - 180).abs() >= 1;
    if (!turned && camera.headingUp == _headingUp) return;
    setState(() {
      _bearing = bearing;
      _headingUp = camera.headingUp;
    });
  }

  void _toggle() {
    final camera = widget.session.camera;
    camera.headingUp = !camera.headingUp;
    _sync();
  }

  @override
  Widget build(BuildContext context) => GoogleStyleCompassButton(
    bearing: _bearing,
    headingUp: _headingUp,
    onPressed: _toggle,
    strings: widget.strings,
    colors: widget.colors,
  );
}
