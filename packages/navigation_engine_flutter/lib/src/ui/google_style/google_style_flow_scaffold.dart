import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../along_route_search.dart';
import '../../flow/alternate_route.dart';
import '../../flow/navigation_flow_actions.dart';
import '../../flow/navigation_flow_controller.dart';
import '../../flow/navigation_flow_scaffold.dart';
import '../../flow/navigation_flow_state.dart';
import '../../flow/navigation_map_config.dart';
import '../../flow/search_pins_map.dart';
import '../../flow/trip_progress.dart';
import '../../route_colors.dart';
import '../navigation_strings.dart';
import 'audio_guidance.dart';
import 'google_style_arrival_sheet.dart';
import 'google_style_colors.dart';
import 'google_style_compass_button.dart';
import 'google_style_control_stack.dart';
import 'google_style_maneuver_header.dart';
import 'google_style_map_layers.dart';
import 'google_style_overview_panel.dart';
import 'google_style_recenter_button.dart';
import 'google_style_report_button.dart';
import 'google_style_report_sheet.dart';
import 'google_style_round_button.dart';
import 'google_style_search_along_route.dart';
import 'google_style_sound_button.dart';
import 'google_style_speed_cluster.dart';
import 'google_style_step_list.dart';
import 'google_style_trip_progress_bar.dart';
import 'google_style_trip_sheet.dart';
import 'incident_type.dart';
import 'last_road.dart';
import 'speed_limit_sign_style.dart';

/// The least screen height that shows the trip progress bar, as in Google's
/// navigation SDK.
const double _progressBarMinHeight = 552;

/// The end column's members, top to bottom.
const _columnMembers = [
  'report',
  'compass',
  'search',
  'sound',
  'route_options',
];

/// The height of one end column button (the round buttons' 52 dp circles,
/// as in Google Maps) and the space between two.
const double _columnExtent = 52;
const double _columnGap = 16;

/// A [NavigationFlowScaffold] dressed with the Google-style pieces: the
/// navigation screen in the style of the Google Maps app, bound to [flow]
/// and [session], without the map, which [mapBuilder] provides. It is the
/// screen of the Google Maps adapter's `GoogleStyleNavigation` drop-in.
///
/// Per [NavigationFlowController.state]:
/// - **Idle:** [idleBuilder]'s overlay.
/// - **Loading, overview, error:** [GoogleStyleOverviewPanel].
/// - **Navigating:**
///   - [GoogleStyleManeuverHeader] at the top. A tap opens the step list
///     and a swipe previews the next step (Re-center ends the preview).
///   - The end column, anchored 16 above the trip sheet and growing
///     upwards: the report button, the compass, the search button, the
///     3-state sound button and the route-options button (the trip
///     overview with the alternates). A short column drops search, then
///     sound, then the compass, then the report; route options stay.
///   - The speed cluster at the bottom start, replaced by the Re-center
///     pill once the map is moved.
///   - [GoogleStyleTripSheet] at the bottom, with its close circle and its
///     menu (share, search along the route, directions, traffic and
///     satellite switches, settings).
///   - Alternate routes on the map with their time bubbles, when the
///     session's map is an [AlternateRoutesMap]; a tap switches to one and
///     the camera follows the vehicle again.
/// - **Arrived:** the arrival header and [GoogleStyleArrivalSheet].
///
/// On a landscape screen at least 600 dp wide, the header and the sheet go
/// to a side panel on the start side ([NavigationFlowScaffold.landscapeSidePanel]).
///
/// A control shows when its toggle is on and its callback exists:
/// - [headerEnabled], [footerEnabled], [tripProgressBarEnabled] (off by
///   default);
/// - [speedometerEnabled], [speedLimitIconEnabled], [recenterButtonEnabled],
///   [compassEnabled], [routeOverviewButtonEnabled];
/// - [reportButtonEnabled] with [onReportIncident], [searchButtonEnabled]
///   with [searchAlongRoute];
/// - the sound button with [onAudioGuidanceChanged].
///
/// The search pins its results on the session's map when it is a
/// [SearchPinsMap], and works without them otherwise.
///
/// The app owns the audio ([audioGuidance]), reports, search and stops; the
/// library adds no stop itself.
///
/// [mapBuilder] gets the [GoogleStyleMapLayers] of the moment: the traffic
/// and satellite switches, the horizontal focus beside the side panel, the
/// bottom overlay (held while the trip sheet moves or is open), the
/// colours, the route line colours and the bubbles' texts. The map should
/// honour them all, turn its own recenter button off and call
/// [NavigationMapConfig.onMapReady] once it is ready. A touch on the map
/// during a step preview ends the preview where the camera is.
///
/// The app owns, starts and disposes [session] and [flow].
class GoogleStyleFlowScaffold extends StatefulWidget {
  /// Creates the Google-style screen of [flow] on [session].
  const GoogleStyleFlowScaffold({
    super.key,
    required this.session,
    required this.flow,
    required this.mapBuilder,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors = GoogleStyleColors.day,
    this.nightColors = GoogleStyleColors.night,
    this.dayRouteColors,
    this.nightRouteColors,
    this.speedLimitSignStyle = SpeedLimitSignStyle.vienna,
    this.speedingMinor,
    this.speedingMajor,
    this.idleBuilder,
    this.onEnd,
    this.headerEnabled = true,
    this.footerEnabled = true,
    this.tripProgressBarEnabled = false,
    this.speedometerEnabled = true,
    this.speedLimitIconEnabled = true,
    this.recenterButtonEnabled = true,
    this.compassEnabled = true,
    this.routeOverviewButtonEnabled = true,
    this.reportButtonEnabled = true,
    this.searchButtonEnabled = true,
    this.audioGuidance = AudioGuidance.sound,
    this.onAudioGuidanceChanged,
    this.onReportIncident,
    this.searchAlongRoute,
    this.onAddStop,
    this.onShareTrip,
    this.onSettings,
  });

