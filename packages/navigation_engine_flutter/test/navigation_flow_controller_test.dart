import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

class FakeFixSource implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  bool _running = false;
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void dispose() {}
  void add(NavFix fix) => _controller.add(fix);
}

class FakePreviewMap implements NavigationMap, RoutePreviewMap {
  final calls = <String>[];
  List<NavRoute>? options;
  int? selected;
  EdgeInsets? fitPadding;
  Object? fitError;

  @override
  Future<void> moveCamera(CameraTarget target) async {}
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) =>
      calls.add('showRoute');
  @override
  void clearRoute() => calls.add('clearRoute');
  @override
  void showRouteOptions(List<NavRoute> routes, int selected) {
    calls.add('showRouteOptions');
    options = routes;
    this.selected = selected;
  }

  @override
  void clearRouteOptions() {
    calls.add('clearRouteOptions');
    options = null;
  }

  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {
    calls.add('fitRoutes');
    fitPadding = padding;
    if (fitError != null) throw fitError!;
  }
}

/// Throws synchronously from every preview call.
class ThrowingPreviewMap extends FakePreviewMap {
  @override
  void showRouteOptions(List<NavRoute> routes, int selected) =>
      throw StateError('show failed');

  @override
  void clearRouteOptions() => throw StateError('clear failed');

  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) =>
      throw StateError('no controller');
}

/// A map that cannot preview routes.
class PlainMap implements NavigationMap {
  @override
  Future<void> moveCamera(CameraTarget target) async {}
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {}
  @override
  void clearRoute() {}
}

class FakeRouteProvider extends RouteProvider {
  FakeRouteProvider(this.handler);
  Future<List<NavRoute>> Function(GeoPoint from, GeoPoint to) handler;

  /// Calls to [routes] (the flow's requests; reroutes use [route]).
  var calls = 0;
  GeoPoint? lastFrom;
  int? lastMaxAlternatives;
  double? lastHeading;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await handler(from, to)).first;

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) {
    calls++;
    lastFrom = from;
    lastMaxAlternatives = maxAlternatives;
    lastHeading = heading;
    return handler(from, to);
  }
}

/// A session and a flow on a fake clock (13:00 UTC = 20:00 in Ho Chi Minh
/// City, after sunset), with helpers to drive them.
class Harness {
  Harness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.auto,
    Duration progressInterval = const Duration(seconds: 1),
    this.map,
  }) {
    session = NavigationSession(
      fixes: source,
      map: map ?? FakePreviewMap(),
      routeProvider: provider,
      clock: () => now,
    );
    flow = NavigationFlowController(
      session: session,
      routeProvider: provider,
      nightMode: nightMode,
      clock: () => now,
      progressInterval: progressInterval,
    );
    flow.state.addListener(() => states.add(flow.state.value));
  }

  final source = FakeFixSource();
  FakePreviewMap? map;
  late final NavigationSession session;
  late final NavigationFlowController flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);

  /// Every state the flow notified, in order.
  final states = <NavigationFlowState>[];

  FakePreviewMap get previewMap => session.map! as FakePreviewMap;

  NavFix fixOn(NavRoute route, double s, {double speed = 10}) => NavFix(
    position: route.pointAt(s),
    accuracy: 5,
    speed: speed,
    heading: route.bearingAt(s),
    time: now,
  );

  /// On [route] at 800 m for second 0, then 60 m to its right: off route.
  NavFix offRoute(NavRoute route, int s) {
    final on = route.pointAt(800.0 + s * 5);
    return NavFix(
      position: s == 0 ? on : offsetPoint(on, route.bearingAt(800) + 90, 60),
      accuracy: 5,
      speed: 5,
      time: now,
    );
  }

  /// Advances one 60 fps frame without delivering the session's streams.
  void tickFrame() {
    now = now.add(const Duration(microseconds: 16667));
    session.tick(1 / 60);
  }

  /// Runs [seconds] at 60 fps; [fixAt] may return a fix each second.
  Future<void> run(
    double seconds, {
    NavFix? Function(int second)? fixAt,
  }) async {
    final frames = (seconds * 60).round();
    for (var i = 0; i < frames; i++) {
      if (i % 60 == 0) {
        final fix = fixAt?.call(i ~/ 60);
        if (fix != null) source.add(fix);
      }
      tickFrame();
      await pumpEventQueue(times: 1);
    }
    await pumpEventQueue(times: 2);
  }

  /// Drives the vehicle over the last 40 m of [route] until it arrives.
  Future<void> arriveOn(NavRoute route) =>
      run(8, fixAt: (s) => fixOn(route, route.length - 40 + 8.0 * s, speed: 8));

  void dispose() {
    flow.dispose();
    session.dispose();
  }
}

