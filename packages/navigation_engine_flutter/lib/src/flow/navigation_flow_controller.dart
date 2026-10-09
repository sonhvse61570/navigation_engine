import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'alternate_route.dart';
import 'alternate_routes_map.dart';
import 'navigation_flow_state.dart';
import 'place_label.dart';
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
  /// Creates a flow on [session], getting routes from [routeProvider].
  NavigationFlowController({
    required this.session,
    this.routeProvider,
    NightMode nightMode = NightMode.auto,
    DateTime Function() clock = DateTime.now,
    this.progressInterval = const Duration(seconds: 1),
    this.stepPreviewTimeout = const Duration(seconds: 10),
    this.fetchAlternatesOnReroute = true,
  }) : _nightMode = nightMode,
       _clock = clock {
    _frameSub = session.frames.listen(_onFrame);
    _eventSub = session.events.listen(_onEvent);
    _followSub = session.followChanges.listen(_onFollowChange);
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

  /// How long a step preview ([previewStep]) lasts without another
  /// [previewStep] call before it ends by itself.
  final Duration stepPreviewTimeout;

  /// Whether a reroute asks [routeProvider] (or the session's provider)
  /// for alternates to the new route. Each reroute then costs one more
  /// request, a `routes(maxAlternatives: 2)` call, besides the session's own
  /// reroute request; set it to false to save that request with a paid
  /// router, or with a UI that shows no alternates while navigating. The
  /// alternates of the trip's start are kept either way, until a reroute.
  final bool fetchAlternatesOnReroute;

  /// The camera zoom of a step preview.
  static const double stepPreviewZoom = 17;

  /// The camera tilt of a step preview, in degrees.
  static const double stepPreviewTilt = 45;

  final DateTime Function() _clock;

  /// How far (metres) an alternate must be from the current route to count
  /// as having left it.
  static const double alternateDivergenceThreshold = 30;

  /// How far (metres) past an alternate's divergence point the vehicle goes
  /// before the alternate is dropped.
  static const double alternatePassedMargin = 20;

  final _alternates = ValueNotifier<List<AlternateRoute>>(const []);

  /// The trip's alternates, with where each leaves the current route.
  List<_Alternate> _alts = const [];

  /// Bumped by every route change; an alternates request started under an
  /// older value is dropped.
  int _altGeneration = 0;
  bool _altRequestPending = false;
  DateTime? _lastAltRequestAt;

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
  late final StreamSubscription<bool> _followSub;
  final _previewedStep = ValueNotifier<int?>(null);
  Timer? _previewTimer;
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

  /// The last [preview] request, as it was passed: what [retry] repeats.
  ({
    GeoPoint to,
    GeoPoint? from,
    double? heading,
    int maxAlternatives,
    PlaceLabel? destination,
  })?
  _lastRequest;

  DateTime? _lastProgressAt;
  DateTime? _lastSpeedAt;
  int? _lastStepIndex;
  bool _disposed = false;

  /// Where the trip is: idle, loading, overview, navigating, arrived or
  /// error. Listen to it to show the matching UI.
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

  /// The index, in the navigating route's steps, of the step previewed with
  /// [previewStep]; null when no step is previewed.
  ValueListenable<int?> get previewedStep => _previewedStep;

  /// The routes the driver could switch to while navigating, fastest or
  /// not, each with its time difference; empty outside [FlowNavigating].
  ValueListenable<List<AlternateRoute>> get alternates => _alternates;

  /// Whether the overview shown is the running trip's own (entered through
  /// [backToOverview]); a UI shows 'Resume' instead of 'Start' then.
  bool get isTripOverview => _tripOverview;

  /// How [isNight] is decided: from the sun where the vehicle is (the
  /// default), or always day or night. Setting it updates [isNight] at once.
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
  /// state change. [destination] is carried on the overview, then on the
  /// trip's navigating and arrived states.
  Future<void> preview({
    required GeoPoint to,
    GeoPoint? from,
    double? heading,
    int maxAlternatives = 2,
    PlaceLabel? destination,
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
    _lastRequest = (
      to: to,
      from: from,
      heading: heading,
      maxAlternatives: maxAlternatives,
      destination: destination,
    );
    _alts = const [];
    _altGeneration++;
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
      _set(
        FlowOverview(
          routes.take(maxAlternatives + 1).toList(),
          0,
          destination: destination,
        ),
      );
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _set(FlowError(e, previous, to));
    }
  }

  /// Repeats the request that failed, with its origin, heading and
  /// alternatives: the last [preview] call, with its arguments as they were
  /// passed (a request without `from` again starts from the session's last
  /// fix). Like [preview] it goes through [FlowLoading] to [FlowOverview], or
  /// to a new [FlowError] with the same `previous`. Throws [StateError] (as a
  /// failed future) outside [FlowError].
  Future<void> retry() async {
    _checkNotDisposed();
    final request = _lastRequest;
    if (_state.value is! FlowError || request == null) {
      throw StateError('retry() needs FlowError');
    }
    return preview(
      to: request.to,
      from: request.from,
      heading: request.heading,
      maxAlternatives: request.maxAlternatives,
      destination: request.destination,
    );
  }

  /// Shows [routes] (best first) without a provider. Throws
  /// [ArgumentError] when empty, [RangeError] for a bad [selected], and,
  /// like [preview], [StateError] while navigating. [destination] is carried
  /// as in [preview].
  void previewRoutes(
    List<NavRoute> routes, {
    int selected = 0,
    PlaceLabel? destination,
  }) {
    _checkNotDisposed();
    if (_state.value is FlowNavigating) {
      throw StateError(
        'previewRoutes() while navigating: call backToOverview() first',
      );
    }
    if (routes.isEmpty) throw ArgumentError.value(routes, 'routes', 'empty');
    final overview = FlowOverview(routes, selected, destination: destination);
    _generation++;
    _tripOverview = false;
    _alts = const [];
    _altGeneration++;
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
    _set(FlowOverview(s.routes, index, destination: s.destination));
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
    final fromTripOverview = _tripOverview;
    final route = s.route;
    // The route the trip ran before this overview, when it resumes onto
    // another one.
    final previous = fromTripOverview && !identical(session.route, route)
        ? session.route
        : null;
    final drivenBefore = fromTripOverview
        ? (_distanceOn(session.route ?? route) ?? 0.0)
        : 0.0;
    // Resuming another route of the trip overview: the vehicle's place on
    // it, when it is one of the trip's alternates.
    final driven = fromTripOverview
        ? _onAlternate(route, drivenBefore)
        : drivenBefore;
    _tripOverview = false;
    _lastSpeedAt = null;
    _lastProgressAt = null;
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
    _altGeneration++;
    _alts = previous == null
        ? _measure(route, s.routes, driven)
        : [
            // As in selectAlternate: the route left is measured from the
            // vehicle on, as its start may lie behind the chosen route's.
            ..._measure(route, [previous], driven, from: drivenBefore),
            ..._measure(route, [
              for (final r in s.routes)
                if (!identical(r, previous)) r,
            ], driven),
          ];
    if (resume && session.guidanceState?.arrived == true) {
      _set(FlowArrived(route, destination: s.destination));
    } else {
      _set(
        FlowNavigating(route, destination: s.destination),
        drivenOnSwitch: driven,
      );
    }
    if (_state.value is FlowNavigating) _refreshAlternates(route, driven);
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
    _alts = const [];
    _altGeneration++;
    _set(const FlowIdle());
  }

  /// From navigating or arrived, back to an overview of the current route.
  /// The session keeps running, without following the vehicle; a reroute
  /// meanwhile updates the overview, and [start] resumes the trip. Throws
  /// [StateError] in other states.
  void backToOverview() {
    _checkNotDisposed();
    final (route, destination) = switch (_state.value) {
      FlowNavigating(:final route, :final destination) ||
      FlowArrived(:final route, :final destination) => (route, destination),
      _ => throw StateError('backToOverview() needs navigating or arrived'),
    };
    _generation++;
    _tripOverview = true;
    _set(
      FlowOverview(
        [route, for (final a in _alts) a.route],
        0,
        destination: destination,
      ),
    );
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

  /// Closes a route preview: from a [FlowOverview] that is not the trip
  /// overview, back to [FlowIdle], removing the route options from the map.
  /// The session is untouched (not stopped, no route set). Throws
  /// [StateError] in the trip overview (where [start] resumes the trip) and
  /// outside [FlowOverview].
  void closeOverview() {
    _checkNotDisposed();
    if (_state.value is! FlowOverview || _tripOverview) {
      throw StateError('closeOverview() needs a FlowOverview of a preview');
    }
    _generation++;
    _set(const FlowIdle());
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

  /// Switches the trip to alternate [index] at once
  /// ([NavigationSession.setRoute], no route request). The route left
  /// becomes an alternate while the vehicle has not passed where the two
  /// part. Throws [StateError] outside [FlowNavigating] and [RangeError]
  /// for a bad index.
  void selectAlternate(int index) {
    _checkNotDisposed();
    final s = _state.value;
    if (s is! FlowNavigating) {
      throw StateError('selectAlternate() needs FlowNavigating');
    }
    RangeError.checkValidIndex(index, _alternates.value, 'index');
    final chosen = _alternates.value[index].route;
    final old = s.route;
    final drivenOld = _distanceOn(old) ?? 0;
    // The vehicle's place on the chosen route: the same as on the old one
    // for routes from the same origin, not for a refetched alternate, which
    // starts where the vehicle was when it was fetched.
    final driven = _onAlternate(chosen, drivenOld);
    _generation++;
    _altGeneration++;
    session.setRoute(chosen);
    _staleFrame = session.frame;
    _rerouting.value = false;
    _alts = [
      ..._measure(chosen, [
        for (final a in _alts)
          if (!identical(a.route, chosen)) a.route,
      ], driven),
      // The old route is measured from the vehicle on: its start may lie
      // behind the chosen route's.
      ..._measure(chosen, [old], driven, from: drivenOld),
    ];
    // Before the state changes: the list must not still hold the chosen
    // route when listeners see the new state.
    _refreshAlternates(chosen, driven);
    _set(
      FlowNavigating(chosen, destination: s.destination),
      drivenOnSwitch: driven,
    );
  }

  /// Draws the alternates again on the session's current map; does nothing
  /// outside [FlowNavigating]. Call it after a map view attaches to the
  /// session (or is recreated) while navigating.
  void refreshAlternates() {
    _checkNotDisposed();
    if (_state.value is FlowNavigating) _drawAlternates();
  }

  /// The routes of [others] that leave [current] and are still ahead of a
  /// vehicle [driven] metres along it; each is sampled from [from] metres
  /// along itself.
  List<_Alternate> _measure(
    NavRoute current,
    Iterable<NavRoute> others,
    double driven, {
    double from = 0,
  }) => [
    for (final r in others)
      if (!identical(r, current))
        if (routeDivergence(
              current,
              r,
              threshold: alternateDivergenceThreshold,
              from: from,
            )
            case final d?)
          if (driven <= d.current + alternatePassedMargin)
            _Alternate(r, d.current, d.alternate, d.shift),
  ];

  /// Where a vehicle [driven] metres along the current route is on
  /// alternate [route]: by the mapping [routeDivergence] measured, so a
  /// refetched alternate, which starts where the vehicle was, is measured
  /// from its own start. [driven] itself when [route] is not one of the
  /// trip's alternates.
  double _onAlternate(NavRoute route, double driven) {
    for (final a in _alts) {
      if (identical(a.route, route)) {
        return a.positionAt(driven).clamp(0.0, route.length);
      }
    }
    return driven;
  }

  /// Drops the passed alternates and publishes the others with their time
  /// differences, for a vehicle [driven] metres along [route]; keeps the
  /// published list when [driven] is null (the frame still measures the
  /// previous route).
  void _refreshAlternates(NavRoute route, double? driven) {
    if (_alts.isEmpty) {
      _setAlternates(const []);
      return;
    }
    if (driven == null) return;
    _alts = [
      for (final a in _alts)
        if (driven <= a.onCurrent + alternatePassedMargin) a,
    ];
    final remaining = route.remainingDuration(driven);
    _setAlternates([
      for (final a in _alts)
        AlternateRoute(
          route: a.route,
          divergence: a.onAlternate,
          timeDelta: Duration(
            seconds:
                (a.route.remainingDuration(
                          a.positionAt(driven).clamp(0.0, a.route.length),
                        ) -
                        remaining)
                    .round(),
          ),
        ),
    ]);
  }

  void _setAlternates(List<AlternateRoute> next) {
    if (_sameAlternates(_alternates.value, next)) return;
    _alternates.value = List.unmodifiable(next);
    _drawAlternates();
  }

  static bool _sameAlternates(List<AlternateRoute> a, List<AlternateRoute> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].route, b[i].route) ||
          a[i].minutesDelta != b[i].minutesDelta) {
        return false;
      }
    }
    return true;
  }

  void _drawAlternates() {
    final map = switch (session.map) {
      final AlternateRoutesMap m => m,
      _ => null,
    };
    if (map == null) return;
    final list = _alternates.value;
    if (list.isEmpty) {
      _onMap('clearing alternate routes', map.clearAlternates);
    } else {
      _onMap(
        'showing alternate routes',
        () => map.showAlternates(list, onTap: _onAlternateTap),
      );
    }
  }

  // A tap on the map: guarded, as the drawing may be stale.
  void _onAlternateTap(int index) {
    if (_disposed || _state.value is! FlowNavigating) return;
    if (index < 0 || index >= _alternates.value.length) return;
    selectAlternate(index);
  }

  /// Asks for alternates after a reroute onto [route]: one request at a
  /// time, at most one per [NavigationSession.rerouteInterval]. The answer is
  /// dropped when the trip's route changed meanwhile; a failure leaves no
  /// alternates.
  void _requestAlternates(NavRoute route) {
    final provider = routeProvider ?? session.routeProvider;
    if (provider == null || _altRequestPending) return;
    final now = _clock();
    final last = _lastAltRequestAt;
    if (last != null && now.difference(last) < session.rerouteInterval) return;
    _lastAltRequestAt = now;
    _altRequestPending = true;
    final generation = _altGeneration;
    final from = session.lastFix?.position ?? route.points.first;
    unawaited(() async {
      try {
        final List<NavRoute> routes;
        try {
          routes = await provider.routes(
            from,
            route.points.last,
            heading: session.frame?.bearing,
            maxAlternatives: 2,
          );
        } catch (_) {
          // No alternates this time: the trip goes on without them.
          return;
        }
        if (_disposed || generation != _altGeneration) return;
        final s = _state.value;
        if (s is! FlowNavigating || !identical(s.route, route)) return;
        final driven = _distanceOn(route) ?? 0;
        _alts = _measure(route, routes, driven);
        _refreshAlternates(route, driven);
      } finally {
        _altRequestPending = false;
      }
    }());
  }

  /// Shows step [index] of the route being driven: follow is turned off and
  /// the camera moves once to the manoeuvre (zoom [stepPreviewZoom], tilt
  /// [stepPreviewTilt], the route's bearing there). The preview ends after
  /// [stepPreviewTimeout] without another call, on [endStepPreview], when
  /// the camera follows again (a Re-center), and when the route or the
  /// state changes (a reroute, an alternate, arrival, stop, the overview).
  /// Throws [StateError] outside [FlowNavigating] and [RangeError] for an
  /// index outside the route's steps.
  void previewStep(int index) {
    _checkNotDisposed();
    final s = _state.value;
    if (s is! FlowNavigating) {
      throw StateError('previewStep() needs FlowNavigating');
    }
    RangeError.checkValidIndex(index, s.route.steps, 'index');
    final step = s.route.steps[index];
    _previewTimer?.cancel();
    _previewTimer = Timer(stepPreviewTimeout, endStepPreview);
    _previewedStep.value = index;
    session.follow = false;
    final map = session.map;
    if (map == null) return;
    final target = CameraTarget(
      position: s.route.pointAt(step.distance),
      bearing: s.route.bearingAt(step.distance),
      zoom: stepPreviewZoom,
      tilt: stepPreviewTilt,
    );
    unawaited(
      Future.sync(() => map.moveCamera(target)).catchError(
        (Object e, StackTrace st) =>
            _reportMapError(e, st, 'moving the camera to a previewed step'),
      ),
    );
  }

  /// Ends a step preview and, unless [refollow] is false, makes the camera
  /// follow the vehicle again; does nothing when no step is previewed. Pass
  /// `refollow: false` when the user touches the map during a preview: the
  /// preview and its timer end, and the camera stays where the user moves
  /// it.
  void endStepPreview({bool refollow = true}) {
    if (_disposed) return;
    _endPreview(refollow: refollow);
  }

  void _endPreview({required bool refollow}) {
    if (_previewedStep.value == null) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewedStep.value = null;
    if (refollow) session.follow = true;
  }

  // Follow turned back on elsewhere (a Re-center) ends the preview. The
  // stream is async: a `true` queued before the preview began is stale.
  void _onFollowChange(bool follow) {
    if (follow && session.follow) _endPreview(refollow: false);
  }

  /// Stops listening. Leaves the session and the map alone.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_frameSub.cancel());
    unawaited(_eventSub.cancel());
    _nightTimer.cancel();
    _previewTimer?.cancel();
    unawaited(_followSub.cancel());
    _previewedStep.dispose();
    _state.dispose();
    _tripProgress.dispose();
    _speed.dispose();
    _isNight.dispose();
    _rerouting.dispose();
    _alternates.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NavigationFlowController was disposed');
  }

  /// The session's map, when it can preview routes.
  RoutePreviewMap? get _previewMap => switch (session.map) {
    final RoutePreviewMap m => m,
    _ => null,
  };

  /// Moves to [next]. [drivenOnSwitch] is the distance driven when the trip
  /// switches to another route mid-trip: the frame still measures the
  /// previous route then, so the first progress is taken from it.
  void _set(NavigationFlowState next, {double? drivenOnSwitch}) {
    final prev = _state.value;
    if (_previewedStep.value != null) {
      final sameRoute =
          next is FlowNavigating &&
          prev is FlowNavigating &&
          identical(next.route, prev.route);
      // An overview turns follow off itself.
      if (!sameRoute) _endPreview(refollow: next is! FlowOverview);
    }
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
      _publishProgress(next.route, force: true, drivenFallback: drivenOnSwitch);
    } else {
      if (next is FlowArrived || next is FlowIdle) _alts = const [];
      _tripProgress.value = null;
      _setAlternates(const []);
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
          _set(FlowArrived(s.route, destination: s.destination));
        }
      case OffRoute() || FixSourceError():
        break;
    }
  }

  void _onRerouted(NavRoute route) {
    _alts = const [];
    _altGeneration++;
    _staleFrame = session.frame;
    final s = _state.value;
    final destination = _destinationOf(s) ?? _destinationOf(_settled);
    if (s is FlowNavigating) {
      _set(FlowNavigating(route, destination: destination));
      if (fetchAlternatesOnReroute) _requestAlternates(route);
    } else if (_tripOverview) {
      // The trip's own overview follows the trip, also the one a pending
      // request or an error returns to, so [start] resumes the new route.
      final overview = FlowOverview([route], 0, destination: destination);
      if (s is FlowOverview) {
        _set(overview);
      } else if (s is FlowLoading || s is FlowError) {
        _settled = overview;
      }
    }
  }

  /// The destination label [s] carries, or the one of the state an error
  /// returns to.
  static PlaceLabel? _destinationOf(NavigationFlowState s) => switch (s) {
    FlowOverview(:final destination) ||
    FlowNavigating(:final destination) ||
    FlowArrived(:final destination) => destination,
    FlowError(:final previous) => _destinationOf(previous),
    FlowIdle() || FlowLoading() => null,
  };

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

  void _publishProgress(
    NavRoute route, {
    bool force = false,
    double? drivenFallback,
  }) {
    final now = _clock();
    final step = session.guidanceState?.stepIndex;
    final last = _lastProgressAt;
    final due =
        force ||
        last == null ||
        now.difference(last) >= progressInterval ||
        step != _lastStepIndex;
    if (!due) return;
    final measured = _distanceOn(route);
    final driven = (measured ?? drivenFallback ?? 0).clamp(0.0, route.length);
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
    _refreshAlternates(route, measured?.clamp(0.0, route.length));
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

/// An alternate and where it leaves the current route: [onCurrent] metres
/// along the current route, [onAlternate] metres along [route]. Before
/// that, a place `x` metres along the current route is `x + shift` metres
/// along [route].
final class _Alternate {
  const _Alternate(this.route, this.onCurrent, this.onAlternate, this.shift);
  final NavRoute route;
  final double onCurrent;
  final double onAlternate;
  final double shift;

  /// Where a vehicle [driven] metres along the current route is along
  /// [route]: on the shared road before the divergence, then as far past
  /// [onAlternate] as it is past [onCurrent].
  double positionAt(double driven) =>
      driven <= onCurrent ? driven + shift : onAlternate - (onCurrent - driven);
}