  /// Builds the map, which fills the screen under the pieces, with the
  /// [GoogleStyleMapLayers] of the moment. It is built when the state, the
  /// night mode or a layer changes, and it may be built again with equal
  /// layers (on a search, a toast or a menu change, or while the sheet is
  /// dragged); a map applies the layers idempotently. It is never built for
  /// progress ticks (see [NavigationFlowScaffold.mapBuilder]).
  final Widget Function(
    BuildContext context,
    NavigationMapConfig config,
    GoogleStyleMapLayers layers,
  )
  mapBuilder;

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  final GoogleStyleColors dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  final GoogleStyleColors nightColors;

  /// The shape of the speed limit sign.
  final SpeedLimitSignStyle speedLimitSignStyle;

  /// Over the limit by this much (in the formatter's unit) is a minor
  /// speeding alert; see [GoogleStyleSpeedCluster.speedingLevel].
  final double? speedingMinor;

  /// Over the limit by this much is a major speeding alert.
  final double? speedingMajor;

  /// Builds the overlay shown while the flow is idle, such as a search bar.
  final WidgetBuilder? idleBuilder;

  /// Called by the close circle and the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// The route line colours by day, for the map
  /// ([GoogleStyleMapLayers.routeColors]); when null, `RouteColors(driven:
  /// alternative, ahead: accent)` of [dayColors].
  final RouteColors? dayRouteColors;

  /// The route line colours at night; when null, from [nightColors].
  final RouteColors? nightRouteColors;

  /// Whether the turn card shows.
  final bool headerEnabled;

  /// Whether the trip sheet shows while navigating.
  final bool footerEnabled;

  /// Whether the trip progress bar shows on the start edge (on screens at
  /// least 552 dp high). Off by default, as in Google's navigation SDK.
  final bool tripProgressBarEnabled;

  /// Whether the speedometer may show.
  final bool speedometerEnabled;

  /// Whether the speed limit sign may show.
  final bool speedLimitIconEnabled;

  /// Whether the Re-center pill shows once the user has moved the map.
  final bool recenterButtonEnabled;

  /// Whether the compass shows while the camera follows the vehicle.
  final bool compassEnabled;

  /// Whether the end column has its route-options button.
  final bool routeOverviewButtonEnabled;

  /// Whether the report button shows (with [onReportIncident]).
  final bool reportButtonEnabled;

  /// Whether the search button shows in the end column (with
  /// [searchAlongRoute]).
  final bool searchButtonEnabled;

  /// The audio state the sound button shows. Owned by the app.
  final AudioGuidance audioGuidance;

  /// Called with the audio state chosen in the sound pill; the sound button
  /// is hidden when null.
  final ValueChanged<AudioGuidance>? onAudioGuidanceChanged;

  /// Called with the incident chosen in the report sheet; the report button
  /// is hidden when null.
  final ValueChanged<IncidentType>? onReportIncident;

  /// Searches for places along the route; the search button and menu row
  /// are hidden when null.
  final AlongRouteSearch? searchAlongRoute;

  /// Called by the search's "Add stop" button; it is hidden when null.
  /// Afterwards the search closes and the camera follows again.
  final ValueChanged<AlongRoutePlace>? onAddStop;

  /// Called by the menu's "Share trip progress" row; hidden when null.
  final VoidCallback? onShareTrip;

  /// Called by the menu's "Settings" row; hidden when null.
  final VoidCallback? onSettings;

  @override
  State<GoogleStyleFlowScaffold> createState() =>
      _GoogleStyleFlowScaffoldState();
}

class _GoogleStyleFlowScaffoldState extends State<GoogleStyleFlowScaffold> {
  /// The end column's slot, its members, and the bottom-start group (the
  /// speed cluster or the Re-center pill), measured after each frame so the
  /// column can keep clear of the group (one frame late).
  final _slotKey = GlobalKey();
  final _speedKey = GlobalKey();
  final _recenterKey = GlobalKey();
  final _memberKeys = {
    for (final name in _columnMembers) name: GlobalKey(debugLabel: name),
  };
  final _memberWidths = <String, double>{};
  Rect? _slotRect;
  Rect? _groupRect;
  bool _measureScheduled = false;

  bool _traffic = false;
  bool _satellite = false;
  bool _speedometerShown = true;
  bool _searching = false;

  /// Whether the sound pill and the trip sheet's menu are open, as they
  /// report it, and whether either was at the last build: the system back
  /// closes them before the search, one layer per back.
  bool _pillOpen = false;
  bool _menuOpen = false;
  bool _layerAboveSearch = false;

  /// The trip sheet's expanded fraction t (0 collapsed, 1 expanded), as it
  /// reports it on every frame of a drag or an animation; the floating
  /// controls fade with it.
  final _sheetFraction = ValueNotifier<double>(0);

  /// Whether the trip sheet is not collapsed (t > 0), as last built.
  bool _sheetMoving = false;

  /// The end column's slot height while the sheet was last collapsed.
  double? _collapsedSlot;

  /// Whether the floating controls keep their collapsed geometry: from the
  /// first frame the sheet leaves its collapsed height until the frame
  /// after it is back (the scaffold publishes the collapsed footer's height
  /// after the frame that lays it out).
  bool _floatFrozen = false;

