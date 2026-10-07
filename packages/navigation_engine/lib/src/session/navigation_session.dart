import 'dart:async';
import 'dart:math' as math;

import '../fix/fix_filter.dart';
import '../fix/fix_source.dart';
import '../fix/nav_fix.dart';
import '../geo/geo_point.dart';
import '../guidance/guidance_announcement.dart';
import '../guidance/guidance_state.dart';
import '../guidance/nav_guidance.dart';
import '../map/camera_target.dart';
import '../map/follow_camera.dart';
import '../map/navigation_map.dart';
import '../motion/free_motion_engine.dart';
import '../motion/motion_engine.dart';
import '../motion/motion_frame.dart';
import '../motion/route_motion_engine.dart';
import '../route/nav_route.dart';
import '../routing/route_provider.dart';
import 'session_event.dart';

/// Wires a [FixSource], the motion engine, the camera, guidance, an optional
/// [NavigationMap] and an optional [RouteProvider] into one navigation run.
///
/// The session has no clock of its own: call [tick] once per display frame
/// (from a Flutter `Ticker`, say). Everything else is event driven.
///
/// ```dart
/// final session = NavigationSession(fixes: source, map: map);
/// session.start(route: route);
/// ticker = createTicker((elapsed) { session.tick(dt); })..start();
/// session.announcements.listen((a) => tts.speak(formatter.announcement(a)));
/// ```
class NavigationSession {
  NavigationSession({
    required FixSource fixes,
    NavigationMap? map,
    this.routeProvider,
    FollowCamera? camera,
    FixFilter? filter,
    this.rerouteInterval = const Duration(seconds: 10),
    this.routeRefreshInterval = const Duration(seconds: 1),
    this.guidanceDistanceResolution = 5,
    DateTime Function() clock = DateTime.now,
  }) : _source = fixes,
       _map = map,
       camera = camera ?? FollowCamera(),
       _filter = filter ?? FixFilter(),
       _clock = clock;

  /// Longest frame step [tick] accepts, in seconds: after a long pause
  /// (app in background) the vehicle must not jump ahead.
  static const maxFrameDt = 0.1;

  final FixSource _source;
  NavigationMap? _map;
  final RouteProvider? routeProvider;
  final FollowCamera camera;
  final FixFilter _filter;
  final DateTime Function() _clock;

  /// Minimum time between two reroute requests.
  final Duration rerouteInterval;

  /// Minimum time between two route-line redraws.
  final Duration routeRefreshInterval;

  /// Metres the distance to the next step must change by before [guidance]
  /// emits again (step changes always emit).
  final double guidanceDistanceResolution;

  /// Whether the camera follows the vehicle. Turn it off while the user pans
  /// the map; frames, guidance and rerouting continue.
  bool follow = true;

  final _frames = StreamController<MotionFrame>.broadcast();
  final _guidance = StreamController<GuidanceState?>.broadcast();
  final _announcements = StreamController<GuidanceAnnouncement>.broadcast();
  final _events = StreamController<SessionEvent>.broadcast();

  StreamSubscription<NavFix>? _sub;
  bool _paused = false;
  bool _disposed = false;

  NavRoute? _route;
  MotionEngine _engine = FreeMotionEngine();
  NavGuidance? _navGuidance;
  GuidanceState? _guidanceState;
  GuidanceState? _emittedGuidance;

  /// Whether the last [guidance] emission was a state (not null).
  bool _guidanceShown = false;
  MotionFrame? _frame;
  NavFix? _lastFix;

  bool _cameraBusy = false;
  DateTime? _routeShownAt;
  bool _wasOffRoute = false;
  bool _arrived = false;
  bool _rerouting = false;
  DateTime? _lastRerouteAt;
  int _routeGeneration = 0;

  int _fixesAccepted = 0;
  int _fixesRejected = 0;
  int _cameraMoves = 0;
  int _cameraFramesSkipped = 0;

  /// Every frame produced by [tick].
  Stream<MotionFrame> get frames => _frames.stream;

  /// Guidance state, emitted when the step, the then-step or arrival changes,
  /// or when the distance to the step moved by [guidanceDistanceResolution].
  /// Emits null when guidance ends: the route was removed ([setRoute] with
  /// null, or [start] without a route) or the motion was reset
  /// ([resetMotion]). Hide the banner on null.
  Stream<GuidanceState?> get guidance => _guidance.stream;

  /// Prompts to speak, in order.
  Stream<GuidanceAnnouncement> get announcements => _announcements.stream;

  Stream<SessionEvent> get events => _events.stream;

  /// Between [start] and [stop], paused or not.
  bool get isRunning => _sub != null;

