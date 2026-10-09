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
///   the bottom start, 16 above the footer or the bottom inset, whichever
///   is higher; [topEndBuilder] below the header
///   on the end side; [edgeBuilder] on the start edge, between the header
///   and the footer;
/// - arrived: [arrivalBuilder] at the bottom.
///
/// Options a style may opt into (all off by default):
/// - a bottom end slot ([bottomEndBuilder]) while navigating, such as a
///   report button: 16 above the footer or the bottom inset at the end
///   side, and 16 above the bottom start group (the speed and the recenter
///   button) when the two would not fit side by side;
/// - an arrival header ([arrivalHeaderBuilder]): a card at the top while
///   arrived, given the arrived state and its destination;
/// - [recenterReplacesSpeed]: while it shows, the recenter button takes
///   the speed's place at the bottom start, and the speed hides;
/// - [landscapeSidePanel]: on a wide landscape screen the panel, the header
///   and the footer (or the arrival's header and panel) move to a column on
///   the start side, and the other pieces to the map area beside it.
///
/// The top end slot's height is bounded: it ends 16 above the bottom end
/// piece, or 16 above the footer or the bottom inset without one.
///
/// While idle or navigating, once the camera stopped following the vehicle
/// (the user moved the map), [recenterBuilder]'s button shows at
/// [recenterAlignment]; at the bottom start it stacks above the speed, or
/// sits beside it where the stack would reach into the header, and is
/// hidden where neither fits (see [recenterAlignment], also for the other
/// alignments). The map's own recenter button should be off.
///
/// Every piece keeps inside the safe area ([MediaQuery.paddingOf]): the
/// header slot and the pieces at the bottom take the insets of their edge,
/// the edge piece, the top end slot and the recenter button the side
/// insets (start and end follow the text direction). [footerBuilder],
/// [panelBuilder] and [arrivalBuilder] sit on the bottom edge and keep
/// their content above the bottom inset themselves (a [SafeArea]); the
/// speed and the recenter button sit 16 above them or above the bottom
/// inset, whichever is higher (a footer without a [SafeArea] lower than the
/// inset counts as the inset).
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
    this.bottomEndBuilder,
    this.arrivalHeaderBuilder,
    this.recenterReplacesSpeed = false,
    this.landscapeSidePanel = false,
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
  /// guidance, with the guarded [NavigationFlowActions] (as
  /// [topEndBuilder] gets them). It follows the session's guidance.
  final Widget Function(
    BuildContext context,
    GuidanceState guidance,
    NavigationFlowActions actions,
  )
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
  /// screen. Its height is bounded: it ends 16 above the bottom end piece
  /// ([bottomEndBuilder]), or 16 above the footer or the bottom inset
  /// without one; a style drops what does not fit. Nothing is shown when
  /// null.
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
  /// bottom start. At the bottom start, where the stack would reach into
  /// the header (a low screen, landscape, large text), the button sits
  /// beside the speed instead; where that does not fit either, it is hidden
  /// rather than overlap; it stays laid out off stage, so it comes back once
  /// it fits (a smaller text scale, a turn to portrait). The button is never
  /// shrunk. Before its first layout it counts as a 48 square.
  final AlignmentDirectional recenterAlignment;

  /// The space between the routes and the panel, the screen's sides and the
  /// top safe area in the overview.
  final double overviewMargin;

  /// The background of the step sheet, by day (false) or night (true). The
  /// open sheet follows [NavigationFlowController.isNight], like the step
  /// list in it. When null, the theme's bottom sheet colour is used.
  final Color Function(bool isNight)? stepSheetColor;

  /// Builds a piece at the bottom end while navigating, such as a report
  /// button: 16 above the footer or the bottom inset, inside the end inset;
  /// with the side panel, at the bottom end of the map area. The top end
  /// slot ends 16 above it. Where it and the bottom start group (the speed
  /// and the recenter button, by their sizes at the last layout) do not fit
  /// side by side with 16 around each, it sits 16 above that group instead.
  /// Nothing is shown when null. Do not combine it with a
  /// [recenterAlignment] at the bottom end.
  final Widget Function(BuildContext context, NavigationFlowActions actions)?
  bottomEndBuilder;

  /// Builds a card at the top while arrived, inside the top safe area (with
  /// the side panel, at the top of the column), given the arrived state
  /// (its route and destination). Nothing is shown when null.
  final Widget Function(BuildContext context, FlowArrived state)?
  arrivalHeaderBuilder;

  /// Whether the recenter button takes the speed's place while it shows, as
  /// in Google's navigation UI: the speed hides and the button sits at the
  /// bottom start, where [NavigationMapConfig.bottomOverlayHeight] counts it
  /// as it counts the speed. With a [recenterAlignment] other than the
  /// bottom start the speed still hides, and the button sits at that
  /// alignment instead. When false (the default) the button stacks above
  /// the speed (see [recenterAlignment]).
  final bool recenterReplacesSpeed;

  /// Whether a wide landscape screen ([usesSidePanel]) gets a side panel:
  /// the panel, the header and the footer (or the arrival's header and
  /// panel) in a column [sidePanelWidth] wide on the start side, with
  /// [sidePanelMargin] around them and the map visible between; the other
  /// pieces in the map area beside it, the speed and the recenter button at
  /// its bottom start (at any [recenterAlignment]). The overview padding
  /// and [NavigationMapConfig.startOverlayWidth] leave the column out, and
  /// [NavigationMapConfig.bottomOverlayHeight] is the height of the speed
  /// and recenter group in the map area (with its gap and the bottom inset).
  /// The footer takes at most 60 % of the column, or more when the header
  /// leaves the room empty (such as a header hidden while the footer shows
  /// a menu). Off by default: landscape keeps the bottom layout.
  final bool landscapeSidePanel;

  /// The least width of a landscape screen with a side panel.
  static const double sidePanelMinWidth = 600;

  /// The widest side panel.
  static const double sidePanelMaxWidth = 400;

  /// The side panel's share of the screen width, up to [sidePanelMaxWidth].
  static const double sidePanelFraction = 0.42;

  /// The space around the side panel's cards.
  static const double sidePanelMargin = 8;

  /// Whether [screen] is landscape and at least [sidePanelMinWidth] wide.
  static bool usesSidePanel(Size screen) =>
      screen.width > screen.height && screen.width >= sidePanelMinWidth;

  /// The side panel's width on [screen]: [sidePanelFraction] of its width,
  /// at most [sidePanelMaxWidth].
  static double sidePanelWidth(Size screen) =>
      math.min(sidePanelMaxWidth, screen.width * sidePanelFraction);

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

  StreamSubscription<bool>? _followSub;

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

  /// Whether the recenter button shows in the speed's place above the
  /// footer ([NavigationFlowScaffold.recenterReplacesSpeed], bottom layout),
  /// as last built: it then makes the band in bottomOverlayHeight.
  bool _recenterBand = false;

  /// Whether the side panel's map area shows its bottom start group (the
  /// speed and the recenter button), as last built.
  bool _sideStartShown = false;

  /// The sizes of the speed piece and of the recenter button at their last
  /// layout, read during layout (the notifiers above follow after the
  /// frame, to rebuild). The decisions use these, so they hold from the
  /// first frame after a layout. Null before the first one.
  Size? _speedLaidSize;
  Size? _recenterLaidSize;
  bool _bottomScheduled = false;

  /// The size of the bottom end piece at its last layout.
  final _bottomEndSize = ValueNotifier<Size>(Size.zero);
  Size? _bottomEndLaidSize;
  Size get _bottomEndBox => _bottomEndLaidSize ?? Size.zero;

  /// The size of the bottom start group (the speed and the recenter button
  /// beside or above it) at its last layout, for the bottom end piece's
  /// lift.
  final _bottomStartSize = ValueNotifier<Size>(Size.zero);
  Size _bottomStartLaidSize = Size.zero;

  /// The height of the arrival at its last layout, to rebuild the side
  /// panel's arrival header bound.
  final _arrivalHeight = ValueNotifier<double>(0);

  /// The width the side panel covers at the start, for the map.
  final _startOverlay = ValueNotifier<double>(0);

  /// Whether the side-panel layout is used, and the screen, as last built.
  bool _sideMode = false;
  Size _screen = Size.zero;

  /// The side panel's bottom piece takes at most this share of the column.
  static const double _sideBottomShare = 0.6;

  void _onBottomEndSize(Size size) {
    _bottomEndLaidSize = size;
    _afterFrame(_bottomEndSize, size);
  }

  void _onBottomStartSize(Size size) {
    _bottomStartLaidSize = size;
    _afterFrame(_bottomStartSize, size);
    if (_sideMode) _scheduleBottomOverlay();
  }

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
      _bottomEndSize,
      _bottomStartSize,
      _arrivalHeight,
    ]);
    flow.state.addListener(_syncFollowing);
  }

  void _subscribe(NavigationSession session) {
    unawaited(_followSub?.cancel());
    _followSub = session.followChanges.listen((_) => _syncFollowing());
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
    unawaited(_followSub?.cancel());
    _following.dispose();
    _headerHeight.dispose();
    _footerHeight.dispose();
    _speedSize.dispose();
    _recenterSize.dispose();
    _bottomOverlay.dispose();
    _bottomEndSize.dispose();
    _bottomStartSize.dispose();
    _arrivalHeight.dispose();
    _startOverlay.dispose();
    super.dispose();
  }

  /// Reads [NavigationSession.follow]: on each change the session reports
  /// ([NavigationSession.followChanges]: the app, the flow or a touch on the
  /// map view), with or without frames, and at once on a state change (the
  /// flow turns following on and off with it).
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
      // The speed's band sits on the slot or on the bottom inset, whichever
      // is higher, at the start, where maps put their attribution.
      final below = math.max(slot, _safe.bottom);
      // A speed piece that lays out empty shows nothing: no band.
      // Beside a side panel nothing covers the map's bottom but the group
      // at the start of the map area; a group that lays out empty shows
      // nothing.
      final startGroup = _bottomStartLaidSize.height;
      final recenter = _recenterLaidSize?.height ?? 0;
      _bottomOverlay.value = _sideMode
          ? (_sideStartShown && startGroup > 0
                ? _safe.bottom + _gap + startGroup
                : 0)
          : _speedShown && _speedLaid > 0
          ? below + _speedLaid + _gap
          : _recenterBand && recenter > 0
          ? below + recenter + _gap
          : slot;
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
      final EdgeInsets padding;
      if (_sideMode) {
        // The panel is beside the map: the routes fit in the map area.
        final side =
            2 * NavigationFlowScaffold.sidePanelMargin +
            NavigationFlowScaffold.sidePanelWidth(_screen);
        final ltr = _direction == TextDirection.ltr;
        padding = EdgeInsets.fromLTRB(
          _safe.left + m + (ltr ? side : 0),
          _safe.top + m,
          _safe.right + m + (ltr ? 0 : side),
          _safe.bottom + m,
        );
      } else {
        padding = EdgeInsets.fromLTRB(
          _safe.left + m,
          _safe.top + m,
          _safe.right + m,
          height + m,
        );
      }
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
    _afterFrame(_arrivalHeight, size.height);
    _scheduleBottomOverlay();
  }

  void _onSpeedSize(Size size) {
    _speedLaid = size.height;
    _speedLaidSize = size;
    _afterFrame(_speedSize, size);
    _scheduleBottomOverlay();
  }

  void _onRecenterSize(Size size) {
    _recenterLaidSize = size;
    _afterFrame(_recenterSize, size);
    if (widget.recenterReplacesSpeed) _scheduleBottomOverlay();
  }

  /// The speed piece's size for the decisions; zero before it was laid out.
  Size get _speed => _speedLaidSize ?? Size.zero;

  /// The recenter button's size for the decisions. Before it was ever laid
  /// out it counts as a 48 square, a touch target, so its first placement
  /// does not assume it takes no room.
  Size get _recenterBox =>
      _recenterLaidSize ?? const Size(_minRecenterHeight, _minRecenterHeight);

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
          color: widget.stepSheetColor,
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
    if (!mounted) return;
    _flow.refreshOverview();
    _flow.refreshAlternates();
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
                child: widget.mapBuilder(
                  context,
                  NavigationMapConfig(
                    isNight: _flow.isNight.value,
                    onRouteOptionTap: _onRouteOptionTap,
                    onMapReady: _onMapReady,
                    bottomOverlayHeight: _bottomOverlay,
                    startOverlayWidth: _startOverlay,
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
    final side =
        widget.landscapeSidePanel &&
        NavigationFlowScaffold.usesSidePanel(screen);
    if (side != _sideMode || screen != _screen) {
      _sideMode = side;
      _screen = screen;
      _schedulePadding();
    }
    // Only while the column shows something: idle keeps the plain layout
    // (the idle overlay), with nothing on the start side.
    final startOverlay = side && state is! FlowIdle
        ? _startInset +
              2 * NavigationFlowScaffold.sidePanelMargin +
              NavigationFlowScaffold.sidePanelWidth(screen)
        : 0.0;
    if (startOverlay != _startOverlay.value) {
      _afterFrame(_startOverlay, startOverlay);
    }
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
    // While it shows, the recenter button takes the speed's place.
    final replaced =
        widget.recenterReplacesSpeed &&
        recenter != null &&
        state is FlowNavigating;
    _bottomSlot = side
        ? null
        : switch (state) {
            FlowIdle() => null,
            FlowLoading() || FlowOverview() || FlowError() => _Slot.panel,
            FlowNavigating() =>
              _flow.tripProgress.value == null ? null : _Slot.footer,
            FlowArrived() => _Slot.arrival,
          };
    _speedShown =
        state is FlowNavigating &&
        _flow.speed.value != null &&
        widget.speedBuilder != null &&
        !replaced;
    _recenterBand = false;
    _scheduleBottomOverlay();
    if (side && state is! FlowIdle) {
      return _sideOverlays(
        context,
        state,
        screen,
        recenter,
        replaced: replaced,
      );
    }
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
            child: _panelPiece(context, state),
          ),
        ];
      case FlowNavigating():
        final progress = _flow.tripProgress.value;
        final topEnd = widget.topEndBuilder;
        final bottomEnd = widget.bottomEndBuilder;
        final edge = widget.edgeBuilder;
        final header = _headerHeight.value;
        // The footer keeps its content in the bottom safe area; without
        // one the safe area is kept free here.
        final footer = progress == null
            ? _safe.bottom
            : math.max(_footerHeight.value, _safe.bottom);
        final actions = _actions(state);
        final speedPiece = _speedPiece(context, replaced: replaced);
        // A speed piece that lays out empty (it shows nothing) leaves no
        // gap above it, and no band in bottomOverlayHeight; its padding
        // stays, so a speed that appears does not move.
        final hasSpeed = speedPiece != null && _speed.height > 0;
        final stackRecenter =
            recenter != null &&
            (recenterAtStart ||
                !_recenterFitsAboveFooter(
                  screen,
                  header: header,
                  footer: footer,
                  hasSpeed: hasSpeed,
                ));
        // At the bottom start: above the speed, else beside it when the
        // stack would reach into the header, else (it fits nowhere) hidden
        // rather than overlap.
        final startFit = stackRecenter
            ? _startFit(
                screen,
                header: header,
                footer: footer,
                hasSpeed: hasSpeed,
              )
            : _StartFit.hidden;
        final startRecenter = startFit == _StartFit.hidden ? null : recenter;
        _recenterBand = replaced && startRecenter != null;
        final ends = _endPlacement(
          screen,
          base: footer,
          rowStart: _startInset,
          startGroup: startRecenter != null || speedPiece != null,
        );
        return [
          Positioned(
            key: const ValueKey(_Slot.header),
            left: 0,
            right: 0,
            top: 0,
            child: _SizeReporter(
              onSize: _onHeaderSize,
              child: SafeArea(bottom: false, child: _guidancePiece(actions)),
            ),
          ),
          if (edge != null && progress != null)
            _edgePiece(
              edge(context, progress),
              start: _edgeMargin + _startInset,
              top: header + _gap,
              bottom: footer + _gap,
            ),
          if (topEnd != null)
            _topEndPiece(
              topEnd(context, actions),
              start: _gap + _startInset,
              top: header + _gap,
              maxHeight: screen.height - (header + _gap) - ends.topEndBottom,
            ),
          if (bottomEnd != null)
            _bottomEndPiece(bottomEnd(context, actions), bottom: ends.bottom),
          _bottom(
            recenter: startRecenter,
            recenterBeside: startFit == _StartFit.beside,
            speed: speedPiece,
            speedEmpty: !hasSpeed,
            footer: progress == null
                ? null
                : _footerPiece(context, progress, actions),
          ),
          // Hidden (it fits nowhere): still laid out, off stage, so its size
          // stays current and it comes back once it fits.
          if (recenter != null && stackRecenter && startFit == _StartFit.hidden)
            Offstage(key: const ValueKey(_Slot.measure), child: recenter),
          if (recenter != null && !stackRecenter)
            _recenterRegion(
              recenter,
              screen,
              top: header,
              bottom: _recenterLifted(screen, hasSpeed: hasSpeed)
                  ? footer + _speed.height + _gap
                  : footer,
            ),
        ];
      case final FlowArrived arrived:
        final arrivalHeader = widget.arrivalHeaderBuilder;
        return [
          if (arrivalHeader != null)
            Positioned(
              key: const ValueKey(_Slot.arrivalHeader),
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: arrivalHeader(context, arrived),
              ),
            ),
          Positioned(
            key: const ValueKey(_Slot.arrival),
            left: 0,
            right: 0,
            bottom: 0,
            child: _arrivalPiece(context, arrived),
          ),
        ];
    }
  }

  /// The landscape side-panel layout
  /// ([NavigationFlowScaffold.landscapeSidePanel]): the panel, the header
  /// and the footer, or the arrival's header and panel, in a column on the
  /// start side; the speed, the recenter button, the edge piece and the end
  /// pieces in the map area beside it. Each column piece scrolls inside the
  /// height left to it, so a low screen with large text does not overflow.
  List<Widget> _sideOverlays(
    BuildContext context,
    NavigationFlowState state,
    Size screen,
    Widget? recenter, {
    required bool replaced,
  }) {
    const m = NavigationFlowScaffold.sidePanelMargin;
    final width = NavigationFlowScaffold.sidePanelWidth(screen);
    final available = math.max(
      0.0,
      screen.height - _safe.top - _safe.bottom - 2 * m,
    );
    final areaStart = _startInset + 2 * m + width;
    final bottomMax = available * _sideBottomShare;
    _sideStartShown = false;
    Widget column(
      _Slot slot, {
      required bool top,
      required double maxHeight,
      required Widget child,
    }) => PositionedDirectional(
      key: ValueKey(slot),
      start: _startInset + m,
      width: width,
      top: top ? _safe.top + m : null,
      bottom: top ? null : _safe.bottom + m,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0.0, maxHeight)),
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: SingleChildScrollView(primary: false, child: child),
        ),
      ),
    );
    switch (state) {
      case FlowIdle():
        return const [];
      case FlowLoading() || FlowOverview() || FlowError():
        return [
          column(
            _Slot.panel,
            top: false,
            maxHeight: available,
            child: _panelPiece(context, state),
          ),
        ];
      case FlowNavigating():
        final progress = _flow.tripProgress.value;
        final topEnd = widget.topEndBuilder;
        final bottomEnd = widget.bottomEndBuilder;
        final edge = widget.edgeBuilder;
        final actions = _actions(state);
        // The footer's share, or the room the header leaves (a header
        // hidden while the footer shows a menu).
        final footerMax = math.max(
          bottomMax,
          available - _headerHeight.value - m,
        );
        final footer = progress == null
            ? 0.0
            : math.min(_footerLaid, footerMax);
        final speedPiece = _speedPiece(context, replaced: replaced);
        _sideStartShown = recenter != null || speedPiece != null;
        final ends = _endPlacement(
          screen,
          base: _safe.bottom,
          rowStart: areaStart,
          startGroup: recenter != null || speedPiece != null,
        );
        return [
          column(
            _Slot.header,
            top: true,
            maxHeight: available - (footer > 0 ? footer + m : 0),
            child: _SizeReporter(
              onSize: _onHeaderSize,
              child: _guidancePiece(actions),
            ),
          ),
          if (progress != null)
            column(
              _Slot.footer,
              top: false,
              maxHeight: footerMax,
              child: _footerPiece(context, progress, actions),
            ),
          if (edge != null && progress != null)
            _edgePiece(
              edge(context, progress),
              start: areaStart + _edgeMargin,
              top: _safe.top + _gap,
              bottom: _safe.bottom + _gap,
            ),
          if (topEnd != null)
            _topEndPiece(
              topEnd(context, actions),
              start: areaStart + _gap,
              top: _safe.top + _gap,
              maxHeight: screen.height - _safe.top - _gap - ends.topEndBottom,
            ),
          if (bottomEnd != null)
            _bottomEndPiece(bottomEnd(context, actions), bottom: ends.bottom),
          if (recenter != null || speedPiece != null)
            PositionedDirectional(
              key: const ValueKey(_Slot.bottom),
              start: areaStart + _gap,
              bottom: _safe.bottom + _gap,
              child: _SizeReporter(
                onSize: _onBottomStartSize,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?recenter,
                    if (recenter != null && speedPiece != null)
                      const SizedBox(height: 8),
                    ?speedPiece,
                  ],
                ),
              ),
            ),
        ];
      case final FlowArrived arrived:
        final header = widget.arrivalHeaderBuilder;
        final bottom = math.min(_arrivalLaid, bottomMax);
        return [
          if (header != null)
            column(
              _Slot.arrivalHeader,
              top: true,
              maxHeight: available - (bottom > 0 ? bottom + m : 0),
              child: header(context, arrived),
            ),
          column(
            _Slot.arrival,
            top: false,
            maxHeight: bottomMax,
            child: _arrivalPiece(context, arrived),
          ),
        ];
    }
  }

  // The pieces both layouts share.

  /// The panel of loading, the overview and an error, measured.
  Widget _panelPiece(BuildContext context, NavigationFlowState state) =>
      _SizeReporter(
        onSize: _onPanelSize,
        child: widget.panelBuilder(context, state, _actions(state)),
      );

  /// The header's content: [NavigationFlowScaffold.headerBuilder], once
  /// there is guidance, following it.
  Widget _guidancePiece(NavigationFlowActions actions) =>
      StreamBuilder<GuidanceState?>(
        stream: _session.guidance,
        initialData: _session.guidanceState,
        builder: (context, snapshot) {
          final guidance = snapshot.data;
          if (guidance == null) return const SizedBox.shrink();
          return widget.headerBuilder(context, guidance, actions);
        },
      );

  /// The trip footer, measured.
  Widget _footerPiece(
    BuildContext context,
    TripProgress progress,
    NavigationFlowActions actions,
  ) => _SizeReporter(
    onSize: _onFooterSize,
    child: widget.footerBuilder(
      context,
      progress,
      _flow.rerouting.value,
      actions,
    ),
  );

  /// The arrival panel, measured.
  Widget _arrivalPiece(BuildContext context, FlowArrived arrived) =>
      _SizeReporter(
        onSize: _onArrivalSize,
        child: widget.arrivalBuilder(context, arrived.route, _actions(arrived)),
      );

  /// The speed, measured; null when there is none, or when the recenter
  /// button [replaced] it.
  Widget? _speedPiece(BuildContext context, {required bool replaced}) {
    final speed = _flow.speed.value;
    final speedBuilder = widget.speedBuilder;
    if (replaced || speed == null || speedBuilder == null) return null;
    return _SizeReporter(
      onSize: _onSpeedSize,
      child: speedBuilder(context, speed),
    );
  }

  /// The edge piece at [start], between [top] and [bottom], at most
  /// [_edgeMaxWidth] wide.
  Widget _edgePiece(
    Widget child, {
    required double start,
    required double top,
    required double bottom,
  }) => PositionedDirectional(
    key: const ValueKey(_Slot.edge),
    start: start,
    top: top,
    bottom: bottom,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _edgeMaxWidth),
      child: child,
    ),
  );

  /// The top end slot at [top], at most [maxHeight] high. Both sides are
  /// anchored: the content is bounded by the width between [start] and the
  /// end margin, and sits at the end.
  Widget _topEndPiece(
    Widget child, {
    required double start,
    required double top,
    required double maxHeight,
  }) => PositionedDirectional(
    key: const ValueKey(_Slot.topEnd),
    start: start,
    end: _gap + _endInset,
    top: top,
    child: Align(
      alignment: AlignmentDirectional.topEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0.0, maxHeight)),
        child: child,
      ),
    ),
  );

  /// The bottom end piece, measured, [bottom] above the screen's bottom,
  /// inside the end inset.
  Widget _bottomEndPiece(Widget child, {required double bottom}) =>
      PositionedDirectional(
        key: const ValueKey(_Slot.bottomEnd),
        end: _gap + _endInset,
        bottom: bottom,
        child: _SizeReporter(onSize: _onBottomEndSize, child: child),
      );

  /// Where the bottom end piece's bottom sits and where the top end slot
  /// ends, both as distances from the screen's bottom, over [base] (the top
  /// of the footer or the bottom inset). The bottom end piece sits [_gap]
  /// above [base]; when it and the bottom start group ([startGroup]: the
  /// speed or the recenter button shows there) do not fit side by side in
  /// the row from [rowStart] to the end inset, with [_gap] around each, it
  /// sits [_gap] above that group instead. The top end slot ends [_gap]
  /// above the bottom end piece, or [_gap] above [base] without one. Uses
  /// their sizes at the last layout.
  ({double bottom, double topEndBottom}) _endPlacement(
    Size screen, {
    required double base,
    required double rowStart,
    required bool startGroup,
  }) {
    final above = base + _gap;
    if (widget.bottomEndBuilder == null) {
      return (bottom: above, topEndBottom: above);
    }
    final end = _bottomEndBox;
    final group = startGroup ? _bottomStartLaidSize : Size.zero;
    final rowEnd = screen.width - _endInset;
    final lifted =
        group.height > 0 &&
        rowStart + _gap + group.width + _gap + end.width + _gap > rowEnd;
    final bottom = lifted ? above + group.height + _gap : above;
    return (
      bottom: bottom,
      topEndBottom: end.height > 0 ? bottom + end.height + _gap : above,
    );
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
    final speedEnd = _startInset + _gap + _speed.width;
    final regionStart = _startInset + _gap;
    final regionWidth = screen.width - _startInset - _endInset - 2 * _gap;
    final free = math.max(0.0, regionWidth - _recenterBox.width);
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
        ? footer + _speed.height + _gap
        : footer;
    final room = screen.height - (header + _gap) - (bottom + _gap);
    return room >= _minRecenterHeight;
  }

  /// Where the recenter button goes at the bottom start, below the header:
  /// above the speed (8 between them); else, when that reaches into the
  /// header, beside the speed on its end side if that row fits the width
  /// and stays below the header; else nowhere. Uses their sizes at the last
  /// layout.
  _StartFit _startFit(
    Size screen, {
    required double header,
    required double footer,
    required bool hasSpeed,
  }) {
    final bandBottom = screen.height - footer - _gap;
    final recenter = _recenterBox;
    final speed = hasSpeed ? _speed : Size.zero;
    final stackHeight = recenter.height + (hasSpeed ? 8 + speed.height : 0);
    if (bandBottom - stackHeight >= header) return _StartFit.above;
    final rowWidth =
        _startInset +
        _gap +
        speed.width +
        8 +
        recenter.width +
        _gap +
        _endInset;
    final rowHeight = math.max(speed.height, recenter.height);
    if (hasSpeed &&
        rowWidth <= screen.width &&
        bandBottom - rowHeight >= header) {
      return _StartFit.beside;
    }
    return _StartFit.hidden;
  }

  /// The bottom of the screen: the recenter button and the speed at the
  /// start, [_gap] above the footer or the bottom safe area, whichever is
  /// higher.
  Widget _bottom({
    Widget? recenter,
    Widget? speed,
    Widget? footer,
    bool recenterBeside = false,
    bool speedEmpty = false,
  }) => Positioned(
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
              // One bottom rule with the recenter region and the edge:
              // max(footer, bottom inset) + gap, also for a footer
              // lower than the inset (one without a SafeArea).
              padding: EdgeInsetsDirectional.only(
                start: _gap + _startInset,
                // Always padded: an empty speed shows nothing anyway, and a
                // speed that appears is in place from its first frame.
                bottom:
                    _gap +
                    (footer == null
                        ? _safe.bottom
                        : math.max(0, _safe.bottom - _footerHeight.value)),
              ),
              // Measured for the bottom end piece's lift.
              child: _SizeReporter(
                onSize: _onBottomStartSize,
                child: recenterBeside && recenter != null && speed != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [speed, const SizedBox(width: 8), recenter],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ?recenter,
                          if (recenter != null && speed != null && !speedEmpty)
                            const SizedBox(height: 8),
                          ?speed,
                        ],
                      ),
              ),
            ),
          ),
        ?footer,
      ],
    ),
  );

  /// The recenter button at [NavigationFlowScaffold.recenterAlignment],
  /// between [top] and [bottom] with a [_gap] margin, inside the side safe
  /// area. While navigating it is used only when that space is at least
  /// [_minRecenterHeight] (see [_recenterFitsAboveFooter]; otherwise the
  /// button stacks at the bottom start). The top clamp, which lets the
  /// region reach up over [top] to keep [_minRecenterHeight], therefore
  /// only acts in idle, on a very low screen.
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