  /// The scaffold's bottom overlay height, as the map view last got it.
  ValueListenable<double>? _bottomOverlay;

  /// The bottom overlay the map view keeps while the trip sheet is not
  /// collapsed: the one from its collapsed height, so neither the camera's
  /// focus nor the map's padding moves as it is dragged, animates or stays
  /// open (as in Google Maps). Null while it is collapsed.
  double? _heldOverlay;

  /// The open report sheet's route; null when none is open.
  ModalRoute<Object?>? _reportRoute;

  /// The search bar's height (from the screen's top), as last reported.
  double _searchBarHeight = 0;
  List<AlongRoutePlace> _places = const [];
  AlongRoutePlace? _focusedPlace;
  String? _toast;
  Timer? _toastTimer;

  /// The flow's state and alternates as last seen, and the alternates seen
  /// before those: the flow drops the chosen route from its alternates just
  /// before it switches to it.
  NavigationFlowState? _lastState;
  List<AlternateRoute> _alternates = const [];
  List<AlternateRoute> _alternatesBefore = const [];

  @override
  void initState() {
    super.initState();
    _listen(widget.flow);
  }

  void _listen(NavigationFlowController flow) {
    _lastState = flow.state.value;
    _alternates = flow.alternates.value;
    _alternatesBefore = const [];
    flow.state.addListener(_onFlowState);
    flow.alternates.addListener(_onAlternates);
    flow.isNight.addListener(_onNight);
  }

  void _unlisten(NavigationFlowController flow) {
    flow.state.removeListener(_onFlowState);
    flow.alternates.removeListener(_onAlternates);
    flow.isNight.removeListener(_onNight);
  }

