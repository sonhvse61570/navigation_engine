import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'navigation_flow_state.dart';
import 'route_preview_map.dart';
import 'trip_progress.dart';

/// Drives a trip through overview → navigation → arrival on top of a
/// [NavigationSession], and publishes what a navigation UI shows: trip
/// progress, speed and limit, day or night, rerouting.
///
/// It owns no widgets: provider-styled UIs listen to it. It listens to the
/// session's frames and events but never ticks the session (the map view
/// does) and never disposes it (the app owns it).
///
/// ```dart
/// final flow = NavigationFlowController(session: session, routeProvider: osrm);
/// await flow.preview(to: destination); // FlowOverview
/// flow.select(1);
/// flow.start(); // FlowNavigating, then FlowArrived
/// ```
class NavigationFlowController {
  NavigationFlowController({
    required this.session,
    this.routeProvider,
    NightMode nightMode = NightMode.auto,
    DateTime Function() clock = DateTime.now,
    this.progressInterval = const Duration(seconds: 1),
  }) : _nightMode = nightMode,
       _clock = clock {
    _frameSub = session.frames.listen(_onFrame);
    _eventSub = session.events.listen(_onEvent);
    _nightTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateNight(),
    );
    _updateNight();
  }

  /// The session this flow drives. Owned by the app.
  final NavigationSession session;

  /// Where [preview] gets routes from.
  final RouteProvider? routeProvider;

  /// The most often [tripProgress] and [speed] change, apart from step
  /// changes.
  final Duration progressInterval;

  final DateTime Function() _clock;

  EdgeInsets _overviewPadding = const EdgeInsets.all(48);

  /// Space the UI covers around the map, for fitting routes in the
  /// overview. Set it from the UI's layout: a new value re-fits the routes
  /// while the overview is shown (without redrawing them or notifying
  /// [state]).
  EdgeInsets get overviewPadding => _overviewPadding;
  set overviewPadding(EdgeInsets value) {
    if (value == _overviewPadding) return;
    _overviewPadding = value;
    final s = _state.value;
    if (!_disposed && s is FlowOverview) _fitOverview(s);
  }

  final _state = ValueNotifier<NavigationFlowState>(const FlowIdle());
  final _tripProgress = ValueNotifier<TripProgress?>(null);
  final _speed = ValueNotifier<SpeedInfo?>(null);
  final _isNight = ValueNotifier<bool>(false);
  final _rerouting = ValueNotifier<bool>(false);

  late final StreamSubscription<MotionFrame> _frameSub;
  late final StreamSubscription<SessionEvent> _eventSub;
  late final Timer _nightTimer;
  NightMode _nightMode;
  int _generation = 0;

  /// The last state that was not loading or an error: what a failed
  /// request returns to.
  NavigationFlowState _settled = const FlowIdle();

  /// Whether the current overview (or the one a pending request or an error
  /// returns to) is the running trip's own, entered via [backToOverview].
  bool _tripOverview = false;

  /// The session's frame when the navigating route last changed: it still
  /// measures the previous route until the next tick.
  MotionFrame? _staleFrame;

  DateTime? _lastProgressAt;
  DateTime? _lastSpeedAt;
  int? _lastStepIndex;
  bool _disposed = false;

  ValueListenable<NavigationFlowState> get state => _state;

  /// Remaining distance, time and ETA; null unless navigating.
  ValueListenable<TripProgress?> get tripProgress => _tripProgress;

  /// Speed, and the limit while navigating; null before the first frame.
  /// It reflects the session's frames, so it stops updating when the
  /// session stops.
  ValueListenable<SpeedInfo?> get speed => _speed;

  /// Whether a night map style should be used; see [nightMode].
  ValueListenable<bool> get isNight => _isNight;

  /// True while the session is fetching a new route after going off route.
  ValueListenable<bool> get rerouting => _rerouting;

  /// Whether the overview shown is the running trip's own (entered through
  /// [backToOverview]); a UI shows 'Resume' instead of 'Start' then.
  bool get isTripOverview => _tripOverview;

  NightMode get nightMode => _nightMode;
  set nightMode(NightMode value) {
    _nightMode = value;
    _updateNight();
  }

  /// Requests routes to [to] and shows them: [FlowLoading], then
  /// [FlowOverview] with the best route selected. [from] defaults to the
  /// session's last fix. Fails into [FlowError] when there is no start
  /// point, no [routeProvider], no route, or the provider throws; the error's
  /// `previous` is the last state that was not loading or an error. A later
  /// call to any flow method supersedes a pending request; [cancel] drops
  /// it. Throws [StateError] while navigating (call [backToOverview] first)
  /// and [ArgumentError] when [maxAlternatives] is negative, before any
  /// state change.
  Future<void> preview({
    required GeoPoint to,
    GeoPoint? from,
    double? heading,
    int maxAlternatives = 2,
  }) async {
    _checkNotDisposed();
    if (maxAlternatives < 0) {
      throw ArgumentError.value(maxAlternatives, 'maxAlternatives');
    }
    if (_state.value is FlowNavigating) {
      throw StateError(
        'preview() while navigating: call backToOverview() first',
      );
    }
    final generation = ++_generation;
    final previous = _settled;
    final start = from ?? session.lastFix?.position;
    final provider = routeProvider;
    if (start == null) {
      _set(FlowError(StateError('No start point: no fix yet'), previous, to));
      return;
    }
    if (provider == null) {
      _set(FlowError(StateError('No routeProvider'), previous, to));
      return;
    }
    _set(FlowLoading(to));
    try {
      final routes = await provider.routes(
        start,
        to,
        heading: heading ?? (from == null ? session.lastFix?.heading : null),
        maxAlternatives: maxAlternatives,
      );
      if (_disposed || generation != _generation) return;
      if (routes.isEmpty) {
        _set(FlowError(StateError('No route found'), previous, to));
        return;
      }
      _tripOverview = false;
      _set(FlowOverview(routes.take(maxAlternatives + 1).toList(), 0));
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _set(FlowError(e, previous, to));
    }
  }

  /// Shows [routes] (best first) without a provider. Throws
  /// [ArgumentError] when empty, [RangeError] for a bad [selected], and,
  /// like [preview], [StateError] while navigating.
  void previewRoutes(List<NavRoute> routes, {int selected = 0}) {
    _checkNotDisposed();
    if (_state.value is FlowNavigating) {
      throw StateError(
        'previewRoutes() while navigating: call backToOverview() first',
      );
    }
    if (routes.isEmpty) throw ArgumentError.value(routes, 'routes', 'empty');
    final overview = FlowOverview(routes, selected);
    _generation++;
    _tripOverview = false;
    _set(overview);
  }

  /// Selects route [index] in the overview; selecting the selected route
  /// does nothing. Throws [StateError] outside [FlowOverview] and
  /// [RangeError] for a bad index.
  void select(int index) {
    _checkNotDisposed();
    final s = _state.value;
    if (s is! FlowOverview) throw StateError('select() needs FlowOverview');
    RangeError.checkValidIndex(index, s.routes, 'index');
    if (index == s.selected) return;
    _set(FlowOverview(s.routes, index));
  }

  /// Starts guidance along the selected route: [FlowNavigating]. The
  /// session is started, or switched to the route when already running,
  /// and follows the vehicle. When the session already runs this very route
  /// (the overview came from [backToOverview], possibly updated by a
  /// reroute), guidance resumes where it is, without resetting the session;
  /// if the vehicle arrived meanwhile, this goes straight to [FlowArrived].
  /// Call [stop] before replaying the same [NavRoute] instance from the start.
  /// Throws [StateError] outside [FlowOverview].
  void start() {
    _checkNotDisposed();
    final s = _state.value;
    if (s is! FlowOverview) throw StateError('start() needs FlowOverview');
    _generation++;
    _tripOverview = false;
    _lastSpeedAt = null;
    _lastProgressAt = null;
    final route = s.route;
    final resume = session.isRunning && identical(session.route, route);
    if (!resume) {
      if (session.isRunning) {
        session.setRoute(route);
      } else {
        session.start(route: route);
      }
      _staleFrame = session.frame;
      _rerouting.value = false;
    }
    session.follow = true;
    if (resume && session.guidanceState?.arrived == true) {
      _set(FlowArrived(route));
    } else {
      _set(FlowNavigating(route));
    }
  }

  /// Ends the trip from any state: stops the session, removes the route
  /// and goes back to [FlowIdle]. This stops the app's session too: to keep
  /// showing the vehicle afterwards, call `session.start()` again.
  void stop() {
    _checkNotDisposed();
    _generation++;
    _tripOverview = false;
    _lastSpeedAt = null;
    _lastProgressAt = null;
    session.stop();
    session.setRoute(null);
    _rerouting.value = false;
    _speed.value = null;
    _set(const FlowIdle());
  }

  /// From navigating or arrived, back to an overview of the current route.
  /// The session keeps running, without following the vehicle; a reroute
  /// meanwhile updates the overview, and [start] resumes the trip. Throws
  /// [StateError] in other states.
  void backToOverview() {
    _checkNotDisposed();
    final route = switch (_state.value) {
      FlowNavigating(:final route) || FlowArrived(:final route) => route,
      _ => throw StateError('backToOverview() needs navigating or arrived'),
    };
    _generation++;
    _tripOverview = true;
    _set(FlowOverview([route], 0));
  }

  /// Goes back to the state before the request: the "Cancel" / "OK" of a
  /// loading spinner or an error message. A pending request is dropped; an
  /// overview is shown again. The session is untouched. Throws
  /// [StateError] outside [FlowLoading] and [FlowError].
  void cancel() {
    _checkNotDisposed();
    final s = _state.value;
    if (s is! FlowLoading && s is! FlowError) {
      throw StateError('cancel() needs FlowLoading or FlowError');
    }
    _generation++;
    _set(_settled);
  }

  /// Shows the route options again and re-fits them on the session's
  /// current map; does nothing outside [FlowOverview]. Call it after a map
  /// view attaches to the session (or is recreated) while the overview is
  /// shown, so the new map draws the route options.
  void refreshOverview() {
    _checkNotDisposed();
    final s = _state.value;
    if (s is FlowOverview) _showOverview(s);
  }

  /// Stops listening. Leaves the session and the map alone.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_frameSub.cancel());
    unawaited(_eventSub.cancel());
    _nightTimer.cancel();
    _state.dispose();
    _tripProgress.dispose();
    _speed.dispose();
    _isNight.dispose();
    _rerouting.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NavigationFlowController was disposed');
  }

  /// The session's map, when it can preview routes.
  RoutePreviewMap? get _previewMap => switch (session.map) {
    final RoutePreviewMap m => m,
    _ => null,
  };

  void _set(NavigationFlowState next) {
    final prev = _state.value;
    if (prev is FlowOverview && next is! FlowOverview) {
      final preview = _previewMap;
      if (preview != null) {
        _onMap('clearing route options', preview.clearRouteOptions);
      }
    }
    if (next is FlowOverview) {
      session.follow = false;
      _showOverview(next);
    }
    if (next is FlowNavigating) {
      if (prev is! FlowNavigating) _lastStepIndex = null;
      _publishProgress(next.route, force: true);
    } else {
      _tripProgress.value = null;
    }
    // Before notifying: a listener may move the flow on.
    if (next is! FlowLoading && next is! FlowError) _settled = next;
    _state.value = next;
    _updateNight();
  }

  /// Draws [overview]'s options on the session's map and fits them.
  void _showOverview(FlowOverview overview) {
    final preview = _previewMap;
    if (preview == null) return;
    _onMap(
      'showing route options',
      () => preview.showRouteOptions(overview.routes, overview.selected),
    );
    _fitOverview(overview);
  }

  /// Fits [overview]'s routes inside [overviewPadding] on the session's map.
  void _fitOverview(FlowOverview overview) {
    final preview = _previewMap;
    if (preview == null) return;
    unawaited(
      Future.sync(
        () => preview.fitRoutes(overview.routes, _overviewPadding),
      ).catchError(
        (Object e, StackTrace st) =>
            _reportMapError(e, st, 'fitting routes in the overview'),
      ),
    );
  }

  void _reportMapError(Object e, StackTrace st, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'navigation_engine_flutter',
        context: ErrorDescription('while $what'),
      ),
    );
  }

  /// Runs a [RoutePreviewMap] call; an error is reported, not thrown, so a
  /// failing map never breaks the flow.
  void _onMap(String what, void Function() call) {
    try {
      call();
    } catch (e, st) {
      _reportMapError(e, st, what);
    }
  }

  void _onEvent(SessionEvent e) {
    switch (e) {
      case Rerouting():
        _rerouting.value = true;
      case Rerouted(:final route):
        _rerouting.value = false;
        // Stale when the route changed again before the event arrived.
        if (identical(session.route, route)) _onRerouted(route);
      case RerouteFailed():
        _rerouting.value = false;
      case Arrived():
        final s = _state.value;
        if (s is FlowNavigating &&
            session.guidanceState?.arrived == true &&
            identical(session.route, s.route)) {
          _set(FlowArrived(s.route));
        }
      case OffRoute() || FixSourceError():
        break;
    }
  }

  void _onRerouted(NavRoute route) {
    _staleFrame = session.frame;
    final s = _state.value;
    if (s is FlowNavigating) {
      _set(FlowNavigating(route));
    } else if (_tripOverview) {
      // The trip's own overview follows the trip, also the one a pending
      // request or an error returns to, so [start] resumes the new route.
      final overview = FlowOverview([route], 0);
      if (s is FlowOverview) {
        _set(overview);
      } else if (s is FlowLoading || s is FlowError) {
        _settled = overview;
      }
    }
  }

  /// Metres driven along [route], when the session's frame measures it:
  /// null when the session runs another route, or right after a route
  /// change, before the first frame on the new route.
  double? _distanceOn(NavRoute route) {
    final frame = session.frame;
    if (!identical(session.route, route) || identical(frame, _staleFrame)) {
      return null;
    }
    return frame?.routeDistance;
  }

  void _onFrame(MotionFrame frame) {
    final now = _clock();
    final s = _state.value;
    final route = s is FlowNavigating ? s.route : null;
    if (route != null) _publishProgress(route);
    final last = _lastSpeedAt;
    if (last == null || now.difference(last) >= progressInterval) {
      _lastSpeedAt = now;
      final d = route == null ? null : _distanceOn(route);
      _speed.value = SpeedInfo(
        speed: frame.speed,
        limit: route == null || d == null ? null : route.speedLimitAt(d),
      );
    }
  }

  void _publishProgress(NavRoute route, {bool force = false}) {
    final now = _clock();
    final step = session.guidanceState?.stepIndex;
    final last = _lastProgressAt;
    final due =
        force ||
        last == null ||
        now.difference(last) >= progressInterval ||
        step != _lastStepIndex;
    if (!due) return;
    final driven = (_distanceOn(route) ?? 0).clamp(0.0, route.length);
    final remaining = Duration(
      microseconds: (route.remainingDuration(driven) * 1e6).round(),
    );
    _lastProgressAt = now;
    _lastStepIndex = step;
    _tripProgress.value = TripProgress(
      remainingDistance: route.length - driven,
      remainingDuration: remaining,
      eta: now.add(remaining),
      fraction: route.length == 0 ? 1 : driven / route.length,
    );
  }

  void _updateNight() {
    if (_disposed) return;
    _isNight.value = switch (_nightMode) {
      NightMode.alwaysDay => false,
      NightMode.alwaysNight => true,
      NightMode.auto => _autoNight(),
    };
  }

  bool _autoNight() {
    final position = session.lastFix?.position ?? _routeOf(_state.value);
    if (position == null) return false;
    final now = _clock();
    return SunTimes.at(position, now).isNight(now);
  }

  static GeoPoint? _routeOf(NavigationFlowState s) => switch (s) {
    FlowOverview(:final route) ||
    FlowNavigating(:final route) ||
    FlowArrived(:final route) => route.points.first,
    FlowError(:final previous) => _routeOf(previous),
    FlowIdle() || FlowLoading() => null,
  };
}