/// Where the recenter button goes at the bottom start.
enum _StartFit { above, beside, hidden }

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
  measure,
  arrival,
  bottomEnd,
  arrivalHeader,
}

/// The step list in a bottom sheet: the current step follows [session]'s
/// guidance, the list and the [color] follow [flow]'s night mode, and the
/// sheet closes itself once [flow] leaves the state it was [opened] in
/// (another kind of state, or another route).
class _StepSheet extends StatefulWidget {
  const _StepSheet({
    required this.flow,
    required this.session,
    required this.opened,
    required this.route,
    required this.builder,
    this.color,
  });

  final NavigationFlowController flow;
  final NavigationSession session;
  final NavigationFlowState opened;
  final NavRoute route;
  final Widget Function(BuildContext context, NavRoute route, int currentStep)
  builder;
  final Color Function(bool isNight)? color;

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

  /// The shape of the modal sheet, so the live background keeps it.
  static ShapeBorder? _shape(BuildContext context) {
    final theme = Theme.of(context).bottomSheetTheme;
    return theme.shape ??
        (Theme.of(context).useMaterial3
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              )
            : null);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // Rebuilt on a night switch: the list's colours and the background
    // follow it while the sheet is open.
    return ValueListenableBuilder<bool>(
      valueListenable: widget.flow.isNight,
      builder: (context, isNight, _) {
        final sheet = DraggableScrollableSheet(
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
        final color = widget.color;
        if (color == null) return sheet;
        return Material(
          key: const ValueKey('navigation_engine_step_sheet'),
          color: color(isNight),
          shape: _shape(context),
          clipBehavior: Clip.antiAlias,
          child: sheet,
        );
      },
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