  // The pieces built here outside the flow scaffold (the search overlay)
  // follow the night colours; the flow scaffold rebuilds its own.
  void _onNight() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GoogleStyleFlowScaffold old) {
    super.didUpdateWidget(old);
    if (!identical(old.flow, widget.flow)) {
      _unlisten(old.flow);
      _listen(widget.flow);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.flow);
    _toastTimer?.cancel();
    _sheetFraction.dispose();
    super.dispose();
  }

  GoogleStyleColors _colorsAt(bool night) =>
      night ? widget.nightColors : widget.dayColors;

  GoogleStyleColors get _colors => _colorsAt(widget.flow.isNight.value);

  /// The session's map as far as it draws search pins; null when it does not.
  SearchPinsMap? get _pins => switch (widget.session.map) {
    final SearchPinsMap m => m,
    _ => null,
  };

  /// The size this screen lays out in, as last built. The flow scaffold
  /// decides its layout from the same size, which is smaller than the
  /// screen when this one is embedded in a pane.
  Size _size = Size.zero;

  /// Whether the scaffold shows the side panel layout.
  bool get _side => NavigationFlowScaffold.usesSidePanel(_size);

  /// The width the side panel covers at the start, as the scaffold's
  /// [NavigationMapConfig.startOverlayWidth]; zero without the side panel.
  double _startOverlay(BuildContext context) {
    if (!_side) return 0;
    final padding = MediaQuery.paddingOf(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return (ltr ? padding.left : padding.right) +
        2 * NavigationFlowScaffold.sidePanelMargin +
        NavigationFlowScaffold.sidePanelWidth(_size);
  }

  /// A card of the side panel: rounded on every side.
  Widget _card(BuildContext context, Widget child) => _side
      ? ClipRRect(borderRadius: BorderRadius.circular(16), child: child)
      : child;

  void _onAlternates() {
    _alternatesBefore = _alternates;
    _alternates = widget.flow.alternates.value;
  }

  void _onFlowState() {
    final state = widget.flow.state.value;
    final last = _lastState;
    _lastState = state;
    // Leaving navigation closes the search and the report sheet.
    if (_searching && state is! FlowNavigating) {
      _closeSearch(refollow: false);
    }
    if (state is! FlowNavigating) _closeReport();
    // A new route (a reroute or an alternate) while searching: the results
    // and pins were found along the old one. The overlay gets the new route
    // and searches again.
    if (_searching &&
        state is FlowNavigating &&
        last is FlowNavigating &&
        !identical(state.route, last.route)) {
      _places = const [];
      _clearPins();
      if (mounted) setState(() => _focusedPlace = null);
    }
    // A switch to an alternate (a tap on its line or bubble, which stopped
    // the follow) re-centres on the vehicle, as Google does. A reroute's new
    // route was never an alternate, so it leaves the follow alone.
    if (state is FlowNavigating &&
        last is FlowNavigating &&
        !identical(state.route, last.route) &&
        [
          ..._alternatesBefore,
          ..._alternates,
        ].any((a) => identical(a.route, state.route))) {
      widget.session.follow = true;
    }
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _report() async {
    final onReport = widget.onReportIncident;
    if (onReport == null) return;
    final strings = widget.strings;
    final flow = widget.flow;
    final type = await showModalBottomSheet<IncidentType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _colors.surface,
      // The sheet paints its own surface, clipped to the sheet's corners.
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        _reportRoute = ModalRoute.of(context);
        // It follows a day/night switch while it is open.
        return ValueListenableBuilder<bool>(
          valueListenable: flow.isNight,
          builder: (context, night, _) {
            final colors = _colorsAt(night);
            return ColoredBox(
              color: colors.surface,
              child: GoogleStyleReportSheet(
                strings: strings,
                colors: colors,
                onSelected: (type) => Navigator.of(context).pop(type),
              ),
            );
          },
        );
      },
    );
    _reportRoute = null;
    // A report belongs to the trip: none once navigation has ended.
    if (type == null ||
        !mounted ||
        widget.flow.state.value is! FlowNavigating) {
      return;
    }
    onReport(type);
    _showToast(widget.strings.reportSent);
  }

  /// Closes the report sheet, if it is open: navigation has ended.
  void _closeReport() {
    final route = _reportRoute;
    _reportRoute = null;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (navigator == null) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  /// Previews the step [delta] away from the one previewed (or the next
  /// one); going back to the next one ends the preview.
  void _previewBy(int delta) {
    final flow = widget.flow;
    final state = flow.state.value;
    final current = widget.session.guidanceState?.stepIndex ?? -1;
    if (state is! FlowNavigating || current < 0) return;
    final target = (flow.previewedStep.value ?? current) + delta;
    if (target <= current) {
      flow.endStepPreview();
      return;
    }
    if (target >= state.route.steps.length) return;
    flow.previewStep(target);
  }

  String _alternateLabel(AlternateRoute alternate) {
    final m = alternate.minutesDelta;
    final strings = widget.strings;
    return m < 0
        ? strings.minFaster(-m)
        : m > 0
        ? strings.minSlower(m)
        : strings.similarEta;
  }

  /// The follow focus across the map: the middle of the part beside a side
  /// panel [start] wide (on the start side), else the centre.
  double _horizontalFocus(BuildContext context, double start) {
    final width = _size.width;
    if (start <= 0 || width <= 0) return 0.5;
    final centre = (start + width) / 2 / width;
    return Directionality.of(context) == TextDirection.ltr
        ? centre
        : 1 - centre;
  }

  void _openSearch() {
    if (widget.searchAlongRoute == null) return;
    if (widget.flow.state.value is! FlowNavigating) return;
    // The search bar takes the header's place: a step preview ends.
    widget.flow.endStepPreview();
    setState(() => _searching = true);
  }

  void _closeSearch({required bool refollow}) {
    _places = const [];
    _focusedPlace = null;
    _clearPins();
    if (refollow) widget.session.follow = true;
    if (mounted) {
      setState(() {
        _searching = false;
        _searchBarHeight = 0;
      });
    }
  }

  void _drawPins() {
    final pins = _pins;
    if (pins == null) return;
    if (_places.isEmpty) {
      _clearPins();
      return;
    }
    _onMap(
      'drawing the search pins',
      () => pins.showSearchPins(
        _places,
        focusedId: _focusedPlace?.id,
        onTap: _focusPlace,
      ),
    );
  }

  void _clearPins() {
    final pins = _pins;
    if (pins != null) _onMap('clearing the search pins', pins.clearSearchPins);
  }

  /// Runs a call on the session's map. An error, thrown at once or through
  /// the future, is reported, not thrown, so a failing map never breaks
  /// the screen (as in [NavigationFlowController]).
  void _onMap(String what, FutureOr<void> Function() call) {
    unawaited(
      Future<void>.sync(call).catchError((Object e, StackTrace st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'navigation_engine_flutter',
            context: ErrorDescription('while $what'),
          ),
        );
      }),
    );
  }

  /// Focuses [place], from its result or its pin: the pin grows, the list
  /// selects it and the camera moves to it.
  void _focusPlace(AlongRoutePlace place) {
    if (mounted) setState(() => _focusedPlace = place);
    _drawPins();
    widget.session.follow = false;
    final map = widget.session.map;
    if (map == null) return;
    _onMap(
      'moving the camera to a place',
      () => map.moveCamera(
        CameraTarget(position: place.position, bearing: 0, zoom: 16, tilt: 0),
      ),
    );
  }

  String _routeLabel(NavRoute route) =>
      widget.formatter.duration(Duration(seconds: route.duration.round()));

  Widget _mapView(BuildContext context, NavigationMapConfig config) {
    final night = config.isNight;
    final colors = _colorsAt(night);
    final routeColors =
        (night ? widget.nightRouteColors : widget.dayRouteColors) ??
        RouteColors(driven: colors.alternative, ahead: colors.accent);
    _bottomOverlay = config.bottomOverlayHeight;
    return ListenableBuilder(
      listenable: Listenable.merge([
        config.startOverlayWidth,
        config.bottomOverlayHeight,
      ]),
      // A touch on the map during a step preview ends it where the camera
      // is: its timer must not re-follow while the user pans.
      builder: (context, _) => Listener(
        onPointerDown: (_) {
          if (widget.flow.previewedStep.value != null) {
            widget.flow.endStepPreview(refollow: false);
          }
        },
        child: widget.mapBuilder(
          context,
          config,
          GoogleStyleMapLayers(
            traffic: _traffic,
            satellite: _satellite,
            horizontalFocus: _horizontalFocus(
              context,
              config.startOverlayWidth.value,
            ),
            // Keeps the map's logo above the sheet, the speed and
            // Re-center; held at the collapsed sheet's while the sheet
            // moves or is open.
            bottomOverlay: _heldOverlay ?? config.bottomOverlayHeight.value,
            colors: colors,
            routeColors: routeColors,
            routeLabel: _routeLabel,
            alternateLabel: _alternateLabel,
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    GuidanceState guidance,
    NavigationFlowActions actions,
  ) {
    if (_searching) {
      // The search bar takes the header's place. In portrait the slot keeps
      // its height, so the stack stays under the bar; the side panel's bar
      // sits in the panel, away from the stack.
      if (_side) return const SizedBox.shrink();
      final top = MediaQuery.paddingOf(this.context).top;
      return SizedBox(height: math.max(0, _searchBarHeight - top));
    }
    if (!widget.headerEnabled) return const SizedBox.shrink();
    // In the side panel the open menu takes the column, as in Google Maps:
    // its rows need more than the footer's share beside the turn card. It
    // gives way as soon as the sheet leaves its collapsed height, so the
    // sheet grows upwards without a jump.
    if ((_menuOpen || _sheetMoving) && _side) return const SizedBox.shrink();
    final flow = widget.flow;
    final margin = _side ? EdgeInsets.zero : const EdgeInsets.all(8);
    return ValueListenableBuilder<int?>(
      valueListenable: flow.previewedStep,
      builder: (context, previewed, _) {
        final state = flow.state.value;
        final route = state is FlowNavigating ? state.route : null;
        final step =
            previewed != null && route != null && previewed < route.steps.length
            ? route.steps[previewed]
            : null;
        final driven = route == null ? 0.0 : route.length - guidance.remaining;
        return _card(
          context,
          GoogleStyleManeuverHeader(
            state: guidance,
            formatter: widget.formatter,
            strings: widget.strings,
            colors: _colors,
            rerouting: flow.rerouting.value,
            previewStep: step,
            previewDistance: step == null
                ? 0
                : math.max(0, step.distance - driven),
            onTap: actions.showSteps,
            onNextStep: () => _previewBy(1),
            onPreviousStep: () => _previewBy(-1),
            margin: margin,
          ),
        );
      },
    );
  }

  bool get _hasReport =>
      widget.reportButtonEnabled && widget.onReportIncident != null;

  bool get _hasTopEnd =>
      widget.compassEnabled ||
      (widget.searchButtonEnabled && widget.searchAlongRoute != null) ||
      widget.onAudioGuidanceChanged != null ||
      widget.routeOverviewButtonEnabled ||
      _hasReport;

  /// The end column of map buttons, as in Google Maps: the report button,
  /// the compass, search, sound and route options, top to bottom, anchored
  /// 16 above the trip sheet (in the side panel layout, at the bottom end
  /// of the map area) and growing upwards, never into the header. While
  /// the search is open it hangs under the search bar instead, clear of
  /// the results at the bottom.
  Widget _topEnd(BuildContext context, NavigationFlowActions actions) {
    final colors = _colors;
    final strings = widget.strings;
    final onAudio = widget.onAudioGuidanceChanged;
    // When short of room the column drops search, then sound, then the
    // compass, then the report: route options stay reachable.
    final members = <(String, int, Widget)>[
      if (_hasReport)
        (
          'report',
          3,
          GoogleStyleReportButton(
            key: _memberKeys['report'],
            onPressed: _report,
            strings: strings,
            colors: colors,
          ),
        ),
      // Shown while following; hidden once the user has panned away.
      if (widget.compassEnabled && widget.session.follow)
        (
          'compass',
          2,
          _LiveCompass(
            key: _memberKeys['compass'],
            session: widget.session,
            strings: strings,
            colors: colors,
          ),
        ),
      // Hidden while the search is open.
      if (widget.searchButtonEnabled &&
          widget.searchAlongRoute != null &&
          !_searching)
        (
          'search',
          0,
          GoogleStyleRoundButton(
            key: _memberKeys['search'],
            icon: const Icon(Icons.search),
            tooltip: strings.searchAlongRoute,
            onPressed: _openSearch,
            colors: colors,
          ),
        ),
      // Kept while the sheet moves or is open, so the column does not
      // re-lay out as it fades; its pill closes as soon as the sheet leaves
      // its collapsed height, rather than keep the back for itself unseen.
      if (onAudio != null)
        (
          'sound',
          1,
          GoogleStyleSoundButton(
            key: _memberKeys['sound'],
            value: widget.audioGuidance,
            onChanged: onAudio,
            canOpen: !_sheetMoving && !_menuOpen,
            strings: strings,
            colors: colors,
            onOpenChanged: (open) {
              if (mounted && open != _pillOpen) {
                setState(() => _pillOpen = open);
              }
            },
          ),
        ),
      // The trip overview with the alternate routes, last; hidden while
      // the search is open, as the search button is.
      if (widget.routeOverviewButtonEnabled && !_searching)
        (
          'route_options',
          4,
          GoogleStyleRoundButton(
            key: _memberKeys['route_options'],
            icon: const Icon(Icons.alt_route),
            tooltip: strings.routeOptions,
            onPressed: actions.backToOverview,
            colors: colors,
          ),
        ),
    ];
    final ranks = [for (final (_, rank, _) in members) rank];
    final names = [for (final (name, _, _) in members) name];
    final column = GoogleStyleControlStack(
      itemExtent: _columnExtent,
      gap: _columnGap,
      priorities: ranks,
      children: [for (final (_, _, member) in members) member],
    );
    _scheduleMeasure();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // One tree shape in every mode, so a mode change keeps the members'
    // state (such as the report button's collapsed pill). The slot spans
    // from under the header (or the search bar) to 16 above the sheet; the
    // column sits at its bottom end, lifted above the bottom-start group
    // when a row would meet it, or at its top end while searching. The
    // empty room around lets touches through to the map.
    return _floating(
      LayoutBuilder(
        builder: (context, box) {
          final bounded = box.maxHeight.isFinite;
          // While the sheet is not collapsed the slot keeps its collapsed
          // height: the column fades in place, with the same members, and
          // the rising sheet covers it (the slot's top does not move).
          if (bounded && !_floatFrozen) _collapsedSlot = box.maxHeight;
          final collapsedSlot = _collapsedSlot;
          final height = !bounded
              ? null
              : _floatFrozen && collapsedSlot != null
              ? collapsedSlot
              : box.maxHeight;
          final lift = _searching || height == null
              ? 0.0
              : _liftFor(height, names, ranks, rtl: rtl);
          return OverflowBox(
            fit: OverflowBoxFit.deferToChild,
            alignment: AlignmentDirectional.topEnd,
            maxHeight: height,
            child: SizedBox(
              key: _slotKey,
              height: height,
              child: Padding(
                padding: EdgeInsets.only(bottom: lift),
                child: Align(
                  alignment: _searching
                      ? AlignmentDirectional.topEnd
                      : AlignmentDirectional.bottomEnd,
                  widthFactor: 1,
                  heightFactor: bounded ? null : 1,
                  child: column,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// How far to lift the end column in a slot [height] high so that none
  /// of its rows meets the bottom-start group: 0 when none would, else
  /// enough to end it 16 above the group's top. It looks at the rows the
  /// unlifted column would show (by [names] and [ranks]) at their last
  /// measured widths, against the group's last laid rect.
  double _liftFor(
    double height,
    List<String> names,
    List<int> ranks, {
    required bool rtl,
  }) {
    final slot = _slotRect;
    final group = _groupRect;
    if (slot == null || group == null) return 0;
    final fit = ((height + _columnGap) / (_columnExtent + _columnGap)).floor();
    final kept = GoogleStyleControlStack.keep(names.length, fit, ranks);
    final bottom = slot.top + height;
    for (var k = 0; k < kept.length; k++) {
      final rowBottom = bottom - k * (_columnExtent + _columnGap);
      final rowTop = rowBottom - _columnExtent;
      if (rowTop >= group.bottom || rowBottom <= group.top) continue;
      final width =
          _memberWidths[names[kept[kept.length - 1 - k]]] ?? _columnExtent;
      final left = rtl ? slot.left : slot.right - width;
      final right = rtl ? slot.left + width : slot.right;
      if (left < group.right + _columnGap / 2 &&
          right > group.left - _columnGap / 2) {
        return math.max(0, bottom - (group.top - _columnGap));
      }
    }
    return 0;
  }

  void _scheduleMeasure() {
    // While the sheet moves the floating controls keep their collapsed
    // geometry: nothing to measure (and no rebuild per frame).
    if (_measureScheduled || _floatFrozen) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _measure();
    });
  }

  /// Reads the slot's, the members' and the group's laid rects; rebuilds
  /// when one changed.
  void _measure() {
    final slot = _laidRect(_slotKey, visibleOnly: false);
    final group =
        _laidRect(_recenterKey, visibleOnly: true) ??
        _laidRect(_speedKey, visibleOnly: true);
    var changed = !_near(slot, _slotRect) || !_near(group, _groupRect);
    for (final MapEntry(key: name, value: key) in _memberKeys.entries) {
      final width = _laidRect(key, visibleOnly: false)?.width;
      if (width == null) continue;
      final old = _memberWidths[name];
      if (old == null || (old - width).abs() > 0.5) {
        _memberWidths[name] = width;
        changed = true;
      }
    }
    if (changed) {
      setState(() {
        _slotRect = slot;
        _groupRect = group;
      });
    }
  }

  static bool _near(Rect? a, Rect? b) =>
      (a == null) == (b == null) &&
      (a == null ||
          ((a.left - b!.left).abs() < 0.5 &&
              (a.top - b.top).abs() < 0.5 &&
              (a.right - b.right).abs() < 0.5 &&
              (a.bottom - b.bottom).abs() < 0.5));

  /// [key]'s laid rect on the screen; null when it is not laid out, empty
  /// or (when [visibleOnly]) off stage.
  static Rect? _laidRect(GlobalKey key, {required bool visibleOnly}) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    if (visibleOnly) {
      for (RenderObject? o = box.parent; o != null; o = o.parent) {
        if (o is RenderOffstage && o.offstage) return null;
      }
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// [child] faded out as the trip sheet expands, as Google Maps fades its
  /// floating controls: at opacity 1 - t, ignoring pointers once t > 0,
  /// and hidden at t = 1; it keeps its state meanwhile. While t > 0 it is
  /// pinned where it was with the sheet collapsed (the scaffold places the
  /// speed cluster on the sheet's top), so it fades in place under the
  /// rising sheet.
  Widget _floating(Widget child) => _PinWhileMoving(
    pinned: _floatFrozen,
    child: ValueListenableBuilder<double>(
      valueListenable: _sheetFraction,
      child: child,
      builder: (context, t, child) => Visibility(
        visible: t < 1,
        maintainState: true,
        child: IgnorePointer(
          ignoring: t > 0,
          child: Opacity(opacity: 1 - t, child: child),
        ),
      ),
    ),
  );

  void _onSheetFraction(double t) {
    if (!mounted) return;
    _sheetFraction.value = t;
    final moving = t > 0;
    if (moving == _sheetMoving) return;
    if (moving) {
      // Taken before the sheet's first taller layout reaches the scaffold.
      _heldOverlay ??= _bottomOverlay?.value;
      _floatFrozen = true;
    } else {
      // Released after the frame that lays the sheet out collapsed: the
      // scaffold publishes its overlay after that layout, before the next
      // build, so the view goes back to the same value without a blip.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_sheetMoving &&
            (_heldOverlay != null || _floatFrozen)) {
          setState(() {
            _heldOverlay = null;
            _floatFrozen = false;
          });
        }
      });
    }
    setState(() => _sheetMoving = moving);
  }

  Widget _footer(
    BuildContext context,
    TripProgress progress,
    bool rerouting,
    NavigationFlowActions actions,
  ) {
    if (!widget.footerEnabled) {
      // Keeps the bottom inset the sheet's own safe area gave.
      return const SafeArea(top: false, child: SizedBox.shrink());
    }
    final strings = widget.strings;
    final onShare = widget.onShareTrip;
    final onSettings = widget.onSettings;
    // In the side panel the sheet is a floating card with its own rounded
    // corners and shadow (no clip, which would cut the shadow).
    return GoogleStyleTripSheet(
      floating: _side,
      progress: progress,
      rerouting: rerouting,
      formatter: widget.formatter,
      strings: strings,
      colors: _colors,
      onClose: actions.end,
      onExpandedChanged: (open) {
        if (mounted && open != _menuOpen) setState(() => _menuOpen = open);
      },
      onFractionChanged: _onSheetFraction,
      // An open sound pill closes first, on its own back.
      backClosesMenu: !_pillOpen,
      // The Google Maps menu's order.
      actions: [
        if (onShare != null)
          GoogleStyleSheetAction(
            icon: Icons.record_voice_over,
            label: strings.shareTrip,
            onPressed: onShare,
          ),
        if (widget.searchAlongRoute != null)
          GoogleStyleSheetAction(
            icon: Icons.search,
            label: strings.searchAlongRoute,
            onPressed: _openSearch,
          ),
        GoogleStyleSheetAction(
          icon: Icons.format_list_bulleted,
          label: strings.directions,
          onPressed: actions.showSteps,
        ),
        GoogleStyleSheetAction(
          icon: Icons.traffic,
          label: strings.showTraffic,
          selected: _traffic,
          onPressed: () => setState(() => _traffic = !_traffic),
        ),
        GoogleStyleSheetAction(
          icon: Icons.satellite,
          label: strings.satellite,
          selected: _satellite,
          onPressed: () => setState(() => _satellite = !_satellite),
        ),
        if (onSettings != null)
          GoogleStyleSheetAction(
            icon: Icons.settings,
            label: strings.settings,
            onPressed: onSettings,
          ),
      ],
    );
  }

  Widget _searchOverlay() {
    final state = widget.flow.state.value;
    final search = widget.searchAlongRoute;
    if (state is! FlowNavigating || search == null) {
      return const SizedBox.shrink();
    }
    final guidance = widget.session.guidanceState;
    final onAddStop = widget.onAddStop;
    return GoogleStyleSearchAlongRoute(
      search: search,
      route: state.route,
      fromDistance: guidance == null
          ? 0
          : (state.route.length - guidance.remaining).clamp(
              0.0,
              state.route.length,
            ),
      formatter: widget.formatter,
      strings: widget.strings,
      colors: _colors,
      onResults: (places) {
        _places = places;
        if (mounted) setState(() => _focusedPlace = null);
        _drawPins();
      },
      focusedPlace: _focusedPlace,
      onFocus: _focusPlace,
      onAddStop: onAddStop == null
          ? null
          : (place) {
              onAddStop(place);
              // As Google does once a stop is added: back to guidance.
              _closeSearch(refollow: true);
            },
      onClose: () => _closeSearch(refollow: true),
      onBarHeight: (height) {
        if (mounted && height != _searchBarHeight) {
          setState(() => _searchBarHeight = height);
        }
      },
    );
  }

  /// The search overlay over the screen: in the side panel's column (where
  /// the header was) on a wide landscape screen, else full width.
  Widget _searchLayer(BuildContext context) {
    final overlay = Material(
      type: MaterialType.transparency,
      child: _searchOverlay(),
    );
    if (!_side) return Positioned.fill(child: overlay);
    final padding = MediaQuery.paddingOf(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    final start = ltr ? padding.left : padding.right;
    final width = NavigationFlowScaffold.sidePanelWidth(_size);
    return PositionedDirectional(
      start: start,
      top: 0,
      bottom: 0,
      // The overlay pads its bar by 8: the bar spans the panel.
      width: width + 16,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        child: overlay,
      ),
    );
  }

  // This screen reads its size as the flow scaffold does, from its
  // constraints, so the two agree on the side panel inside a pane.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      return _screen(context);
    },
  );

  Widget _screen(BuildContext context) {
    final formatter = widget.formatter;
    final strings = widget.strings;
    final scaffold = NavigationFlowScaffold(
      session: widget.session,
      flow: widget.flow,
      idleBuilder: widget.idleBuilder,
      onEnd: widget.onEnd,
      recenterAlignment: AlignmentDirectional.bottomStart,
      recenterReplacesSpeed: true,
      landscapeSidePanel: true,
      stepSheetColor: (night) => _colorsAt(night).surface,
      mapBuilder: _mapView,
      // In the side panel the panel and the sheets are floating cards with
      // their own corners and shadow (no clip, which would cut the shadow).
      panelBuilder: (context, state, actions) => GoogleStyleOverviewPanel(
        floating: _side,
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
      headerBuilder: _header,
      speedBuilder: widget.speedometerEnabled || widget.speedLimitIconEnabled
          ? (context, speed) => _floating(
              GoogleStyleSpeedCluster(
                key: _speedKey,
                info: speed,
                style: widget.speedLimitSignStyle,
                formatter: formatter,
                strings: strings,
                colors: _colors,
                showSpeed: widget.speedometerEnabled,
                showLimit: widget.speedLimitIconEnabled,
                speedometerVisible: _speedometerShown,
                onLimitTap: () =>
                    setState(() => _speedometerShown = !_speedometerShown),
                speedingMinor: widget.speedingMinor,
                speedingMajor: widget.speedingMajor,
              ),
            )
          : null,
      footerBuilder: _footer,
      edgeBuilder: widget.tripProgressBarEnabled
          ? (context, progress) => _size.height < _progressBarMinHeight
                ? const SizedBox.shrink()
                : GoogleStyleTripProgressBar(
                    fraction: progress.fraction,
                    colors: _colors,
                  )
          : null,
      topEndBuilder: _hasTopEnd ? _topEnd : null,
      // The report button heads the end column (topEndBuilder); there is
      // no bottom end piece, so the scaffold's lift beside the speed does
      // not apply here.
      arrivalHeaderBuilder: widget.headerEnabled
          ? (context, state) => _card(
              context,
              GoogleStyleManeuverHeader.arrival(
                destination: state.destination,
                lastRoad: lastRoadName(state.route),
                strings: strings,
                colors: _colors,
                margin: _side ? EdgeInsets.zero : const EdgeInsets.all(8),
              ),
            )
          : null,
      arrivalBuilder: (context, route, actions) {
        final state = widget.flow.state.value;
        return GoogleStyleArrivalSheet(
          floating: _side,
          route: route,
          destination: state is FlowArrived ? state.destination : null,
          strings: strings,
          colors: _colors,
          onDone: actions.end,
        );
      },
      stepListBuilder: (context, route, currentStep) => GoogleStyleStepList(
        route: route,
        currentStep: currentStep,
        formatter: formatter,
        colors: _colors,
      ),
      recenterBuilder: widget.recenterButtonEnabled
          ? (context, recenter) => _floating(
              GoogleStyleRecenterButton(
                key: _recenterKey,
                onPressed: recenter,
                strings: strings,
                colors: _colors,
              ),
            )
          : null,
    );
    final toast = _toast;
    final side = _side;
    _layerAboveSearch = _pillOpen || _menuOpen;
    // The system back closes the search (after the pill or the menu, which
    // close themselves) before it leaves the screen; the scaffold's own
    // back handling sits inside.
    return PopScope<Object?>(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_searching || _layerAboveSearch) return;
        _closeSearch(refollow: true);
      },
      child: Stack(
        children: [
          Positioned.fill(child: scaffold),
          if (_searching)
            Positioned.fill(
              // The keyboard shrinks the overlay (it sizes its results from
              // the room left), and its chips and field get a Material.
              child: Builder(
                builder: (context) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: MediaQuery.removeViewInsets(
                    context: context,
                    removeBottom: true,
                    child: Builder(
                      builder: (context) =>
                          Stack(children: [_searchLayer(context)]),
                    ),
                  ),
                ),
              ),
            ),
          if (toast != null)
            // Centred in the map area: beside the side panel when it shows.
            PositionedDirectional(
              start: _startOverlay(context),
              end: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SafeArea(
                  left: !side,
                  right: !side,
                  child: Align(
                    alignment: const Alignment(0, 0.55),
                    // Read out by a screen reader when it appears.
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        key: const ValueKey('google_style_toast'),
                        color: const Color(0xFF323232),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            toast,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The compass of [session]'s camera. The scaffold rebuilds its overlays
/// about once a second, too seldom for a needle, so it listens to the
/// session's frames itself and rebuilds only when the camera's bearing
/// changed by 1 degree or more; it also listens to
/// [FollowCamera.headingUpChanges], so a switch between heading up and north
/// up shows without a frame.
///
/// The bearing is the one the session's camera sends, not one read back
/// from the map: it is right while the camera follows the vehicle, which is
/// the only time the compass shows (a gesture that rotates the map stops
/// following and hides it).
class _LiveCompass extends StatefulWidget {
  const _LiveCompass({
    super.key,
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
  StreamSubscription<bool>? _modeSub;

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
    unawaited(_modeSub?.cancel());
    _sub = widget.session.frames.listen((_) => _sync());
    _modeSub = widget.session.camera.headingUpChanges.listen((_) => _sync());
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
    unawaited(_modeSub?.cancel());
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
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

/// Keeps [child] painted, and hit tested, where it was laid out the last
/// time it was not [pinned]: while pinned, a layout that moves it (the
/// scaffold stacks the speed cluster on the rising trip sheet) is undone
/// by a paint offset. Not pinned, it is a plain proxy.
class _PinWhileMoving extends SingleChildRenderObjectWidget {
  const _PinWhileMoving({required this.pinned, super.child});

  final bool pinned;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPinWhileMoving(pinned);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPinWhileMoving renderObject,
  ) => renderObject.pinned = pinned;
}

class _RenderPinWhileMoving extends RenderProxyBox {
  _RenderPinWhileMoving(this._pinned);

  bool _pinned;
  set pinned(bool value) {
    if (value == _pinned) return;
    _pinned = value;
    markNeedsPaint();
  }

  /// Where the box was on the screen at its last paint while not pinned.
  Offset? _anchor;

  /// The paint offset that keeps the child at [_anchor].
  Offset _shift = Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    // The box's own place: its ancestors' transforms, without [_shift].
    final origin = localToGlobal(Offset.zero);
    if (!_pinned) {
      _anchor = origin;
      _shift = Offset.zero;
    } else {
      _shift = (_anchor ??= origin) - origin;
    }
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
