import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'navigation_flow_actions.dart';
import 'navigation_flow_controller.dart';
import 'navigation_flow_state.dart';
import 'navigation_map_config.dart';
import 'trip_progress.dart';

/// A navigation screen's flow binding, without a look: the map, and the
/// pieces a style builds, switched by [NavigationFlowController.state].
///
/// It shows, per state:
/// - idle: [idleBuilder]'s overlay, or nothing;
/// - loading, overview, error: [panelBuilder] at the bottom;
/// - navigating: [headerBuilder] at the top, inside the safe area (once
///   there is guidance); [footerBuilder] at the bottom; [speedBuilder] at
///   the bottom start, 16 above the footer; [topEndBuilder] below the header
///   on the end side; [edgeBuilder] on the start edge, between the header
///   and the footer;
/// - arrived: [arrivalBuilder] at the bottom.
///
/// While idle or navigating, once the camera stopped following the vehicle
/// (the user moved the map), [recenterBuilder]'s button shows at
/// [recenterAlignment]; at the bottom start it stacks above the speed (see
/// [recenterAlignment] for the other alignments). The map's own recenter
/// button should be off.
///
/// Every piece keeps inside the safe area ([MediaQuery.paddingOf]): the
/// header slot and the pieces at the bottom take the insets of their edge,
/// the edge piece, the top end slot and the recenter button the side
/// insets (start and end follow the text direction). [footerBuilder],
/// [panelBuilder] and [arrivalBuilder] sit on the bottom edge and keep
/// their content above the bottom inset themselves (a [SafeArea]); the
/// speed and the recenter button sit above them, or above the bottom inset
/// when there is no footer.
///
/// The pieces get [NavigationFlowActions], each guarded against stale
/// state. The scaffold also:
/// - measures the panel and sets [NavigationFlowController.overviewPadding]
///   to the panel's height plus [overviewMargin], the top and side insets
///   plus [overviewMargin] (only when it changes);
/// - gives the map the height of what covers its bottom (the panel, the
///   footer or the arrival, and the speed's band while the speed shows) as
///   [NavigationMapConfig.bottomOverlayHeight];
/// - redraws the overview when the map reports itself ready
///   ([NavigationMapConfig.onMapReady]);
/// - maps a back (the system back button or gesture): it leaves the screen
///   only while idle, navigating or arrived; otherwise loading and error
///   cancel, a route preview closes, and the trip overview resumes the trip;
/// - shows the step list ([stepListBuilder]) in a sheet that follows the
///   guidance and closes when the flow moves on (another kind of state, or
///   another route);
/// - builds the map ([mapBuilder]) only when the state or the night mode
///   changes, not for progress ticks.
///
/// The app owns, starts and disposes [session] and [flow].
class NavigationFlowScaffold extends StatefulWidget {
  /// Creates the flow binding of [flow] on [session].
  const NavigationFlowScaffold({
    super.key,
    required this.session,
    required this.flow,
    required this.mapBuilder,
    required this.panelBuilder,
    required this.headerBuilder,
    required this.footerBuilder,
    required this.arrivalBuilder,
    required this.stepListBuilder,
    this.recenterBuilder,
    this.speedBuilder,
    this.topEndBuilder,
    this.edgeBuilder,
    this.idleBuilder,
    this.onEnd,
    this.recenterAlignment = AlignmentDirectional.bottomStart,
    this.overviewMargin = 32,
    this.stepSheetColor,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Builds the map, which fills the screen under the pieces. It is built
  /// again only when the state or the night mode changes.
  final Widget Function(BuildContext context, NavigationMapConfig config)
  mapBuilder;

  /// Builds the bottom panel of loading, the overview and an error. Its
  /// height sets the overview padding.
  final Widget Function(
    BuildContext context,
    NavigationFlowState state,
    NavigationFlowActions actions,
  )
  panelBuilder;

  /// Builds the turn card at the top while navigating, once there is
  /// guidance. It follows the session's guidance.
  final Widget Function(BuildContext context, GuidanceState guidance)
  headerBuilder;

  /// Builds the trip footer at the bottom while navigating.
  final Widget Function(
    BuildContext context,
    TripProgress progress,
    bool rerouting,
    NavigationFlowActions actions,
  )
  footerBuilder;

  /// Builds the arrival panel at the bottom.
  final Widget Function(
    BuildContext context,
    NavRoute route,
    NavigationFlowActions actions,
  )
  arrivalBuilder;

  /// Builds the step list of [NavRoute] in the step sheet; `currentStep` is
  /// the guidance's step index on the route the session drives, else -1.
  final Widget Function(BuildContext context, NavRoute route, int currentStep)
  stepListBuilder;

  /// Builds the recenter button, which calls `recenter`. When null there is
  /// no recenter button, and no space is left for it.
  final Widget Function(BuildContext context, VoidCallback recenter)?
  recenterBuilder;

  /// Builds the speed (and limit) at the bottom start while navigating, once
  /// there is a speed. Nothing is shown when null.
  final Widget Function(BuildContext context, SpeedInfo speed)? speedBuilder;

  /// Builds the controls below the header on the end side while
  /// navigating, with the guarded [NavigationFlowActions]. Its width is
  /// bounded by the screen's width minus 32, so long content stays on the
  /// screen. Nothing is shown when null.
  final Widget Function(BuildContext context, NavigationFlowActions actions)?
  topEndBuilder;

  /// Builds a piece on the start edge, between the header and the footer,
  /// while navigating (such as a trip progress bar). Its width is bounded by
  /// 48. Nothing is shown when null.
  final Widget Function(BuildContext context, TripProgress progress)?
  edgeBuilder;

  /// Builds the overlay shown while the flow is idle, such as a search bar;
  /// it fills the screen above the map. Nothing is shown when null.
  final WidgetBuilder? idleBuilder;

  /// Called by [NavigationFlowActions.end]; when null it calls
  /// [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// Where the recenter button sits, above the footer and below the header.
  /// At [AlignmentDirectional.bottomStart] it stacks above the speed. At
  /// any other alignment its region ends 16 above the footer, beside
  /// the speed; when the two would share a row (the speed's end plus a gap
  /// passes the button's start at this alignment, by their sizes at the
  /// last layout), the
  /// region ends above the speed's band instead, so the button does not
  /// cover the speed however wide that grows (large text, narrow screens).
  /// The region is at least 48 high (a touch target): when that does not
  /// fit above the speed's band, the button stacks above the speed at the
  /// bottom start.
  final AlignmentDirectional recenterAlignment;

  /// The space between the routes and the panel, the screen's sides and the
  /// top safe area in the overview.
  final double overviewMargin;

  /// The background of the step sheet, by day (false) or night (true), as
  /// the sheet opens. When null, the theme's bottom sheet colour is used.
  final Color Function(bool isNight)? stepSheetColor;

  @override
  State<NavigationFlowScaffold> createState() => _NavigationFlowScaffoldState();
}

class _NavigationFlowScaffoldState extends State<NavigationFlowScaffold> {
  /// What the whole screen, the map included, depends on.
  late Listenable _screenListenable;

  /// What only the overlays depend on: they change while driving, the map
  /// does not.
  late Listenable _overlayListenable;

  /// Whether the camera follows the vehicle, as last seen on the session.
  final _following = ValueNotifier<bool>(true);

  /// The heights of the header slot (with the top safe area) and of the
  /// footer at their last layout.
  final _headerHeight = ValueNotifier<double>(0);
  final _footerHeight = ValueNotifier<double>(0);

  /// The sizes of the speed piece and of the recenter button at their last
  /// layout.
  final _speedSize = ValueNotifier<Size>(Size.zero);
  final _recenterSize = ValueNotifier<Size>(Size.zero);

  /// The height of what covers the bottom of the map (the panel, the footer
  /// or the arrival), given to the map ([NavigationMapConfig]).
  final _bottomOverlay = ValueNotifier<double>(0);

  StreamSubscription<MotionFrame>? _frameSub;

  /// The height of the panel at its last layout; null before.
  double? _panelHeight;

  /// The heights of the footer and the arrival at their last layout.
  double _footerLaid = 0;
  double _arrivalLaid = 0;

  /// Which slot covers the bottom of the map, as last built.
  _Slot? _bottomSlot;

  /// Whether the speed shows above the footer, as last built, and its
  /// height at its last layout.
  bool _speedShown = false;
  double _speedLaid = 0;
  bool _bottomScheduled = false;

  /// The safe area of the screen, as last built.
  EdgeInsets _safe = EdgeInsets.zero;
  TextDirection _direction = TextDirection.ltr;
  double get _topPadding => _safe.top;
  double get _startInset =>
      _direction == TextDirection.ltr ? _safe.left : _safe.right;
  double get _endInset =>
      _direction == TextDirection.ltr ? _safe.right : _safe.left;

  bool _paddingScheduled = false;

  NavigationFlowController get _flow => widget.flow;
  NavigationSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _listen(widget.flow);
    _subscribe(widget.session);
  }

  void _listen(NavigationFlowController flow) {
    _screenListenable = Listenable.merge([flow.state, flow.isNight]);
    _overlayListenable = Listenable.merge([
      flow.tripProgress,
      flow.speed,
      flow.rerouting,
      _following,
      _headerHeight,
      _footerHeight,
      _speedSize,
      _recenterSize,
    ]);
    flow.state.addListener(_syncFollowing);
  }

  void _subscribe(NavigationSession session) {
    unawaited(_frameSub?.cancel());
    _frameSub = session.frames.listen((_) => _syncFollowing());
    _following.value = session.follow;
  }

  @override
  void didUpdateWidget(NavigationFlowScaffold old) {
    super.didUpdateWidget(old);
    if (!identical(old.flow, widget.flow)) {
      old.flow.state.removeListener(_syncFollowing);
      _listen(widget.flow);
      _schedulePadding();
    }
    if (!identical(old.session, widget.session)) _subscribe(widget.session);
    if (old.overviewMargin != widget.overviewMargin) _schedulePadding();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePadding();
  }

  @override
  void dispose() {
    widget.flow.state.removeListener(_syncFollowing);
    unawaited(_frameSub?.cancel());
    _following.dispose();
    _headerHeight.dispose();
    _footerHeight.dispose();
    _speedSize.dispose();
    _recenterSize.dispose();
    _bottomOverlay.dispose();
    super.dispose();
  }

  /// Reads [NavigationSession.follow]: on each frame, on each state change
  /// (the flow turns following on and off) and on a touch on the map (the
  /// map view turns it off).
  void _syncFollowing() => _following.value = _session.follow;

  void _onPanelSize(Size size) {
    _panelHeight = size.height;
    _schedulePadding();
    _scheduleBottomOverlay();
  }

  // Publishes the height of the slot that covers the bottom of the map after
  // the frame, once its layout is known.
  void _scheduleBottomOverlay() {
    if (_bottomScheduled) return;
    _bottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomScheduled = false;
      if (!mounted) return;
      final slot = switch (_bottomSlot) {
        _Slot.panel => _panelHeight ?? 0,
        _Slot.footer => _footerLaid,
        _Slot.arrival => _arrivalLaid,
        _ => 0.0,
      };
      // The speed's band sits on the slot (or on the bottom inset without
      // a footer), at the start, where maps put their attribution.
      final below = _bottomSlot == null ? _safe.bottom : slot;
      _bottomOverlay.value = _speedShown ? below + _speedLaid + _gap : slot;
    });
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
      final m = widget.overviewMargin;
      final padding = EdgeInsets.fromLTRB(
        _safe.left + m,
        _safe.top + m,
        _safe.right + m,
        height + m,
      );
      if (padding != _flow.overviewPadding) _flow.overviewPadding = padding;
    });
  }

  // Header and footer sizes come from layout too: they are applied after
  // the frame, and only rebuild the overlays.
  void _onHeaderSize(Size size) => _afterFrame(_headerHeight, size.height);
  void _onFooterSize(Size size) {
    _footerLaid = size.height;
    _afterFrame(_footerHeight, size.height);
    _scheduleBottomOverlay();
  }

  void _onArrivalSize(Size size) {
    _arrivalLaid = size.height;
    _scheduleBottomOverlay();
  }

  void _onSpeedSize(Size size) {
    _speedLaid = size.height;
    _afterFrame(_speedSize, size);
    _scheduleBottomOverlay();
  }

  void _onRecenterSize(Size size) => _afterFrame(_recenterSize, size);

  void _afterFrame<T>(ValueNotifier<T> notifier, T value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notifier.value = value;
    });
  }

  // The actions: each one does nothing outside the states it applies to.

  void _select(int index) {
    if (_flow.state.value is FlowOverview) _flow.select(index);
  }

  void _start() {
    if (_flow.state.value is FlowOverview) _flow.start();
  }

  void _end() {
    final runs = switch (_flow.state.value) {
      FlowNavigating() || FlowArrived() => true,
      FlowOverview() => _flow.isTripOverview,
      _ => false,
    };
    if (runs) (widget.onEnd ?? _flow.stop)();
  }

  void _backToOverview() {
    final state = _flow.state.value;
    if (state is FlowNavigating || state is FlowArrived) {
      _flow.backToOverview();
    }
  }

  void _cancel() {
    final state = _flow.state.value;
    if (state is FlowLoading || state is FlowError) _flow.cancel();
  }

  void _close() {
    if (_flow.state.value is FlowOverview && !_flow.isTripOverview) {
      _flow.closeOverview();
    }
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
            library: 'navigation_engine_flutter',
            context: ErrorDescription('while retrying the route request'),
          ),
        ),
      ),
    );
  }

  void _recenter() {
    final state = _flow.state.value;
    if (state is! FlowNavigating && state is! FlowIdle) return;
    _session.follow = true;
    _following.value = true;
  }

  // The sheet follows the guidance, and closes itself when the flow moves
  // on (arrival, stop, reroute, another route).
  void _showSteps() {
    final opened = _flow.state.value;
    final route = switch (opened) {
      FlowOverview(:final route) || FlowNavigating(:final route) => route,
      _ => null,
    };
    if (route == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: widget.stepSheetColor?.call(_flow.isNight.value),
        builder: (context) => _StepSheet(
          flow: _flow,
          session: _session,
          opened: opened,
          route: route,
          builder: widget.stepListBuilder,
        ),
      ),
    );
  }

  NavigationFlowActions _actions(NavigationFlowState state) =>
      NavigationFlowActions(
        select: _select,
        start: _start,
        end: _end,
        backToOverview: _backToOverview,
        cancel: _cancel,
        close: state is FlowOverview && !_flow.isTripOverview ? _close : null,
        retry: _retry,
        showSteps: _showSteps,
        recenter: _recenter,
      );

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

  void _onMapReady() {
    if (mounted) _flow.refreshOverview();
  }

  @override
  Widget build(BuildContext context) {
    _safe = MediaQuery.paddingOf(context);
    _direction = Directionality.of(context);
    return ListenableBuilder(
      listenable: _screenListenable,
      builder: (context, _) {
        final state = _flow.state.value;
        return PopScope<Object?>(
          canPop: _canPop(state),
          onPopInvokedWithResult: _onPop,
          child: Stack(
            children: [
              // Built here, not with the overlays: progress ticks do not
              // rebuild the map.
              Positioned.fill(
                child: Listener(
                  // After the map view's own listener, which stops
                  // following on a touch.
                  onPointerDown: (_) => _syncFollowing(),
                  child: widget.mapBuilder(
                    context,
                    NavigationMapConfig(
                      isNight: _flow.isNight.value,
                      onRouteOptionTap: _onRouteOptionTap,
                      onMapReady: _onMapReady,
                      bottomOverlayHeight: _bottomOverlay,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _overlayListenable,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: _overlays(context, state, constraints.biggest),
                    ),
                  ),
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
    Size screen,
  ) {
    final showRecenter =
        (state is FlowNavigating || state is FlowIdle) && !_following.value;
    final recenterBuilder = widget.recenterBuilder;
    final recenter = showRecenter && recenterBuilder != null
        ? _SizeReporter(
            onSize: _onRecenterSize,
            child: recenterBuilder(context, _recenter),
          )
        : null;
    final recenterAtStart =
        widget.recenterAlignment == AlignmentDirectional.bottomStart;
    _bottomSlot = switch (state) {
      FlowIdle() => null,
      FlowLoading() || FlowOverview() || FlowError() => _Slot.panel,
      FlowNavigating() =>
        _flow.tripProgress.value == null ? null : _Slot.footer,
      FlowArrived() => _Slot.arrival,
    };
    _speedShown =
        state is FlowNavigating &&
        _flow.speed.value != null &&
        widget.speedBuilder != null;
    _scheduleBottomOverlay();
    switch (state) {
      case FlowIdle():
        final idle = widget.idleBuilder;
        return [
          if (idle != null)
            Positioned.fill(
              key: const ValueKey(_Slot.idle),
              child: Builder(builder: idle),
            ),
          if (recenter != null && recenterAtStart) _bottom(recenter: recenter),
          if (recenter != null && !recenterAtStart)
            _recenterRegion(
              recenter,
              screen,
              top: _topPadding,
              bottom: _safe.bottom,
            ),
        ];
      case FlowLoading() || FlowOverview() || FlowError():
        return [
          Positioned(
            key: const ValueKey(_Slot.panel),
            left: 0,
            right: 0,
            bottom: 0,
            child: _SizeReporter(
              onSize: _onPanelSize,
              child: widget.panelBuilder(context, state, _actions(state)),
            ),
          ),
        ];
      case FlowNavigating():
        final progress = _flow.tripProgress.value;
        final speed = _flow.speed.value;
        final speedBuilder = widget.speedBuilder;
        final topEnd = widget.topEndBuilder;
        final edge = widget.edgeBuilder;
        final header = _headerHeight.value;
        // The footer keeps its content in the bottom safe area; without
        // one the safe area is kept free here.
        final footer = progress == null
            ? _safe.bottom
            : math.max(_footerHeight.value, _safe.bottom);
        final actions = _actions(state);
        final speedPiece = speed == null || speedBuilder == null
            ? null
            : _SizeReporter(
                onSize: _onSpeedSize,
                child: speedBuilder(context, speed),
              );
        final stackRecenter =
            recenter != null &&
            (recenterAtStart ||
                !_recenterFitsAboveFooter(
                  screen,
                  header: header,
                  footer: footer,
                  hasSpeed: speedPiece != null,
                ));
        return [
          Positioned(
            key: const ValueKey(_Slot.header),
            left: 0,
            right: 0,
            top: 0,
            child: _SizeReporter(
              onSize: _onHeaderSize,
              child: SafeArea(
                bottom: false,
                child: StreamBuilder<GuidanceState?>(
                  stream: _session.guidance,
                  initialData: _session.guidanceState,
                  builder: (context, snapshot) {
                    final guidance = snapshot.data;
                    if (guidance == null) return const SizedBox.shrink();
                    return widget.headerBuilder(context, guidance);
                  },
                ),
              ),
            ),
          ),
          if (edge != null && progress != null)
            PositionedDirectional(
              key: const ValueKey(_Slot.edge),
              start: _edgeMargin + _startInset,
              top: header + _gap,
              bottom: footer + _gap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _edgeMaxWidth),
                child: edge(context, progress),
              ),
            ),
          if (topEnd != null)
            // Both sides anchored: the content is bounded by the width
            // minus the margins, and sits at the end.
            PositionedDirectional(
              key: const ValueKey(_Slot.topEnd),
              start: _gap + _startInset,
              end: _gap + _endInset,
              top: header + _gap,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: topEnd(context, actions),
              ),
            ),
          _bottom(
            recenter: stackRecenter ? recenter : null,
            speed: speedPiece,
            footer: progress == null
                ? null
                : _SizeReporter(
                    onSize: _onFooterSize,
                    child: widget.footerBuilder(
                      context,
                      progress,
                      _flow.rerouting.value,
                      actions,
                    ),
                  ),
          ),
          if (recenter != null && !stackRecenter)
            _recenterRegion(
              recenter,
              screen,
              top: header,
              bottom: _recenterLifted(screen, hasSpeed: speedPiece != null)
                  ? footer + _speedSize.value.height + _gap
                  : footer,
            ),
        ];
      case FlowArrived(:final route):
        return [
          Positioned(
            key: const ValueKey(_Slot.arrival),
            left: 0,
            right: 0,
            bottom: 0,
            child: _SizeReporter(
              onSize: _onArrivalSize,
              child: widget.arrivalBuilder(context, route, _actions(state)),
            ),
          ),
        ];
    }
  }

  static const double _gap = 16;
  static const double _edgeMargin = 8;
  static const double _edgeMaxWidth = 48;

  /// The least height of the recenter button's region: a touch target.
  static const double _minRecenterHeight = kMinInteractiveDimension;

  /// Whether the speed and the recenter button (away from the bottom
  /// start) would share a row at the bottom: the speed's end, plus a gap,
  /// passes the button's start. The button's start comes from
  /// [NavigationFlowScaffold.recenterAlignment] within its region, which
  /// spans the width minus the side insets and gaps. Uses their sizes at
  /// the last layout.
  bool _recenterLifted(Size screen, {required bool hasSpeed}) {
    if (!hasSpeed) return false;
    final speedEnd = _startInset + _gap + _speedSize.value.width;
    final regionStart = _startInset + _gap;
    final regionWidth = screen.width - _startInset - _endInset - 2 * _gap;
    final free = math.max(0.0, regionWidth - _recenterSize.value.width);
    final x = widget.recenterAlignment.start;
    final recenterStart = regionStart + free * (x + 1) / 2;
    return speedEnd + _gap > recenterStart;
  }

  /// Whether the recenter button (away from the bottom start) has a region
  /// at least [_minRecenterHeight] high between the header and the footer:
  /// above the speed's band when the two share a row, else beside the
  /// speed. When not, the button stacks above the speed at the bottom
  /// start.
  bool _recenterFitsAboveFooter(
    Size screen, {
    required double header,
    required double footer,
    required bool hasSpeed,
  }) {
    final bottom = _recenterLifted(screen, hasSpeed: hasSpeed)
        ? footer + _speedSize.value.height + _gap
        : footer;
    final room = screen.height - (header + _gap) - (bottom + _gap);
    return room >= _minRecenterHeight;
  }

  /// The bottom of the screen: the recenter button and the speed at the
  /// start, [_gap] above the footer (or above the bottom safe area when
  /// there is no footer).
  Widget _bottom({Widget? recenter, Widget? speed, Widget? footer}) =>
      Positioned(
        key: const ValueKey(_Slot.bottom),
        left: 0,
        right: 0,
        bottom: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recenter != null || speed != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: _gap + _startInset,
                    bottom: _gap + (footer == null ? _safe.bottom : 0),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ?recenter,
                      if (recenter != null && speed != null)
                        const SizedBox(height: 8),
                      ?speed,
                    ],
                  ),
                ),
              ),
            ?footer,
          ],
        ),
      );

  /// The recenter button at [NavigationFlowScaffold.recenterAlignment],
  /// between [top] and [bottom] with a [_gap] margin, inside the side safe
  /// area. The region is never lower than [_minRecenterHeight]: when the
  /// space is smaller, it reaches up over [top].
  Widget _recenterRegion(
    Widget recenter,
    Size screen, {
    required double top,
    required double bottom,
  }) => PositionedDirectional(
    key: const ValueKey(_Slot.recenter),
    start: _gap + _startInset,
    end: _gap + _endInset,
    top: math.max(
      0,
      math.min(top + _gap, screen.height - bottom - _gap - _minRecenterHeight),
    ),
    bottom: bottom + _gap,
    child: Align(alignment: widget.recenterAlignment, child: recenter),
  );
}

/// The scaffold's slots, as keys that cannot clash with the pieces' own.
enum _Slot {
  idle,
  panel,
  header,
  edge,
  topEnd,
  bottom,
  footer,
  recenter,
  arrival,
}

/// The step list in a bottom sheet: the current step follows [session]'s
/// guidance, and the sheet closes itself once [flow] leaves the state it was
/// [opened] in (another kind of state, or another route).
class _StepSheet extends StatefulWidget {
  const _StepSheet({
    required this.flow,
    required this.session,
    required this.opened,
    required this.route,
    required this.builder,
  });

  final NavigationFlowController flow;
  final NavigationSession session;
  final NavigationFlowState opened;
  final NavRoute route;
  final Widget Function(BuildContext context, NavRoute route, int currentStep)
  builder;

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
          builder: (context, snapshot) => widget.builder(
            context,
            widget.route,
            // Only the route the session drives has a current step.
            identical(session.route, widget.route)
                ? snapshot.data?.stepIndex ?? -1
                : -1,
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