/// Collects [FlutterError] reports until the test ends.
List<FlutterErrorDetails> collectFlutterErrors() {
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = old);
  return errors;
}

void main() {
  final route = sampleRoute;
  final alt = sampleRouteAlternatives.single;
  final from = route.points.first;
  final to = route.points.last;

  Harness harness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.auto,
    Duration progressInterval = const Duration(seconds: 1),
  }) {
    final h = Harness(
      provider: provider,
      nightMode: nightMode,
      progressInterval: progressInterval,
    );
    addTearDown(h.dispose);
    return h;
  }

  FakeRouteProvider both() => FakeRouteProvider((_, _) async => [route, alt]);
  FakeRouteProvider offline() =>
      FakeRouteProvider((_, _) => Future.error(Exception('offline')));

  group('preview', () {
    test('loads routes into an overview with the best one selected', () async {
      final provider = both();
      final h = harness(provider: provider);
      expect(h.flow.state.value, isA<FlowIdle>());
      h.flow.overviewPadding = const EdgeInsets.all(20);
      final done = h.flow.preview(from: from, to: to, maxAlternatives: 1);
      expect(h.flow.state.value, isA<FlowLoading>());
      await done;
      final s = h.flow.state.value as FlowOverview;
      expect(s.routes, [same(route), same(alt)]);
      expect(s.selected, 0);
      expect(s.route, same(route));
      expect(provider.lastMaxAlternatives, 1);
      expect(h.session.follow, isFalse);
      expect(h.previewMap.options, [same(route), same(alt)]);
      expect(h.previewMap.selected, 0);
      expect(h.previewMap.fitPadding, const EdgeInsets.all(20));
    });

    test('keeps at most maxAlternatives + 1 routes', () async {
      final h = harness(
        provider: FakeRouteProvider((_, _) async => [route, alt, alt]),
      );
      await h.flow.preview(from: from, to: to, maxAlternatives: 1);
      expect((h.flow.state.value as FlowOverview).routes, hasLength(2));
    });

    test('a negative maxAlternatives throws before any state change', () async {
      final provider = both();
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      final before = h.flow.state.value;
      h.states.clear();
      await expectLater(
        h.flow.preview(from: from, to: to, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(h.flow.state.value, same(before));
      expect(h.states, isEmpty);
      expect(provider.calls, 0);
    });

    test('starts from the last fix, with its heading', () async {
      final provider = both();
      final h = harness(provider: provider)..session.start();
      await h.run(2, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
      await h.flow.preview(to: to);
      expect(h.flow.state.value, isA<FlowOverview>());
      expect(provider.lastHeading, isNotNull);
    });

    test('fails without a start point, keeping the previous state', () async {
      final h = harness(provider: both());
      await h.flow.preview(to: to);
      final s = h.flow.state.value as FlowError;
      expect(s.error, isA<StateError>());
      expect(s.previous, isA<FlowIdle>());
      expect(s.to, to);
    });

    test('fails without a route provider', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      await h.flow.preview(from: from, to: alt.points[40]);
      final s = h.flow.state.value as FlowError;
      expect(s.error, isA<StateError>());
      expect(s.previous, isA<FlowOverview>());
      expect(s.to, alt.points[40]);
    });

    test('fails when the provider throws or finds nothing', () async {
      final provider = offline();
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      await h.flow.preview(from: from, to: to);
      final failed = h.flow.state.value as FlowError;
      expect(failed.error, isA<Exception>());
      expect(failed.previous, isA<FlowOverview>());
      expect(failed.to, to, reason: 'what to retry');
      expect(h.previewMap.options, isNull, reason: 'left the overview');

      provider.handler = (_, _) async => [];
      await h.flow.preview(from: from, to: to);
      final empty = h.flow.state.value as FlowError;
      expect(empty.error, isA<StateError>());
      expect(empty.previous, isA<FlowOverview>(), reason: 'not the error');
      expect(provider.calls, 2);
    });

    test('retry repeats the failed request as it was made', () async {
      final provider = offline();
      final h = harness(provider: provider);
      // A last fix elsewhere, which a retry must not start from.
      h.session.start();
      await h.run(1, fixAt: (_) => h.fixOn(alt, 300));
      expect(h.session.lastFix, isNotNull);
      final a = route.pointAt(1000);
      await h.flow.preview(from: a, to: to, heading: 90, maxAlternatives: 1);
      expect(h.flow.state.value, isA<FlowError>());
      provider.lastFrom = null;
      provider.lastHeading = null;
      provider.lastMaxAlternatives = null;

      await h.flow.retry();
      expect(provider.calls, 2);
      expect(provider.lastFrom, a);
      expect(provider.lastHeading, 90);
      expect(provider.lastMaxAlternatives, 1);
    });

    test('retry outside an error throws', () async {
      final h = harness(provider: both());
      await expectLater(h.flow.retry(), throwsStateError);
      h.flow.previewRoutes([route]);
      await expectLater(h.flow.retry(), throwsStateError);
      expect(h.flow.state.value, isA<FlowOverview>());
    });

    test('a retry that fails again keeps the error and its previous', () async {
      final provider = offline();
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      await h.flow.preview(from: from, to: to);
      final first = h.flow.state.value as FlowError;
      await h.flow.retry();
      final again = h.flow.state.value as FlowError;
      expect(again, isNot(same(first)));
      expect(again.previous, same(first.previous));
      expect(again.to, to);
      expect(provider.calls, 2);
    });

    test('a newer request or call supersedes a pending one', () async {
      final first = Completer<List<NavRoute>>();
      final provider = FakeRouteProvider((_, _) => first.future);
      final h = harness(provider: provider);
      final pending = h.flow.preview(from: from, to: to);
      provider.handler = (_, _) async => [alt];
      await h.flow.preview(from: from, to: to);
      first.complete([route]);
      await pending;
      expect((h.flow.state.value as FlowOverview).route, same(alt));

      final late = Completer<List<NavRoute>>();
      provider.handler = (_, _) => late.future;
      final again = h.flow.preview(from: from, to: to);
      h.flow.stop();
      late.complete([route]);
      await again;
      expect(h.flow.state.value, isA<FlowIdle>());
    });

    test('a superseded request keeps the last settled state', () async {
      final pending = Completer<List<NavRoute>>();
      final provider = FakeRouteProvider((_, _) => pending.future);
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      final first = h.flow.preview(from: from, to: to);
      provider.handler = (_, _) => Future.error(Exception('offline'));
      await h.flow.preview(from: from, to: to);
      expect((h.flow.state.value as FlowError).previous, isA<FlowOverview>());
      pending.complete([alt]);
      await first;
      expect(h.flow.state.value, isA<FlowError>(), reason: 'stale result');
    });

    test(
      'preview while navigating throws; back to the overview first',
      () async {
        final h = harness(provider: both());
        h.flow.previewRoutes([route]);
        h.flow.start();
        await expectLater(h.flow.preview(from: from, to: to), throwsStateError);
        expect(h.flow.state.value, isA<FlowNavigating>());
        h.flow.backToOverview();
        await h.flow.preview(from: from, to: to);
        expect((h.flow.state.value as FlowOverview).routes, hasLength(2));
      },
    );

    test('preview after arriving plans the next trip', () async {
      final h = harness(provider: both());
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.arriveOn(route);
      expect(h.flow.state.value, isA<FlowArrived>());
      await h.flow.preview(from: from, to: to);
      expect((h.flow.state.value as FlowOverview).routes, hasLength(2));
      expect(h.previewMap.options, hasLength(2));
    });

    test('previewRoutes shows given routes; empty or bad index throws', () {
      final h = harness();
      h.flow.previewRoutes([route, alt], selected: 1);
      expect((h.flow.state.value as FlowOverview).route, same(alt));
      expect(() => h.flow.previewRoutes([]), throwsArgumentError);
      expect(
        () => h.flow.previewRoutes([route], selected: 1),
        throwsRangeError,
      );
    });

    test('previewRoutes while navigating throws', () {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      expect(() => h.flow.previewRoutes([alt]), throwsStateError);
      expect((h.flow.state.value as FlowNavigating).route, same(route));
      expect(h.session.route, same(route));
    });
  });

  group('cancel', () {
    test('from loading drops the request and re-shows the overview', () async {
      final pending = Completer<List<NavRoute>>();
      final provider = FakeRouteProvider((_, _) => pending.future);
      final h = harness(provider: provider);
      h.flow.previewRoutes([route, alt], selected: 1);
      final overview = h.flow.state.value;
      final request = h.flow.preview(from: from, to: to);
      expect(h.flow.state.value, isA<FlowLoading>());
      expect(h.previewMap.options, isNull);
      h.previewMap.calls.clear();
      h.flow.cancel();
      expect(h.flow.state.value, same(overview));
      expect(h.previewMap.calls, ['showRouteOptions', 'fitRoutes']);
      expect(h.previewMap.options, [same(route), same(alt)]);
      expect(h.previewMap.selected, 1);
      pending.complete([alt]);
      await request;
      expect(h.flow.state.value, same(overview), reason: 'dropped');
      expect(provider.calls, 1);
    });

    test('from an error over an overview goes back to it', () async {
      final h = harness(provider: offline());
      h.flow.previewRoutes([route]);
      await h.flow.preview(from: from, to: to);
      expect(h.flow.state.value, isA<FlowError>());
      h.previewMap.calls.clear();
      h.flow.cancel();
      expect((h.flow.state.value as FlowOverview).route, same(route));
      expect(h.previewMap.calls, ['showRouteOptions', 'fitRoutes']);
      expect(h.session.follow, isFalse);
    });

    test('from an error over an arrival goes back to it', () async {
      final h = harness(provider: offline());
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.arriveOn(route);
      await h.flow.preview(from: from, to: to);
      expect((h.flow.state.value as FlowError).previous, isA<FlowArrived>());
      h.flow.cancel();
      expect((h.flow.state.value as FlowArrived).route, same(route));
      expect(h.session.isRunning, isTrue, reason: 'session untouched');
    });

    test('from an error over idle goes back to idle', () async {
      final h = harness();
      await h.flow.preview(from: from, to: to);
      h.flow.cancel();
      expect(h.flow.state.value, isA<FlowIdle>());
    });

    test('outside loading or an error throws', () {
      final h = harness();
      expect(h.flow.cancel, throwsStateError);
      h.flow.previewRoutes([route]);
      expect(h.flow.cancel, throwsStateError);
      h.flow.start();
      expect(h.flow.cancel, throwsStateError);
      expect(h.flow.state.value, isA<FlowNavigating>());
    });
  });

  group('closeOverview', () {
    test('leaves a preview overview for idle, session untouched', () {
      final h = harness();
      h.session.start();
      expect(h.session.isRunning, isTrue);
      h.flow.previewRoutes([route, alt]);
      h.previewMap.calls.clear();
      h.flow.closeOverview();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(h.previewMap.calls, ['clearRouteOptions']);
      expect(h.previewMap.options, isNull);
      expect(h.session.isRunning, isTrue, reason: 'session untouched');
      expect(h.session.route, isNull);
    });

    test('a stopped session stays stopped', () {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.closeOverview();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(h.session.isRunning, isFalse);
    });

    test('throws in the trip overview and outside an overview', () {
      final h = harness();
      expect(h.flow.closeOverview, throwsStateError, reason: 'idle');
      h.flow.previewRoutes([route]);
      h.flow.start();
      expect(h.flow.closeOverview, throwsStateError, reason: 'navigating');
      h.flow.backToOverview();
      expect(h.flow.closeOverview, throwsStateError, reason: 'trip overview');
      expect(h.flow.state.value, isA<FlowOverview>());
      expect(h.session.route, same(route));
    });
  });

  group('overview', () {
    test('select re-highlights; checks the state and the index', () {
      final h = harness();
      expect(() => h.flow.select(0), throwsStateError);
      h.flow.previewRoutes([route, alt]);
      h.previewMap.calls.clear();
      h.flow.select(1);
      expect((h.flow.state.value as FlowOverview).route, same(alt));
      expect(h.previewMap.selected, 1);
      expect(h.previewMap.calls, ['showRouteOptions', 'fitRoutes']);
      expect(() => h.flow.select(2), throwsRangeError);
    });

    test('selecting the selected route does nothing', () {
      final h = harness();
      h.flow.previewRoutes([route, alt], selected: 1);
      final before = h.flow.state.value;
      h.previewMap.calls.clear();
      h.states.clear();
      h.flow.select(1);
      expect(h.flow.state.value, same(before));
      expect(h.previewMap.calls, isEmpty);
      expect(h.states, isEmpty);
      expect(() => h.flow.select(-1), throwsRangeError);
    });

    test('works with a map that cannot preview routes', () {
      for (final map in <NavigationMap?>[PlainMap(), null]) {
        final h = harness();
        h.session.map = map;
        h.flow.previewRoutes([route, alt]);
        h.flow.select(1);
        h.flow.refreshOverview();
        h.flow.overviewPadding = const EdgeInsets.all(8);
        h.flow.start();
        expect(h.flow.state.value, isA<FlowNavigating>());
      }
    });

    test('a failing fitRoutes is reported, not thrown', () async {
      final h = harness();
      h.previewMap.fitError = StateError('map gone');
      final errors = collectFlutterErrors();
      h.flow.previewRoutes([route]);
      await pumpEventQueue();
      expect(errors.single.exception, isA<StateError>());
      expect(h.flow.state.value, isA<FlowOverview>());
    });

    test('map calls that throw synchronously are reported', () async {
      final h = harness();
      h.session.map = ThrowingPreviewMap();
      final errors = collectFlutterErrors();
      h.flow.previewRoutes([route, alt]);
      await pumpEventQueue();
      expect(errors.map((e) => '${e.exception}'), [
        contains('show failed'),
        contains('no controller'),
      ]);
      expect(h.flow.state.value, isA<FlowOverview>());
      h.flow.select(1);
      expect((h.flow.state.value as FlowOverview).selected, 1);

      await pumpEventQueue();
      errors.clear();
      h.flow.refreshOverview();
      h.flow.overviewPadding = const EdgeInsets.all(8);
      await pumpEventQueue();
      expect(errors.map((e) => '${e.exception}'), [
        contains('show failed'),
        contains('no controller'),
        contains('no controller'),
      ]);

      errors.clear();
      h.flow.start();
      expect(errors.map((e) => '${e.exception}'), [contains('clear failed')]);
      expect(h.flow.state.value, isA<FlowNavigating>());
    });

    test('a new overviewPadding re-fits the overview, nothing else', () {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.previewMap.calls.clear();
      h.states.clear();
      h.flow.overviewPadding = const EdgeInsets.all(10);
      expect(h.flow.overviewPadding, const EdgeInsets.all(10));
      expect(h.previewMap.calls, ['fitRoutes']);
      expect(h.previewMap.fitPadding, const EdgeInsets.all(10));
      expect(h.states, isEmpty);
      h.previewMap.calls.clear();
      h.flow.overviewPadding = const EdgeInsets.all(10);
      expect(h.previewMap.calls, isEmpty, reason: 'unchanged');
    });

    test('overviewPadding outside the overview is kept for the next', () {
      final h = harness();
      h.flow.overviewPadding = const EdgeInsets.all(10);
      expect(h.previewMap.calls, isEmpty);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.previewMap.calls.clear();
      h.flow.overviewPadding = const EdgeInsets.all(20);
      expect(h.previewMap.calls, isEmpty);
      h.flow.backToOverview();
      expect(h.previewMap.fitPadding, const EdgeInsets.all(20));
    });

    test('refreshOverview draws the overview on a newly attached map', () {
      final h = harness();
      h.flow.previewRoutes([route, alt], selected: 1);
      final attached = FakePreviewMap();
      h.session.map = attached;
      attached.calls.clear();
      h.states.clear();
      h.flow.refreshOverview();
      expect(attached.calls, ['showRouteOptions', 'fitRoutes']);
      expect(attached.options, [same(route), same(alt)]);
      expect(attached.selected, 1);
      expect(attached.fitPadding, const EdgeInsets.all(48));
      expect(h.states, isEmpty);
    });

    test('refreshOverview outside the overview does nothing', () {
      final h = harness();
      h.flow.refreshOverview();
      expect(h.previewMap.calls, isEmpty);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.previewMap.calls.clear();
      h.flow.refreshOverview();
      expect(h.previewMap.calls, isEmpty);
    });
  });

  group('navigation', () {
    test('start runs the session along the selected route', () {
      final h = harness();
      expect(h.flow.start, throwsStateError);
      h.flow.previewRoutes([route, alt], selected: 1);
      h.flow.start();
      expect(h.session.isRunning, isTrue);
      expect(h.session.route, same(alt));
      expect(h.session.follow, isTrue);
      expect(h.previewMap.options, isNull);
      expect((h.flow.state.value as FlowNavigating).route, same(alt));
      final p = h.flow.tripProgress.value!;
      expect(p.remainingDistance, alt.length);
      expect(
        p.remainingDuration.inMilliseconds / 1000,
        closeTo(alt.duration, 0.001),
      );
      expect(p.eta, h.now.add(p.remainingDuration));
      expect(p.fraction, 0);
    });

    test('trip progress follows the vehicle at most once a second', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      final updates = <TripProgress?>[];
      h.flow.tripProgress.addListener(
        () => updates.add(h.flow.tripProgress.value),
      );
      await h.run(5, fixAt: (s) => h.fixOn(route, 600.0 + 10 * s));
      expect(updates.length, inInclusiveRange(4, 7));
      final p = h.flow.tripProgress.value!;
      final d = route.length - p.remainingDistance;
      expect(d, greaterThan(550));
      expect(
        p.remainingDuration.inMilliseconds / 1000,
        closeTo(route.remainingDuration(d), 0.001),
      );
      expect(p.fraction, closeTo(d / route.length, 1e-9));
      expect(p.eta.isAfter(h.now), isTrue);
    });

    test(
      'trip progress updates on a step change within the interval',
      () async {
        final h = harness(progressInterval: const Duration(hours: 1));
        h.flow.previewRoutes([route]);
        h.flow.start();
        final steps = <int?>[];
        h.flow.tripProgress.addListener(
          () => steps.add(h.session.guidanceState?.stepIndex),
        );
        // From 150 m to 230 m: past the turn onto Truong Dinh at 192 m.
        await h.run(8, fixAt: (s) => h.fixOn(route, 150.0 + 10 * s));
        expect(steps, hasLength(greaterThanOrEqualTo(2)));
        expect(steps.toSet(), hasLength(steps.length), reason: 'per step');
        expect(steps.last, h.session.guidanceState!.stepIndex);
      },
    );

    test('switching routes does not reuse the old route distance', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(3, fixAt: (s) => h.fixOn(route, 600.0 + 10 * s));
      expect(h.session.frame!.routeDistance, greaterThan(550));
      h.flow.backToOverview();
      h.flow.previewRoutes([alt]);
      h.flow.start();
      expect(h.session.route, same(alt));
      final p = h.flow.tripProgress.value!;
      expect(p.remainingDistance, alt.length);
      expect(p.fraction, 0);
    });

    test('speed carries the limit where the vehicle is', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(4, fixAt: (s) => h.fixOn(route, 3000.0 + 15 * s, speed: 15));
      final v = h.flow.speed.value!;
      expect(v.speed, greaterThan(10));
      expect(v.limit, closeTo(60 / 3.6, 1e-9));
    });

    test('the first frame after start publishes the speed and limit', () async {
      final h = harness();
      h.session.start(); // free driving: speed without a limit
      await h.run(
        1.5,
        fixAt: (s) => h.fixOn(route, 3000.0 + 15 * s, speed: 15),
      );
      expect(h.flow.speed.value!.limit, isNull);
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(1 / 60);
      expect(h.flow.speed.value!.limit, closeTo(60 / 3.6, 1e-9));
    });

    test('isOverLimit is more than 5 % over', () {
      expect(const SpeedInfo(speed: 10.4, limit: 10).isOverLimit, isFalse);
      expect(const SpeedInfo(speed: 10.6, limit: 10).isOverLimit, isTrue);
      expect(const SpeedInfo(speed: 50).isOverLimit, isFalse);
    });

    test('arrival ends guidance', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.arriveOn(route);
      expect((h.flow.state.value as FlowArrived).route, same(route));
      expect(h.flow.tripProgress.value, isNull);
    });

    test('a state listener may stop the flow on arrival', () async {
      final h = harness(provider: offline());
      h.flow.state.addListener(() {
        if (h.flow.state.value is FlowArrived) h.flow.stop();
      });
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.arriveOn(route);
      expect(h.flow.state.value, isA<FlowIdle>());
      await h.flow.preview(from: from, to: to);
      expect((h.flow.state.value as FlowError).previous, isA<FlowIdle>());
    });

    test('a late Arrived for a replaced route is ignored', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      // Tick without delivering events until the session has arrived, so
      // its Arrived event is still queued.
      for (var i = 0; h.session.guidanceState?.arrived != true; i++) {
        expect(i, lessThan(600));
        if (i % 60 == 0) {
          h.source.add(
            h.fixOn(route, route.length - 40 + 8.0 * (i ~/ 60), speed: 8),
          );
        }
        h.tickFrame();
        if (h.session.guidanceState?.arrived != true) {
          await pumpEventQueue(times: 1);
        }
      }
      expect(h.flow.state.value, isA<FlowNavigating>());
      h.flow.backToOverview();
      h.flow.previewRoutes([alt]);
      h.flow.start();
      await pumpEventQueue();
      expect((h.flow.state.value as FlowNavigating).route, same(alt));
    });

    test('a reroute switches the route and drives the indicator', () async {
      late NavRoute fresh;
      final gate = Completer<void>();
      final provider = FakeRouteProvider((from, to) async {
        await gate.future;
        fresh = NavRoute.fromPoints([from, to]);
        return [fresh];
      });
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      final indicator = <bool>[];
      h.flow.rerouting.addListener(() => indicator.add(h.flow.rerouting.value));
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      expect(h.flow.rerouting.value, isTrue);
      gate.complete();
      await h.run(0.1);
      expect(indicator, [true, false]);
      expect((h.flow.state.value as FlowNavigating).route, same(fresh));
    });

    test('a failed reroute clears the indicator and keeps the route', () async {
      final gate = Completer<List<NavRoute>>();
      final h = harness(provider: FakeRouteProvider((_, _) => gate.future));
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      expect(h.flow.rerouting.value, isTrue);
      gate.completeError(Exception('offline'));
      await h.run(0.1);
      expect(h.flow.rerouting.value, isFalse);
      expect((h.flow.state.value as FlowNavigating).route, same(route));
    });

    test('a late Rerouted for a replaced route is ignored', () async {
      final gate = Completer<void>();
      final provider = FakeRouteProvider((from, to) async {
        await gate.future;
        return [
          NavRoute.fromPoints([from, to]),
        ];
      });
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      expect(h.flow.rerouting.value, isTrue);
      gate.complete();
      // Let the session switch to the new route; its Rerouted event is
      // still queued when the check below first succeeds.
      while (identical(h.session.route, route)) {
        await Future<void>.value();
      }
      h.flow.backToOverview();
      h.flow.previewRoutes([alt]);
      h.flow.start();
      await pumpEventQueue();
      expect(h.session.route, same(alt));
      expect((h.flow.state.value as FlowNavigating).route, same(alt));
    });

    test('backToOverview keeps the session running unfollowed', () {
      final h = harness();
      h.flow.previewRoutes([route]);
      expect(h.flow.backToOverview, throwsStateError);
      h.flow.start();
      h.flow.backToOverview();
      final s = h.flow.state.value as FlowOverview;
      expect(s.routes, [same(route)]);
      expect(h.session.isRunning, isTrue);
      expect(h.session.follow, isFalse);
      expect(h.flow.tripProgress.value, isNull);
      h.flow.start();
      expect(h.flow.state.value, isA<FlowNavigating>());
      expect(h.session.follow, isTrue);
    });

    test('backToOverview after arriving shows the trip', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.arriveOn(route);
      h.flow.backToOverview();
      expect((h.flow.state.value as FlowOverview).routes, [same(route)]);
      expect(h.previewMap.options, [same(route)]);
      expect(h.session.isRunning, isTrue);
      expect(h.session.follow, isFalse);
    });

    test('stop ends the trip from any state', () {
      final h = harness();
      h.flow.stop();
      expect(h.flow.state.value, isA<FlowIdle>());
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.previewMap.calls.clear();
      h.flow.stop();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(h.session.isRunning, isFalse);
      expect(h.session.route, isNull);
      expect(h.previewMap.calls, contains('clearRoute'));
      expect(h.flow.tripProgress.value, isNull);
      expect(h.flow.speed.value, isNull);
    });

    test('isTripOverview is true only for the running trip overview', () {
      final h = harness();
      expect(h.flow.isTripOverview, isFalse);
      h.flow.previewRoutes([route]);
      expect(h.flow.isTripOverview, isFalse);
      h.flow.start();
      expect(h.flow.isTripOverview, isFalse);
      h.flow.backToOverview();
      expect(h.flow.isTripOverview, isTrue);
      h.flow.start();
      expect(h.flow.isTripOverview, isFalse);
      h.flow.backToOverview();
      h.flow.stop();
      expect(h.flow.isTripOverview, isFalse);
    });

    test('resuming keeps a pending reroute visible', () async {
      final gate = Completer<void>();
      final provider = FakeRouteProvider((from, to) async {
        await gate.future;
        return [
          NavRoute.fromPoints([from, to]),
        ];
      });
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.flow.backToOverview();
      NavFix off(int s) {
        final on = route.pointAt(800.0 + s * 5);
        return NavFix(
          position: s == 0
              ? on
              : offsetPoint(on, route.bearingAt(800) + 90, 60),
          accuracy: 5,
          speed: 5,
          time: h.now,
        );
      }

      await h.run(6, fixAt: off);
      expect(h.flow.rerouting.value, isTrue);
      h.flow.start(); // resume: same route instance still running
      expect(h.flow.rerouting.value, isTrue);
      gate.complete();
      await h.run(0.1);
      expect(h.flow.rerouting.value, isFalse);
    });
  });

  group('resuming the trip overview', () {
    test('keeps the session route and guidance progress', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(3, fixAt: (s) => h.fixOn(route, 600.0 + 10 * s));
      final guidance = h.session.guidanceState;
      expect(guidance, isNotNull);
      h.flow.backToOverview();
      h.previewMap.calls.clear();
      h.flow.start();
      expect((h.flow.state.value as FlowNavigating).route, same(route));
      expect(h.session.route, same(route));
      expect(h.session.guidanceState, same(guidance), reason: 'not reset');
      expect(h.previewMap.calls, isNot(contains('showRoute')));
      expect(h.session.follow, isTrue);
      final p = h.flow.tripProgress.value!;
      expect(route.length - p.remainingDistance, greaterThan(550));
    });

    test('a reroute during it re-shows it with the new route', () async {
      late NavRoute fresh;
      final provider = FakeRouteProvider((from, to) async {
        fresh = NavRoute.fromPoints([from, to]);
        return [fresh];
      });
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.flow.backToOverview();
      h.previewMap.calls.clear();
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      expect(h.session.route, same(fresh), reason: 'rerouted');
      expect((h.flow.state.value as FlowOverview).routes, [same(fresh)]);
      expect(h.previewMap.options, [same(fresh)]);
      expect(
        h.previewMap.calls,
        containsAll(['showRouteOptions', 'fitRoutes']),
      );
      expect(h.flow.rerouting.value, isFalse);
    });

    test('after a reroute during it keeps the new route', () async {
      late NavRoute fresh;
      final provider = FakeRouteProvider((from, to) async {
        fresh = NavRoute.fromPoints([from, to]);
        return [fresh];
      });
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.flow.backToOverview();
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      final events = <SessionEvent>[];
      final sub = h.session.events.listen(events.add);
      addTearDown(sub.cancel);
      h.flow.start();
      expect(h.session.route, same(fresh), reason: 'not reverted');
      expect((h.flow.state.value as FlowNavigating).route, same(fresh));
      await h.run(1);
      expect(events.whereType<Rerouting>(), isEmpty);
    });

    test('after a reroute while re-planning keeps the new route', () async {
      late NavRoute fresh;
      final provider = both();
      final h = harness(provider: provider);
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.flow.backToOverview();
      final planning = Completer<List<NavRoute>>();
      provider.handler = (_, _) => planning.future;
      final request = h.flow.preview(from: from, to: to);
      provider.handler = (from, to) async {
        fresh = NavRoute.fromPoints([from, to]);
        return [fresh];
      };
      await h.run(6, fixAt: (s) => h.offRoute(route, s));
      expect(h.session.route, same(fresh), reason: 'rerouted');
      expect(h.flow.state.value, isA<FlowLoading>());
      h.flow.cancel();
      expect((h.flow.state.value as FlowOverview).routes, [same(fresh)]);
      h.flow.start();
      expect(h.session.route, same(fresh));
      planning.complete([alt]);
      await request;
      expect(h.flow.state.value, isA<FlowNavigating>());
    });

    test('after arriving during it goes to the arrival', () async {
      final h = harness();
      h.flow.previewRoutes([route]);
      h.flow.start();
      h.flow.backToOverview();
      await h.arriveOn(route);
      expect(h.session.guidanceState!.arrived, isTrue);
      expect(h.flow.state.value, isA<FlowOverview>(), reason: 'stays');
      h.flow.start();
      expect((h.flow.state.value as FlowArrived).route, same(route));
      expect(h.flow.tripProgress.value, isNull);
      expect(h.session.follow, isTrue);
    });
  });

  group('night mode', () {
    test('auto follows the sun at the vehicle, else the route', () async {
      final h = harness();
      expect(h.flow.isNight.value, isFalse, reason: 'nowhere yet');
      h.flow.previewRoutes([route]); // 20:00 in Ho Chi Minh City
      expect(h.flow.isNight.value, isTrue);
      h.now = DateTime.utc(2026, 10, 8, 3); // 10:00
      h.flow.nightMode = NightMode.auto;
      expect(h.flow.isNight.value, isFalse);
    });

    test('alwaysDay and alwaysNight override the sun', () {
      final h = harness(nightMode: NightMode.alwaysNight);
      expect(h.flow.isNight.value, isTrue);
      h.flow.previewRoutes([route]);
      h.flow.nightMode = NightMode.alwaysDay;
      expect(h.flow.isNight.value, isFalse);
    });

    testWidgets('auto is re-evaluated every minute', (tester) async {
      final h = Harness();
      h.flow.previewRoutes([route]);
      expect(h.flow.isNight.value, isTrue);
      h.now = DateTime.utc(2026, 10, 8, 3);
      await tester.pump(const Duration(seconds: 61));
      expect(h.flow.isNight.value, isFalse);
      h.dispose(); // before the pending-timer check, which precedes tearDown
    });
  });

  test('dispose leaves the session alone and drops late results', () async {
    final pending = Completer<List<NavRoute>>();
    final h = Harness(provider: FakeRouteProvider((_, _) => pending.future));
    addTearDown(h.session.dispose);
    final request = h.flow.preview(from: from, to: to);
    h.flow.dispose();
    pending.complete([route]);
    await request;
    expect(() => h.flow.start(), throwsStateError);
    h.flow.dispose();
    h.session.start(route: route);
    expect(h.session.isRunning, isTrue);
  });
}
