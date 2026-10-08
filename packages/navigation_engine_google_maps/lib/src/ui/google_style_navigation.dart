import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import '../google_maps_navigation_view.dart';
import 'google_style_arrival_panel.dart';
import 'google_style_colors.dart';
import 'google_style_maneuver_header.dart';
import 'google_style_overview_panel.dart';
import 'google_style_recenter_button.dart';
import 'google_style_speedometer.dart';
import 'google_style_step_list.dart';
import 'google_style_strings.dart';
import 'google_style_trip_footer.dart';
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
///   [GoogleStyleTripFooter] at the bottom, and [GoogleStyleRecenterButton]
///   once the user has moved the map;
/// - arrived: [GoogleStyleArrivalPanel].
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
/// and ticks it while on screen. The app owns, starts and disposes [session]
/// and [flow].
class GoogleStyleNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const GoogleStyleNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const GoogleStyleStrings(),
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
  final GoogleStyleStrings strings;

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

  @override
  State<GoogleStyleNavigation> createState() => _GoogleStyleNavigationState();
}

class _GoogleStyleNavigationState extends State<GoogleStyleNavigation> {
  /// Keeps the map view, and so the platform map, across rebuilds.
  final _mapKey = GlobalKey();

  /// What the whole screen, the map included, depends on.
  late Listenable _screenListenable;

  /// What only the overlays depend on: they change while driving, the map
  /// does not.
  late Listenable _progressListenable;

  /// The height of the overview panel at its last layout; null before.
  double? _panelHeight;
  double _topPadding = 0;
  bool _paddingScheduled = false;

  /// The height of the trip footer, which the recenter button sits above.
  double _footerHeight = 0;

