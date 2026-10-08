import 'dart:async';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

class FakeFixSource implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  var starts = 0, stops = 0;
  var disposed = false;
  var _running = false;

  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() {
    starts++;
    _running = true;
  }

  @override
  void stop() {
    stops++;
    _running = false;
  }

  @override
  void dispose() => disposed = true;

  void add(NavFix fix) => _controller.add(fix);
  void addError(Object e) => _controller.addError(e);
}

class FakeMap implements NavigationMap {
  final moves = <CameraTarget>[];
  final routes = <(List<GeoPoint>, List<GeoPoint>)>[];
  var clears = 0;

  /// When set, moveCamera returns this future instead of completing at once.
  Future<void> Function()? onMove;

  @override
  Future<void> moveCamera(CameraTarget target) {
    moves.add(target);
    return onMove?.call() ?? Future.value();
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) =>
      routes.add((driven, ahead));

  @override
  void clearRoute() => clears++;
}

class FakeRouteProvider extends RouteProvider {
  FakeRouteProvider(this.handler);
  final Future<NavRoute> Function(GeoPoint from, GeoPoint to) handler;
  var calls = 0;
  double? lastHeading;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) {
    calls++;
    lastHeading = heading;
    return handler(from, to);
  }
}

/// A session on a fake clock, fed by [source], with helpers to drive it.
class Harness {
  Harness({NavigationMap? map, RouteProvider? provider})
    : source = FakeFixSource() {
    session = NavigationSession(
      fixes: source,
      map: map,
      routeProvider: provider,
      clock: () => now,
    );
    session.events.listen(events.add);
    session.guidance.listen(guidance.add);
    session.announcements.listen(announcements.add);
  }

  final FakeFixSource source;
  late final NavigationSession session;
  DateTime now = DateTime.utc(2026);
  final events = <SessionEvent>[];
  final guidance = <GuidanceState?>[];
  final announcements = <GuidanceAnnouncement>[];

  NavFix fixOn(NavRoute route, double s, {double speed = 10}) => NavFix(
    position: route.pointAt(s),
    accuracy: 5,
    speed: speed,
    heading: route.bearingAt(s),
    time: now,
  );

  /// Runs [seconds] at 60 fps; [fixAt] (called once per simulated second,
  /// with the elapsed seconds) may return a fix to deliver. The event queue
  /// is pumped after every frame, as Flutter drains microtasks between
  /// frames: camera completions and reroute results land in time.
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
      now = now.add(const Duration(microseconds: 16667));
      session.tick(1 / 60);
      await pumpEventQueue(times: 1);
    }
    await pumpEventQueue(times: 2);
  }
}