  /// The map the session draws on, or null to only compute. It can be
  /// swapped at any time, e.g. by a map view attaching itself while
  /// mounted: the new map gets the route line at once and the next camera
  /// update.
  NavigationMap? get map => _map;
  set map(NavigationMap? value) {
    if (identical(value, _map)) return;
    _map = value;
    _cameraBusy = false;
    _routeShownAt = null;
    final route = _route;
    if (value == null || _disposed) return;
    if (route == null) {
      // A map that outlived another session must not keep that one's route.
      value.clearRoute();
      return;
    }
    _routeShownAt = _clock();
    final (driven, ahead) = route.splitAt(_frame?.routeDistance ?? 0);
    value.showRoute(driven, ahead);
  }

  /// Between [pause] and [resume] (or [stop]).
  bool get isPaused => _paused;
  NavRoute? get route => _route;

  /// The latest frame (null until the first fix after [start] / [resetMotion]).
  MotionFrame? get frame => _frame;

  /// The latest guidance state (null without a route or before a frame).
  GuidanceState? get guidanceState => _guidanceState;

  /// The last fix that passed the filter.
  NavFix? get lastFix => _lastFix;

  SessionStats get stats => SessionStats(
    fixesAccepted: _fixesAccepted,
    fixesRejected: _fixesRejected,
    cameraMoves: _cameraMoves,
    cameraFramesSkipped: _cameraFramesSkipped,
  );

  /// Starts listening to the fix source (and starts it). Without a [route]
  /// the vehicle is followed freely, with no guidance. Does nothing when
  /// already running; throws [StateError] after [dispose].
  void start({NavRoute? route}) {
    if (_disposed) throw StateError('NavigationSession was disposed');
    if (_sub != null) return;
    _filter.reset();
    camera.reset();
    _lastFix = null;
    _frame = null;
    _cameraBusy = false;
    _lastRerouteAt = null;
    _paused = false;
    setRoute(route);
    _sub = _source.fixes.listen(
      _onFix,
      onError: (Object e, StackTrace st) => _emit(FixSourceError(e, st)),
    );
    _source.start();
  }

  /// Stops listening and stops the fix source. The state is kept; [start]
  /// begins a fresh run. A pending reroute is superseded: its outcome, success
  /// or failure, is dropped without an event.
  void stop() {
    final sub = _sub;
    if (sub == null) return;
    _sub = null;
    unawaited(sub.cancel());
    if (!_paused) _source.stop();
    _paused = false;
  }

  /// Stops the fix source but keeps the run: the route, the vehicle, the
  /// guidance progress and the subscription stay as they are, so [resume]
  /// carries on where it left off. [tick] may still be called: without
  /// fixes the vehicle slows to a stop. Does nothing when not running,
  /// already paused, or after [dispose].
  void pause() {
    if (_disposed || _sub == null || _paused) return;
    _paused = true;
    _source.stop();
  }

  /// Restarts the fix source after [pause]. Does nothing when not paused or
  /// after [dispose].
  void resume() {
    if (_disposed || _sub == null || !_paused) return;
    _paused = false;
    _source.start();
  }