  NavigationFlowController get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _listen(widget.flow);
  }

  void _listen(NavigationFlowController flow) {
    _screenListenable = Listenable.merge([flow.state, flow.isNight]);
    _progressListenable = Listenable.merge([
      flow.tripProgress,
      flow.speed,
      flow.rerouting,
    ]);
  }

  @override
  void didUpdateWidget(GoogleStyleNavigation old) {
    super.didUpdateWidget(old);
    if (!identical(old.flow, widget.flow)) {
      _listen(widget.flow);
      _schedulePadding();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePadding();
  }

  void _onPanelSize(Size size) {
    _panelHeight = size.height;
    _schedulePadding();
  }

  // Sets the flow's overview padding after the frame (the size comes from
  // layout, where nothing may change), and only when it changed: the setter
  // re-fits the routes.
  void _schedulePadding() {
    if (_paddingScheduled || _panelHeight == null) return;
    _paddingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paddingScheduled = false;
      final height = _panelHeight;
      if (!mounted || height == null) return;
      final padding = EdgeInsets.fromLTRB(
        32,
        _topPadding + 32,
        32,
        height + 32,
      );
      if (padding != _flow.overviewPadding) _flow.overviewPadding = padding;
    });
  }

  void _onFooterSize(Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && size.height != _footerHeight) {
        setState(() => _footerHeight = size.height);
      }
    });
  }

  // The sheet follows the guidance, and closes itself when the flow moves
  // on (arrival, stop, reroute). The formatter and the colours are those of
  // the moment it opens.
  void _showSteps(NavRoute route, GoogleStyleColors colors) {
    final formatter = widget.formatter;
    final flow = _flow;
    final session = widget.session;
    final opened = flow.state.value;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: colors.surface,
        builder: (context) => _StepSheet(
          flow: flow,
          session: session,
          opened: opened,
          route: route,
          formatter: formatter,
          colors: colors,
        ),
      ),
    );
  }

  // Runs only from the error state; a second tap, after the retry moved the
  // flow on, does nothing. A failure is reported, not thrown.
  void _retry() {
    if (_flow.state.value is! FlowError) return;
    unawaited(
      _flow.retry().catchError(
        (Object e, StackTrace st) => FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'navigation_engine_google_maps',
            context: ErrorDescription('while retrying the route request'),
          ),
        ),
      ),
    );
  }

  /// Whether a back leaves the screen: only when there is nothing to close.
  static bool _canPop(NavigationFlowState state) =>
      state is FlowIdle || state is FlowNavigating || state is FlowArrived;

  // A back closes what is open instead of leaving the screen.
  void _onPop(bool didPop, Object? result) {
    if (didPop) return;
    switch (_flow.state.value) {
      case FlowLoading() || FlowError():
        _flow.cancel();
      case FlowOverview() when !_flow.isTripOverview:
        _flow.closeOverview();
      case FlowOverview():
        _flow.start();
      case FlowIdle() || FlowNavigating() || FlowArrived():
        break;
    }
  }

  void _onRouteOptionTap(int index) {
    if (_flow.state.value is FlowOverview) _flow.select(index);
  }

  void _onMapCreated(GoogleMapController controller) {
    _flow.refreshOverview();
    widget.onMapCreated?.call(controller);
  }

  @override
  Widget build(BuildContext context) {
    _topPadding = MediaQuery.paddingOf(context).top;
    return ListenableBuilder(
      listenable: _screenListenable,
      builder: (context, _) {
        final night = _flow.isNight.value;
        final colors = night ? widget.nightColors : widget.dayColors;
        final routeColors =
            (night ? widget.nightRouteColors : widget.dayRouteColors) ??
            RouteColors(driven: colors.alternative, ahead: colors.accent);
        final state = _flow.state.value;
        return PopScope<Object?>(
          canPop: _canPop(state),
          onPopInvokedWithResult: _onPop,
          child: Stack(
            children: [
              // Built here, not with the overlays: progress ticks do not
              // rebuild the map.
              Positioned.fill(
                child: GoogleMapsNavigationView(
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
                  // Idle too: closing a preview or stopping after a pan
                  // leaves following off, and this is the way back.
                  showRecenterButton:
                      state is FlowNavigating || state is FlowIdle,
                  recenterButton: (recenter) => Padding(
                    padding: EdgeInsets.only(
                      bottom: state is FlowNavigating ? _footerHeight : 0,
                    ),
                    child: GoogleStyleRecenterButton(
                      onPressed: recenter,
                      strings: widget.strings,
                      colors: colors,
                    ),
                  ),
                  routeLabel: (route) => widget.formatter.duration(
                    Duration(seconds: route.duration.round()),
                  ),
                  onRouteOptionTap: _onRouteOptionTap,
                  alternativeRouteColor: colors.alternative,
                  labelColors: colors,
                  onMapCreated: _onMapCreated,
                ),
              ),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _progressListenable,
                  builder: (context, _) =>
                      Stack(children: _overlays(context, state, colors)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _overlays(
    BuildContext context,
    NavigationFlowState state,
    GoogleStyleColors colors,
  ) {
    switch (state) {
      case FlowIdle():
        final idle = widget.idleBuilder;
        return [
          if (idle != null)
            Positioned.fill(
              key: const ValueKey('idle'),
              child: Builder(builder: idle),
            ),
        ];
      case FlowLoading() || FlowOverview() || FlowError():
        return [
          Positioned(
            key: const ValueKey('overview'),
            left: 0,
            right: 0,
            bottom: 0,
            child: _SizeReporter(
              onSize: _onPanelSize,
              child: GoogleStyleOverviewPanel(
                state: state,
                tripOverview: _flow.isTripOverview,
                formatter: widget.formatter,
                strings: widget.strings,
                colors: colors,
                onSelect: _flow.select,
                onStart: _flow.start,
                onSteps: state is FlowOverview
                    ? () => _showSteps(state.route, colors)
                    : null,
                onRetry: state is FlowError ? _retry : null,
                onCancel: _flow.cancel,
                onClose: _flow.isTripOverview ? null : _flow.closeOverview,
              ),
            ),
          ),
        ];
      case FlowNavigating(:final route):
        final progress = _flow.tripProgress.value;
        final speed = _flow.speed.value;
        return [
          Positioned(
            key: const ValueKey('header'),
            left: 0,
            right: 0,
            top: 0,
            child: StreamBuilder<GuidanceState?>(
              stream: widget.session.guidance,
              initialData: widget.session.guidanceState,
              builder: (context, snapshot) {
                final guidance = snapshot.data;
                if (guidance == null) return const SizedBox.shrink();
                return GoogleStyleManeuverHeader(
                  state: guidance,
                  formatter: widget.formatter,
                  strings: widget.strings,
                  colors: colors,
                );
              },
            ),
          ),
          Positioned(
            key: const ValueKey('footer'),
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (speed != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 16,
                        bottom: 16,
                      ),
                      child: GoogleStyleSpeedometer(
                        info: speed,
                        sign: widget.speedLimitSign,
                        strings: widget.strings,
                        colors: colors,
                        formatter: widget.formatter,
                      ),
                    ),
                  ),
                if (progress != null)
                  _SizeReporter(
                    onSize: _onFooterSize,
                    child: GoogleStyleTripFooter(
                      progress: progress,
                      rerouting: _flow.rerouting.value,
                      formatter: widget.formatter,
                      strings: widget.strings,
                      colors: colors,
                      onEnd: widget.onEnd ?? _flow.stop,
                      onSteps: () => _showSteps(route, colors),
                      onOverview: _flow.backToOverview,
                    ),
                  ),
              ],
            ),
          ),
        ];
      case FlowArrived(:final route):
        return [
          Positioned(
            key: const ValueKey('arrival'),
            left: 0,
            right: 0,
            bottom: 0,
            child: GoogleStyleArrivalPanel(
              route: route,
              strings: widget.strings,
              colors: colors,
              onDone: widget.onEnd ?? _flow.stop,
            ),
          ),
        ];
    }
  }
}

/// The step list in a bottom sheet: the current step follows
/// [session]'s guidance, and the sheet closes itself once [flow] leaves the
/// state it was [opened] in (another kind of state, or another route).
class _StepSheet extends StatefulWidget {
  const _StepSheet({
    required this.flow,
    required this.session,
    required this.opened,
    required this.route,
    required this.formatter,
    required this.colors,
  });

  final NavigationFlowController flow;
  final NavigationSession session;
  final NavigationFlowState opened;
  final NavRoute route;
  final GuidanceFormatter formatter;
  final GoogleStyleColors colors;

  @override
  State<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends State<_StepSheet> {
  ModalRoute<Object?>? _sheet;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.flow.state.addListener(_onFlowState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheet = ModalRoute.of(context);
  }

  @override
  void dispose() {
    widget.flow.state.removeListener(_onFlowState);
    super.dispose();
  }

  static NavRoute? _routeOf(NavigationFlowState state) => switch (state) {
    FlowNavigating(:final route) || FlowArrived(:final route) => route,
    final FlowOverview overview => overview.route,
    _ => null,
  };

  void _onFlowState() {
    final state = widget.flow.state.value;
    if (state.runtimeType == widget.opened.runtimeType &&
        identical(_routeOf(state), _routeOf(widget.opened))) {
      return;
    }
    final sheet = _sheet;
    if (_closed || !mounted || sheet == null || !sheet.isActive) return;
    _closed = true;
    final navigator = Navigator.of(context);
    if (sheet.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(sheet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => PrimaryScrollController(
        controller: controller,
        child: StreamBuilder<GuidanceState?>(
          stream: session.guidance,
          initialData: session.guidanceState,
          builder: (context, snapshot) => GoogleStyleStepList(
            route: widget.route,
            // Only the route the session drives has a current step.
            currentStep: identical(session.route, widget.route)
                ? snapshot.data?.stepIndex ?? -1
                : -1,
            formatter: widget.formatter,
            colors: widget.colors,
          ),
        ),
      ),
    );
  }
}

/// Reports its child's size after each layout that changed it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    onSize(size);
  }
}