void main() {
  final route = sampleRoute;

  test('start subscribes and starts the source; stop stops it', () {
    final h = Harness();
    expect(h.session.isRunning, isFalse);
    h.session.start(route: route);
    expect(h.session.isRunning, isTrue);
    expect(h.source.starts, 1);
    h.session.start(route: route); // already running: no-op
    expect(h.source.starts, 1);
    h.session.stop();
    expect(h.session.isRunning, isFalse);
    expect(h.source.stops, 1);
    h.session.stop(); // not running: no-op
    expect(h.source.stops, 1);
  });

  test('tick before any fix does nothing', () {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    h.session.tick(1 / 60);
    expect(h.session.frame, isNull);
    expect(map.moves, isEmpty);
  });

  test('frames follow the fixes and move the camera', () async {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    await h.run(3, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    expect(h.session.frame, isNotNull);
    // Last fix at 120 m (t = 2 s), then ~1 s more at 10 m/s.
    expect(h.session.frame!.routeDistance, inInclusiveRange(115, 140));
    expect(map.moves.length, greaterThan(100));
    expect(map.moves.last.tilt, 50);
    expect(h.session.stats.fixesAccepted, 3);
    expect(h.session.lastFix, isNotNull);
  });

  test('only one camera update in flight', () async {
    final map = FakeMap();
    final pending = Completer<void>();
    map.onMove = () => pending.future;
    final h = Harness(map: map)..session.start(route: route);
    h.source.add(h.fixOn(route, 100));
    for (var i = 0; i < 10; i++) {
      h.session.tick(1 / 60);
    }
    expect(map.moves, hasLength(1));
    expect(h.session.stats.cameraFramesSkipped, 9);
    map.onMove = null;
    pending.complete();
    await pumpEventQueue();
    h.session.tick(1 / 60);
    expect(map.moves, hasLength(2));
    expect(h.session.stats.cameraMoves, 2);
  });

  test('a failing camera update releases the in-flight flag', () async {
    final map = FakeMap()..onMove = () => Future.error(StateError('boom'));
    final h = Harness(map: map)..session.start(route: route);
    h.source.add(h.fixOn(route, 100));
    h.session.tick(1 / 60);
    await pumpEventQueue();
    h.session.tick(1 / 60);
    expect(map.moves, hasLength(2));
  });

  test('follow = false leaves the camera alone', () async {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    h.session.follow = false;
    await h.run(2, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    expect(map.moves, isEmpty);
    expect(h.session.frame, isNotNull);
  });

  test('followChanges emits each change of follow, not a repeat', () async {
    final h = Harness();
    final seen = <bool>[];
    final sub = h.session.followChanges.listen(seen.add);
    h.session.follow = false;
    h.session.follow = false;
    h.session.follow = true;
    await pumpEventQueue();
    expect(seen, [false, true]);
    await sub.cancel();
    h.session.dispose();
    h.session.follow = false; // after dispose: no throw
    expect(h.session.follow, isFalse);
  });

  test('dispose ends the camera it created, not one it was given', () async {
    final own = Harness();
    var ownDone = false;
    own.session.camera.headingUpChanges.listen(
      null,
      onDone: () => ownDone = true,
    );
    final given = FollowCamera();
    final other = NavigationSession(fixes: FakeFixSource(), camera: given);
    var givenDone = false;
    given.headingUpChanges.listen(null, onDone: () => givenDone = true);
    own.session.dispose();
    other.dispose();
    await pumpEventQueue();
    expect(ownDone, isTrue);
    expect(givenDone, isFalse, reason: 'the caller owns it');
    given.dispose();
  });

  test('the route line is redrawn at most once per second', () async {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    await h.run(3.5, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    // Drawn on the first frame, then at ~1 s, ~2 s, ~3 s.
    expect(map.routes.length, inInclusiveRange(3, 4));
    final (driven, ahead) = map.routes.last;
    expect(driven.last, ahead.first);
  });

  test('a huge dt (app resumed) is clamped', () {
    final h = Harness()..session.start(route: route);
    h.source.add(h.fixOn(route, 1000, speed: 20));
    h.session.tick(1 / 60);
    final before = h.session.frame!.routeDistance!;
    h.now = h.now.add(const Duration(seconds: 5));
    h.session.tick(5);
    final after = h.session.frame!.routeDistance!;
    // At most 0.1 s of driving (20 m/s + 5 m/s correction), not 100 m.
    expect(after - before, lessThan(3));
  });

  test('guidance emits on change, not every frame', () async {
    final h = Harness()..session.start(route: route);
    await h.run(30, fixAt: (s) => h.fixOn(route, 10.0 * s));
    expect(h.guidance, isNotEmpty);
    expect(h.guidance.length, lessThan(30 * 60 ~/ 10));
    for (var i = 1; i < h.guidance.length; i++) {
      final a = h.guidance[i - 1]!, b = h.guidance[i]!;
      final changed =
          a.stepIndex != b.stepIndex ||
          a.arrived != b.arrived ||
          !identical(a.thenStep, b.thenStep) ||
          (a.distanceToStep - b.distanceToStep).abs() >= 5;
      expect(changed, isTrue, reason: 'emission $i');
    }
    expect(h.session.guidanceState, isNotNull);
  });

  test('announcements are forwarded in order', () async {
    final h = Harness()..session.start(route: route);
    // 400 m from the start: past the first spoken manoeuvre (steps[2]).
    await h.run(40, fixAt: (s) => h.fixOn(route, 10.0 * s));
    expect(route.steps[2].distance, lessThan(350));
    expect(h.announcements, isNotEmpty);
    final indices = h.announcements.map((a) => a.stepIndex).toList();
    expect(indices, orderedEquals([...indices]..sort()));
  });

  test('arrival emits Arrived once', () async {
    final h = Harness()..session.start(route: route);
    await h.run(
      8,
      fixAt: (s) => h.fixOn(route, route.length - 40 + 8.0 * s, speed: 8),
    );
    expect(h.events.whereType<Arrived>(), hasLength(1));
    expect(h.announcements.last.kind, AnnouncementKind.arrived);
  });

  group('off route', () {
    NavFix offFix(Harness h, int s) {
      final on = route.pointAt(800.0 + s * 5);
      return NavFix(
        position: s == 0 ? on : offsetPoint(on, route.bearingAt(800) + 90, 60),
        accuracy: 5,
        speed: 5,
        time: h.now,
      );
    }

    test(
      'failed reroutes are throttled and keep the session running',
      () async {
        final provider = FakeRouteProvider(
          (_, _) => Future.error(StateError('no route')),
        );
        final h = Harness(provider: provider)..session.start(route: route);
        await h.run(20, fixAt: (s) => offFix(h, s));
        expect(h.events.whereType<OffRoute>(), hasLength(1));
        expect(h.events.whereType<RerouteFailed>().length, provider.calls);
        // Off route from ~4 s; attempts at ~4 s and ~14 s.
        expect(provider.calls, 2);
        expect(h.session.isRunning, isTrue);
        expect(h.session.route, same(route));
      },
    );

    test(
      'a successful reroute swaps the route and replays the last fix',
      () async {
        late NavRoute fresh;
        final provider = FakeRouteProvider((from, to) async {
          fresh = NavRoute.fromPoints([from, to]);
          return fresh;
        });
        final h = Harness(provider: provider)..session.start(route: route);
        await h.run(6, fixAt: (s) => offFix(h, s));
        expect(h.events.whereType<Rerouting>(), hasLength(1));
        expect(h.events.whereType<Rerouted>().single.route, same(fresh));
        expect(h.session.route, same(fresh));
        expect(provider.lastHeading, isNotNull);
        h.session.tick(1 / 60);
        expect(h.session.frame!.offRoute, isFalse);
        // Near the start of the new route (rerouted at ~4 s, ~2 s at 5 m/s),
        // not ~830 m along the old one.
        expect(h.session.frame!.routeDistance, lessThan(30));
      },
    );

    test('a reroute that lands after setRoute is ignored', () async {
      final pending = Completer<NavRoute>();
      final provider = FakeRouteProvider((_, _) => pending.future);
      final h = Harness(provider: provider)..session.start(route: route);
      await h.run(6, fixAt: (s) => offFix(h, s));
      expect(provider.calls, 1);
      final other = NavRoute.fromPoints([route.points.first, route.points[5]]);
      h.session.setRoute(other);
      pending.complete(NavRoute.fromPoints([route.points[3], route.points[9]]));
      await pumpEventQueue();
      expect(h.session.route, same(other));
      expect(h.events.whereType<Rerouted>(), isEmpty);
    });

    test('a hung provider does not disable rerouting after setRoute', () async {
      final provider = FakeRouteProvider(
        (_, _) => Completer<NavRoute>().future,
      );
      final h = Harness(provider: provider)..session.start(route: route);
      await h.run(6, fixAt: (s) => offFix(h, s));
      expect(provider.calls, 1);
      h.session.setRoute(route);
      await h.run(14, fixAt: (s) => offFix(h, s + 1));
      expect(provider.calls, 2);
    });

    test('no reroute is requested while stopped', () async {
      final provider = FakeRouteProvider(
        (_, _) => Future.error(StateError('no route')),
      );
      final h = Harness(provider: provider)..session.start(route: route);
      await h.run(6, fixAt: (s) => offFix(h, s));
      expect(provider.calls, 1);
      expect(h.session.frame!.offRoute, isTrue);
      h.session.stop();
      h.now = h.now.add(const Duration(seconds: 30));
      for (var i = 0; i < 5; i++) {
        h.session.tick(1 / 60);
        await pumpEventQueue();
      }
      expect(provider.calls, 1);
      expect(h.events.whereType<Rerouting>(), hasLength(1));
    });

    test('no reroute while paused', () async {
      final provider = FakeRouteProvider(
        (_, _) => Future.error(StateError('no route')),
      );
      final h = Harness(provider: provider)..session.start(route: route);
      await h.run(6, fixAt: (s) => offFix(h, s));
      expect(provider.calls, 1);
      h.session.pause();
      await h.run(25);
      expect(provider.calls, 1);
    });

    test('a stale reroute failure emits nothing', () async {
      final pending = Completer<NavRoute>();
      final provider = FakeRouteProvider((_, _) => pending.future);
      final h = Harness(provider: provider)..session.start(route: route);
      await h.run(6, fixAt: (s) => offFix(h, s));
      expect(provider.calls, 1);
      h.session.setRoute(
        NavRoute.fromPoints([route.points.first, route.points[5]]),
      );
      pending.completeError(StateError('late failure'));
      await pumpEventQueue();
      expect(h.events.whereType<RerouteFailed>(), isEmpty);
    });
  });

  group('attaching a map later', () {
    test(
      'the new map gets the route at once and the camera from then on',
      () async {
        final h = Harness()..session.start(route: route);
        await h.run(2, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
        final map = FakeMap();
        h.session.map = map;
        expect(h.session.map, same(map));
        expect(map.routes, hasLength(1));
        expect(map.routes.single.$1.length, greaterThan(1));
        await h.run(1);
        expect(map.moves, isNotEmpty);
        h.session.map = null;
        final moves = map.moves.length;
        await h.run(1);
        expect(map.moves.length, moves);
      },
    );

    test('a session without a route clears the new map instead', () {
      final h = Harness()..session.start();
      final map = FakeMap();
      h.session.map = map;
      expect(map.clears, 1);
      expect(map.routes, isEmpty);
    });

    test('a camera update stuck on the old map does not block the new one', () {
      final old = FakeMap()..onMove = () => Completer<void>().future;
      final h = Harness(map: old)..session.start(route: route);
      h.source.add(h.fixOn(route, 100));
      h.session.tick(1 / 60);
      expect(old.moves, hasLength(1));
      final map = FakeMap();
      h.session.map = map;
      h.session.tick(1 / 60);
      expect(map.moves, hasLength(1));
    });
  });

  test('resetMotion hides the guidance until the next frame', () async {
    final h = Harness()..session.start(route: route);
    await h.run(1, fixAt: (s) => h.fixOn(route, 500));
    expect(h.guidance.last, isNotNull);
    h.session.resetMotion();
    await pumpEventQueue();
    expect(h.guidance.last, isNull);
    final nulls = h.guidance.where((g) => g == null).length;
    h.session.resetMotion();
    await pumpEventQueue();
    expect(
      h.guidance.where((g) => g == null).length,
      nulls,
      reason: 'no duplicate null',
    );
    await h.run(1, fixAt: (s) => h.fixOn(route, 600));
    expect(h.guidance.last, isNotNull);
  });

  test(
    'removing the route right after replacing it still emits null',
    () async {
      final h = Harness()..session.start(route: route);
      await h.run(1, fixAt: (s) => h.fixOn(route, 500));
      final other = NavRoute.fromPoints([
        route.pointAt(500),
        route.points.last,
      ]);
      h.session.setRoute(other);
      h.session.setRoute(null);
      await pumpEventQueue();
      expect(h.guidance.last, isNull);
    },
  );

  test('fix source errors become events; the session keeps running', () async {
    final h = Harness()..session.start(route: route);
    h.source.addError(StateError('gps off'));
    await pumpEventQueue();
    expect(h.events.whereType<FixSourceError>(), hasLength(1));
    expect(h.session.isRunning, isTrue);
  });

  test('rejected fixes are counted', () {
    final h = Harness()..session.start(route: route);
    h.source.add(
      NavFix(position: route.pointAt(10), accuracy: 100, time: h.now),
    );
    expect(h.session.stats.fixesRejected, 1);
    expect(h.session.stats.fixesAccepted, 0);
  });

  test('no route: free driving, the route line is cleared', () async {
    final map = FakeMap();
    final h = Harness(map: map)..session.start();
    await h.run(2, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    expect(map.clears, 1);
    expect(h.session.frame, isNotNull);
    expect(h.session.frame!.routeDistance, isNull);
    expect(h.session.guidanceState, isNull);
  });

  test('resetMotion forgets the vehicle until the next fix', () async {
    final h = Harness()..session.start(route: route);
    await h.run(2, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    h.session.resetMotion();
    expect(h.session.frame, isNull);
    h.session.tick(1 / 60);
    expect(h.session.frame, isNull);
    h.source.add(h.fixOn(route, 2000));
    h.session.tick(1 / 60);
    expect(h.session.frame!.routeDistance, closeTo(2000, 10));
  });

  test(
    'dispose closes streams, is idempotent, and leaves the source alone',
    () async {
      final map = FakeMap();
      final h = Harness(map: map)..session.start(route: route);
      h.source.add(h.fixOn(route, 100));
      h.session.tick(1 / 60);
      final frame = h.session.frame;
      expect(frame, isNotNull);
      final done = Future.wait<Object>([
        h.session.frames.toList(),
        h.session.guidance.toList(),
        h.session.announcements.toList(),
        h.session.events.toList(),
      ]);
      h.session.dispose();
      h.session.dispose();
      await done;
      expect(h.source.disposed, isFalse);
      expect(h.source.stops, 1);
      final moves = map.moves.length;
      h.session.tick(1 / 60); // no-op, no exception
      expect(map.moves, hasLength(moves));
      expect(h.session.frame, same(frame));
      expect(() => h.session.start(route: route), throwsStateError);
    },
  );

  test('tick ignores negative and NaN steps', () {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    h.source.add(h.fixOn(route, 100));
    h.session.tick(1 / 60);
    final frame = h.session.frame;
    final moves = map.moves.length;
    h.session.tick(-1);
    h.session.tick(double.nan);
    expect(h.session.frame, same(frame));
    expect(map.moves, hasLength(moves));
  });

  group('pause / resume', () {
    test(
      'pause stops the source but keeps the run; resume restarts it',
      () async {
        final map = FakeMap();
        final h = Harness(map: map)..session.start(route: route);
        await h.run(3, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
        final frame = h.session.frame;
        expect(frame, isNotNull);
        expect(h.session.isPaused, isFalse);

        h.session.pause();
        expect(h.session.isPaused, isTrue);
        expect(h.session.isRunning, isTrue);
        expect(h.source.stops, 1);
        expect(h.source.starts, 1);
        expect(h.session.route, same(route));
        expect(h.session.frame, same(frame));
        expect(h.session.guidanceState, isNotNull);

        // Ticking while paused is fine: without fixes the vehicle stops.
        await h.run(8);
        expect(h.session.frame!.speed, lessThan(0.5));
        expect(h.session.route, same(route));

        h.session.resume();
        expect(h.session.isPaused, isFalse);
        expect(h.source.starts, 2);
        expect(h.source.stops, 1);
        // The run continues where it was: same subscription, same route.
        final before = h.session.frame!.routeDistance!;
        await h.run(2, fixAt: (s) => h.fixOn(route, before + 10 * s));
        expect(h.session.frame!.routeDistance, greaterThan(before));
        expect(h.session.stats.fixesAccepted, 5);
      },
    );

    test('pause and resume are no-ops when not running or twice', () {
      final h = Harness();
      h.session.pause();
      h.session.resume();
      expect(h.session.isPaused, isFalse);
      expect((h.source.starts, h.source.stops), (0, 0));

      h.session.start(route: route);
      h.session.resume(); // not paused
      expect((h.source.starts, h.source.stops), (1, 0));
      h.session.pause();
      h.session.pause();
      expect((h.source.starts, h.source.stops), (1, 1));
      h.session.resume();
      h.session.resume();
      expect((h.source.starts, h.source.stops), (2, 1));

      h.session.pause();
      h.session.stop(); // stopping a paused run
      expect(h.session.isPaused, isFalse);
      expect(h.session.isRunning, isFalse);
      h.session.resume(); // stopped: no-op
      expect(h.source.starts, 2);
      h.session.start(route: route);
      expect(h.session.isPaused, isFalse);
      expect(h.source.starts, 3);
    });
  });

  test('guidance emits null when it ends', () async {
    final h = Harness()..session.start(route: route);
    await h.run(3, fixAt: (s) => h.fixOn(route, 100.0 + 10 * s));
    expect(h.guidance, isNotEmpty);
    expect(h.guidance.last, isNotNull);
    h.session.setRoute(null);
    await pumpEventQueue();
    expect(h.guidance.last, isNull);
    expect(h.session.guidanceState, isNull);

    // Starting again without a route after a route ends guidance too.
    h.session.setRoute(route);
    await h.run(2, fixAt: (s) => h.fixOn(route, 200.0 + 10 * s));
    expect(h.guidance.last, isNotNull);
    h.session.stop();
    h.session.start();
    await pumpEventQueue();
    expect(h.guidance.last, isNull);
  });

  test('setRoute shows the route line before the first fix', () async {
    final map = FakeMap();
    final h = Harness(map: map)..session.start(route: route);
    expect(map.routes, hasLength(1));
    final (driven, ahead) = map.routes.single;
    expect(driven.first, route.points.first);
    expect(ahead.first, route.points.first);
    expect(ahead.last, route.points.last);

    final other = NavRoute.fromPoints([route.points.first, route.points[5]]);
    h.session.setRoute(other);
    expect(map.routes, hasLength(2));
    expect(map.routes.last.$2.last, other.points.last);
  });

  test('setRoute and resetMotion throw after dispose; pause/resume do not', () {
    final h = Harness()..session.start(route: route);
    h.session.dispose();
    expect(() => h.session.setRoute(route), throwsStateError);
    expect(() => h.session.setRoute(null), throwsStateError);
    expect(() => h.session.resetMotion(), throwsStateError);
    h.session.pause();
    h.session.resume();
    expect(h.session.isPaused, isFalse);
    expect((h.source.starts, h.source.stops), (1, 1));
  });
}