  /// Stops and closes the streams. The fix source is stopped but not
  /// disposed: it belongs to the caller.
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    unawaited(_frames.close());
    unawaited(_guidance.close());
    unawaited(_announcements.close());
    unawaited(_events.close());
  }

  /// Switches to [route] (null: free driving): a new engine and guidance,
  /// fed the last fix so the vehicle stays where it is. The route line is
  /// drawn at once, before the first fix; removing the route clears it and
  /// emits a null [guidance] state. A pending reroute is superseded: its
  /// outcome, success or failure, is dropped without an event. Throws
  /// [StateError] after [dispose].
  void setRoute(NavRoute? route) {
    if (_disposed) throw StateError('NavigationSession was disposed');
    final hadGuidance = _guidanceShown;
    _route = route;
    _routeGeneration++;
    _rerouting = false;
    _engine = route == null ? FreeMotionEngine() : RouteMotionEngine(route);
    _navGuidance = route == null ? null : NavGuidance(route);
    _guidanceState = null;
    _emittedGuidance = null;
    _wasOffRoute = false;
    _arrived = false;
    _routeShownAt = null;
    final map = this.map;
    if (route == null) {
      map?.clearRoute();
    } else if (map != null) {
      // Visible before the first fix; the next redraw is a full
      // [routeRefreshInterval] away.
      _routeShownAt = _clock();
      final (driven, ahead) = route.splitAt(0);
      map.showRoute(driven, ahead);
    }
    if (route == null && hadGuidance) {
      _guidance.add(null);
      _guidanceShown = false;
    }
    final fix = _lastFix;
    if (fix != null) _engine.onFix(fix, _clock());
  }

  /// Forgets the vehicle's motion and guidance progress (after the position
  /// jumped, e.g. a simulator teleport). The next fix places it afresh.
  /// Throws [StateError] after [dispose].
  void resetMotion() {
    if (_disposed) throw StateError('NavigationSession was disposed');
    _filter.reset();
    _engine.reset();
    _navGuidance?.reset();
    camera.reset();
    _guidanceState = null;
    _emittedGuidance = null;
    if (_guidanceShown) {
      _guidance.add(null);
      _guidanceShown = false;
    }
    _lastFix = null;
    _frame = null;
    _wasOffRoute = false;
    _arrived = false;
  }

  void _onFix(NavFix fix) {
    if (_disposed) return;
    if (!_filter.accept(fix)) {
      _fixesRejected++;
      return;
    }
    _fixesAccepted++;
    _lastFix = fix;
    _engine.onFix(fix, _clock());
  }

  /// Advances by [dt] seconds (clamped to [maxFrameDt]): moves the vehicle,
  /// the camera, guidance, the route line, and reroutes when off route.
  void tick(double dt) {
    if (_disposed) return;
    final now = _clock();
    final step = dt > 0 ? math.min(dt, maxFrameDt) : 0.0;
    final frame = _engine.tick(step, now);
    if (frame == null) return;
    _frame = frame;
    _frames.add(frame);

    final target = camera.update(frame, step);
    if (follow) _moveCamera(target);

    final route = _route;
    final s = frame.routeDistance;
    if (route == null || s == null) return;
    _updateGuidance(s);
    _maybeShowRoute(route, s, now);
    if (frame.offRoute && !_wasOffRoute) _emit(const OffRoute());
    _wasOffRoute = frame.offRoute;
    if (frame.offRoute) _maybeReroute(route, now);
  }

  /// One camera update in flight at a time: when the renderer is slower than
  /// the display, queueing updates makes the map lag ever further behind,
  /// while dropping a frame is invisible.
  void _moveCamera(CameraTarget target) {
    final map = this.map;
    if (map == null) return;
    if (_cameraBusy) {
      _cameraFramesSkipped++;
      return;
    }
    _cameraBusy = true;
    _cameraMoves++;
    Future<void> pending;
    try {
      pending = map.moveCamera(target);
    } catch (_) {
      _cameraBusy = false;
      return;
    }
    unawaited(
      pending
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() => _cameraBusy = false),
    );
  }

  void _updateGuidance(double s) {
    final guidance = _navGuidance;
    if (guidance == null) return;
    final update = guidance.update(s);
    final state = update.state;
    _guidanceState = state;
    for (final a in update.announcements) {
      _announcements.add(a);
    }
    if (_guidanceChanged(state)) {
      _emittedGuidance = state;
      _guidanceShown = true;
      _guidance.add(state);
    }
    if (state.arrived && !_arrived) {
      _arrived = true;
      _emit(const Arrived());
    }
  }

  bool _guidanceChanged(GuidanceState s) {
    final prev = _emittedGuidance;
    return prev == null ||
        prev.stepIndex != s.stepIndex ||
        prev.arrived != s.arrived ||
        !identical(prev.thenStep, s.thenStep) ||
        (prev.distanceToStep - s.distanceToStep).abs() >=
            guidanceDistanceResolution;
  }

  void _maybeShowRoute(NavRoute route, double s, DateTime now) {
    final map = this.map;
    if (map == null) return;
    final shownAt = _routeShownAt;
    if (shownAt != null && now.difference(shownAt) < routeRefreshInterval) {
      return;
    }
    _routeShownAt = now;
    final (driven, ahead) = route.splitAt(s);
    map.showRoute(driven, ahead);
  }

  void _maybeReroute(NavRoute route, DateTime now) {
    final provider = routeProvider;
    final fix = _lastFix;
    if (provider == null ||
        fix == null ||
        _rerouting ||
        !isRunning ||
        _paused) {
      return;
    }
    final last = _lastRerouteAt;
    if (last != null && now.difference(last) < rerouteInterval) return;
    _rerouting = true;
    _lastRerouteAt = now;
    _emit(const Rerouting());
    unawaited(
      _reroute(
        provider,
        fix.position,
        route.points.last,
        _frame?.bearing,
        _routeGeneration,
      ),
    );
  }

  Future<void> _reroute(
    RouteProvider provider,
    GeoPoint from,
    GeoPoint to,
    double? heading,
    int generation,
  ) async {
    try {
      final next = await provider.route(from, to, heading: heading);
      if (_isStale(generation)) return;
      setRoute(next);
      _emit(Rerouted(next));
    } catch (e, st) {
      if (!_isStale(generation)) _emit(RerouteFailed(e, st));
    } finally {
      // A stale call must not release a newer call's guard.
      if (generation == _routeGeneration) _rerouting = false;
    }
  }

  /// The route was replaced, or the session stopped, since [generation].
  bool _isStale(int generation) =>
      _disposed || _sub == null || generation != _routeGeneration;

  void _emit(SessionEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
