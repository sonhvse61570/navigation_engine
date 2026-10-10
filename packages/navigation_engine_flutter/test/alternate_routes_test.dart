import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_flutter/src/flow/alternate_route.dart'
    show routeDivergence;

import 'support/flow_harness.dart';

void main() {
  group('routeDivergence', () {
    test('finds where the alternate leaves the route by more than 30 m', () {
      final d = routeDivergence(northRoute(), branchRoute(1500))!;
      // 50 m along the north-east leg is 35 m off; 40 m along is 28 m off,
      // which projects 28 m past the fork.
      expect(d.alternate, closeTo(1550, 3));
      expect(d.current, closeTo(1528, 3));
    });

    test('an alternate that never leaves the route has none', () {
      final north = northRoute();
      expect(routeDivergence(north, NavRoute.fromPoints(north.points)), isNull);
      expect(
        routeDivergence(
          north,
          NavRoute.fromPoints(straight(testOrigin, 0, 1200)),
        ),
        isNull,
        reason: 'a prefix of the route',
      );
    });

    test('an alternate that starts part way along the route is measured '
        'from there', () {
      // A refetched alternate starts where the vehicle is, 1000 m along.
      final from1000 = NavRoute.fromPoints(
        branchRoute(1500).points.skip(20).toList(),
      );
      final d = routeDivergence(northRoute(), from1000)!;
      expect(d.alternate, closeTo(550, 3));
      expect(d.current, closeTo(1528, 3));
    });

    test('an alternate that skips a spur of the route never leaves it', () {
      // The route goes 1 km north, 500 m east and back, then 1 km north;
      // the alternate drives straight on, past the spur's base.
      final base = offsetPoint(testOrigin, 0, 1000);
      final spurEnd = offsetPoint(base, 90, 500);
      final withSpur = NavRoute.fromPoints([
        ...straight(testOrigin, 0, 1000),
        ...straight(base, 90, 500).skip(1),
        ...straight(spurEnd, 270, 500).skip(1),
        ...straight(base, 0, 1000).skip(1),
      ]);
      final straightOn = NavRoute.fromPoints(straight(testOrigin, 0, 2000));
      expect(routeDivergence(withSpur, straightOn), isNull);
    });

    test('current follows the windowed match on a U-turn, and a border '
        'sample never jumps back to the other carriageway', () {
      // 1 km north, 15 m east, 1 km south: two carriageways 15 m apart.
      final top = offsetPoint(testOrigin, 0, 1000);
      final topEast = offsetPoint(top, 90, 15);
      final uTurn = NavRoute.fromPoints([
        ...straight(testOrigin, 0, 1000),
        ...straight(topEast, 180, 1000),
      ]);
      // The alternate starts on the return carriageway 505 m from the
      // origin (1510 m along), runs 300 m south drawn on the outbound line
      // (15 m off its own carriageway, 0 m off the other), then turns west.
      final start = offsetPoint(topEast, 180, 495);
      final corner = offsetPoint(testOrigin, 0, 200);
      final alternate = NavRoute.fromPoints([
        start,
        ...straight(offsetPoint(testOrigin, 0, 500), 180, 300),
        ...straight(corner, 270, 500).skip(1),
      ]);
      final d = routeDivergence(uTurn, alternate)!;
      // Still on the return carriageway: 1000 + 15 + 800 m along.
      expect(d.current, closeTo(1815, 5));
      // About 20 m west of the corner the alternate is more than 30 m off
      // the return carriageway, though still within 30 m of the outbound
      // one: it has left the route there.
      final turn = alternate.snap(corner).distance;
      expect(d.alternate, closeTo(turn + 20, 5));
    });

    test('a match ahead of the window is taken even on a later pass (the '
        'known limit of the forward rejoin)', () {
      // 1 km north, then back south on a carriageway 15 m to the east.
      final top = offsetPoint(testOrigin, 0, 1000);
      final outAndBack = NavRoute.fromPoints([
        ...straight(testOrigin, 0, 1000),
        ...straight(offsetPoint(top, 90, 15), 180, 1000),
      ]);
      // The alternate follows the outbound leg for 500 m, then turns east
      // across the return carriageway.
      final turn = offsetPoint(testOrigin, 0, 500);
      final crossing = NavRoute.fromPoints([
        ...straight(testOrigin, 0, 500),
        ...straight(turn, 90, 300).skip(1),
      ]);
      final d = routeDivergence(outAndBack, crossing)!;
      // Crossing the return carriageway (15 m east of the outbound one)
      // reads as a rejoin there, 1000 + 15 + 500 m along; it leaves at
      // 50 m east of the turn.
      expect(d.current, closeTo(1515, 5));
      expect(d.alternate, closeTo(550, 5));
      // Bounding the forward jump would break a skipped spur, which needs
      // the same rejoin (see the spur test above).
    });

    test('a copy of a 100 km route is measured in under 50 ms', () {
      // 100 legs of 1 km, alternately 20° east and west of north: 2001
      // points every 50 m.
      final points = <GeoPoint>[testOrigin];
      for (var leg = 0; leg < 100; leg++) {
        points.addAll(
          straight(points.last, leg.isEven ? 20 : 340, 1000).skip(1),
        );
      }
      final long = NavRoute.fromPoints(points);
      expect(long.length, closeTo(100000, 50));
      final copy = NavRoute.fromPoints(points);
      // Warmed up first, then the median of 3 runs: the guard measures the
      // algorithm, not the first call's compilation or a busy machine.
      expect(routeDivergence(long, copy), isNull);
      final times = <int>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final d = routeDivergence(long, copy);
        watch.stop();
        expect(d, isNull);
        times.add(watch.elapsedMilliseconds);
      }
      times.sort();
      expect(times[1], lessThan(50), reason: 'took $times ms');
    });
  });

  group('alternateLabelDistance', () {
    AlternateRoute alt({required double divergence, double? rejoin}) =>
        AlternateRoute(
          route: detourRoute(),
          timeDelta: Duration.zero,
          divergence: divergence,
          rejoin: rejoin == null ? null : (alternate: rejoin, current: 0),
        );

    test('without a rejoin: 400 m past the divergence, or the middle of '
        'the rest when nearer', () {
      expect(alternateLabelDistance(alt(divergence: 1000)), 1400);
      final rest = (3000 + detourRoute().length) / 2;
      expect(alternateLabelDistance(alt(divergence: 3000)), rest);
    });

    test('with a rejoin: the middle of the part that differs when nearer '
        'than 400 m, so the bubble is on the drawn line', () {
      expect(alternateLabelDistance(alt(divergence: 1040, rejoin: 1240)), 1140);
      expect(alternateLabelDistance(alt(divergence: 1040, rejoin: 2560)), 1440);
    });

    test('takes another lead', () {
      expect(alternateLabelDistance(alt(divergence: 1000), lead: 100), 1100);
    });
  });

  group('alternateLinePoints', () {
    test('runs from 40 m before the divergence to the end without a '
        'rejoin', () {
      final branch = branchRoute(1500);
      final a = AlternateRoute(
        route: branch,
        timeDelta: Duration.zero,
        divergence: 1550,
      );
      expect(a.rejoin, isNull);
      final points = alternateLinePoints(a);
      expect(points, branch.pointsBetween(1510, branch.length));
      expect(points.last, branch.points.last);
      expect(
        distanceBetween(points.first, branch.pointAt(1510)),
        lessThan(0.01),
      );
    });

    test('stops 40 m after the rejoin', () {
      final detour = detourRoute();
      final a = AlternateRoute(
        route: detour,
        timeDelta: Duration.zero,
        divergence: 1040,
        rejoin: (alternate: 2560, current: 2000),
      );
      expect(alternateLinePoints(a), detour.pointsBetween(1000, 2600));
    });

    test('is clamped to the route at both ends', () {
      final detour = detourRoute();
      final a = AlternateRoute(
        route: detour,
        timeDelta: Duration.zero,
        divergence: 10,
        rejoin: (alternate: detour.length - 5, current: 2995),
      );
      expect(alternateLinePoints(a), detour.points);
    });
  });

  flowTest('a detour that comes back to the route is measured to its '
      'rejoin', (tester, h) async {
    final north = northRoute();
    final detour = detourRoute();
    h.flow.previewRoutes([north, detour]);
    h.flow.start();
    final alt = h.flow.alternates.value.single;
    expect(alt.route, same(detour));
    expect(alt.divergence, closeTo(1040, 3));
    // Measured as the divergence of the two routes reversed: the first
    // sample more than 30 m into the 300 m leg back, counted from the end
    // (the 30 m sample sits on the threshold).
    expect(
      alt.rejoin!.alternate,
      inInclusiveRange(detour.length - 1041, detour.length - 1029),
    );
    expect(alt.rejoin!.current, closeTo(2000, 3));
    // The line drawn for it leaves out both shared stretches but 40 m.
    final line = alternateLinePoints(alt);
    expect(
      distanceBetween(line.first, detour.pointAt(alt.divergence - 40)),
      lessThan(0.01),
    );
    expect(
      distanceBetween(line.last, detour.pointAt(alt.rejoin!.alternate + 40)),
      lessThan(0.01),
    );
  });

  // A long trip: each route measures metres in its own planar frame
  // (anchored at its first point), so the rejoin, found on the routes
  // reversed, must be mapped back by position, not by length.
  for (final (lat, bearing) in [(21.0, 45.0), (21.0, 225.0), (50.0, 45.0)]) {
    flowTest('on a 100 km trip at latitude $lat, heading $bearing°, the '
        'line ends just past the real rejoin', (tester, h) async {
      final origin = GeoPoint(lat, 105.8);
      final (main, detour) = longDetour(origin, bearing);
      h.flow.previewRoutes([main, detour]);
      h.flow.start();
      final alt = h.flow.alternates.value.single;
      final back = offsetPoint(origin, bearing, 3000);
      expect(alt.rejoin!.current, closeTo(3000, 15));
      // The last sample off the route is 30 to 40 m before the rejoin, and
      // the line reaches 40 m past it.
      final line = alternateLinePoints(alt);
      expect(distanceBetween(line.last, back), lessThan(15));
      expect(
        distanceBetween(detour.pointAt(alt.rejoin!.alternate), back),
        inInclusiveRange(25, 45),
      );
    });
  }

  flowTest('an alternate to another end has no rejoin', (tester, h) async {
    h.flow.previewRoutes([northRoute(), branchRoute(1500)]);
    h.flow.start();
    expect(h.flow.alternates.value.single.rejoin, isNull);
  });

  flowTest('the rejoin is kept when the time delta is measured again', (
    tester,
    h,
  ) async {
    final north = northRoute();
    // 180 s in all at 20 m/s against 300 s.
    final detour = detourRoute(speed: 20);
    h.flow.previewRoutes([north, detour]);
    h.flow.start();
    final before = h.flow.alternates.value.single;
    expect(before.minutesDelta, -2);
    // At ~900 m: 135 s left on the detour against 210 s.
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 880.0 + 10 * s));
    final after = h.flow.alternates.value.single;
    expect(after.minutesDelta, -1);
    expect(after.rejoin, isNotNull);
    expect(after.rejoin, before.rejoin);
  });

  test('minutesDelta rounds the time delta to whole minutes', () {
    AlternateRoute alt(int seconds) => AlternateRoute(
      route: northRoute(),
      timeDelta: Duration(seconds: seconds),
      divergence: 0,
    );
    expect(alt(-60).minutesDelta, -1);
    expect(alt(100).minutesDelta, 2);
    expect(alt(20).minutesDelta, 0);
  });

  flowTest('start keeps the unselected routes as alternates', (
    tester,
    h,
  ) async {
    final north = northRoute();
    final fast = branchRoute(1500); // 2400 m against 3000 m at 10 m/s
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    final alts = h.flow.alternates.value;
    expect(alts, hasLength(1));
    expect(alts.single.route, same(fast));
    expect(alts.single.divergence, closeTo(1550, 3));
    expect(alts.single.timeDelta.inSeconds, closeTo(-60, 2));
    expect(alts.single.minutesDelta, -1);
    expect(h.recording.shownAlternates!.single.route, same(fast));
  });

  flowTest('an alternate identical to the route is not kept at start', (
    tester,
    h,
  ) async {
    final north = northRoute();
    h.flow.previewRoutes([north, NavRoute.fromPoints(north.points)]);
    h.flow.start();
    await h.run(tester, 1, fixAt: (s) => h.fixOn(north, 100));
    expect(h.flow.alternates.value, isEmpty);
    expect(h.recording.alternateShows, 0);
  });

  flowTest('the time delta follows the trip', (tester, h) async {
    final north = northRoute();
    // 120 s in all at 20 m/s against 300 s.
    final fast = branchRoute(1500, speed: 20);
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    expect(h.flow.alternates.value.single.minutesDelta, -3);
    final shows = h.recording.alternateShows;
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 980.0 + 10 * s));
    // At ~1000 m: 70 s left on the branch against 200 s.
    expect(h.flow.alternates.value.single.minutesDelta, -2);
    expect(h.recording.alternateShows, greaterThan(shows));
  });

  flowTest('an alternate is dropped once its divergence point is 20 m '
      'behind', (tester, h) async {
    final north = northRoute();
    h.flow.previewRoutes([north, branchRoute(1500)]);
    h.flow.start();
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 1480.0 + 10 * s));
    expect(h.flow.alternates.value, hasLength(1), reason: 'before ~1548 m');
    await h.run(tester, 4, fixAt: (s) => h.fixOn(north, 1540.0 + 10 * s));
    expect(h.flow.alternates.value, isEmpty);
    expect(h.recording.shownAlternates, isNull);
  });

  late CountingRouteProvider provider;
  flowTest(
    'a reroute refetches alternatives once, with maxAlternatives 2',
    (tester, h) async {
      final north = northRoute();
      h.flow.previewRoutes([north]);
      h.flow.start();
      await h.run(tester, 6, fixAt: (s) => h.offRoute(north, s));
      await h.run(tester, 0.5);
      expect(provider.reroutes, 1);
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.maxAlternatives, 2);
      expect(provider.requests.single.to, north.points.last);
      final current = (h.flow.state.value as FlowNavigating).route;
      expect(current.name, 'direct');
      // The refetched 'direct' is a copy of the current route: not kept.
      expect(h.flow.alternates.value.map((a) => a.route.name), ['east']);
      expect(h.recording.shownAlternates!.single.route.name, 'east');
    },
    provider: () => provider = CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to], name: 'direct'),
        NavRoute.fromPoints([
          from,
          offsetPoint(from, 90, 600),
          to,
        ], name: 'east'),
      ],
    ),
  );

  late Completer<List<NavRoute>> gate;
  flowTest(
    'a refetch that completes after the route changed is dropped',
    (tester, h) async {
      gate = Completer();
      provider.routesHandler = (_, _) => gate.future;
      final north = northRoute();
      h.flow.previewRoutes([north]);
      h.flow.start();
      await h.run(tester, 6, fixAt: (s) => h.offRoute(north, s));
      await h.run(tester, 0.5);
      expect(provider.requests, hasLength(1), reason: 'pending');
      h.flow.stop();
      h.flow.previewRoutes([northRoute()]);
      h.flow.start();
      gate.complete([northRoute(), branchRoute(1500)]);
      await tester.pump();
      expect(h.flow.alternates.value, isEmpty);
      expect(h.recording.shownAlternates, isNull);
    },
    provider: () => provider = CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to]),
      ],
    ),
  );

  flowTest(
    'selectAlternate switches the route without a request and keeps '
    'guidance consistent',
    (tester, h) async {
      final north = northRoute();
      final fast = branchRoute(1500);
      const label = PlaceLabel(name: 'End');
      h.flow.previewRoutes([north, fast], destination: label);
      h.flow.start();
      await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
      final requests = provider.requests.length;
      h.flow.selectAlternate(0);
      final state = h.flow.state.value as FlowNavigating;
      expect(state.route, same(fast));
      expect(state.destination, label);
      expect(h.session.route, same(fast));
      expect(provider.requests, hasLength(requests));
      expect(provider.reroutes, 0);
      expect(h.flow.rerouting.value, isFalse);
      // The old route still lies ahead of its divergence: an alternate.
      expect(h.flow.alternates.value.single.route, same(north));
      expect(h.flow.alternates.value.single.minutesDelta, 1);
      await h.run(tester, 2, fixAt: (s) => h.fixOn(fast, 530.0 + 10 * s));
      expect(
        h.session.guidanceState!.remaining,
        closeTo(fast.length - 540, 20),
      );
      expect(
        h.flow.tripProgress.value!.remainingDistance,
        closeTo(fast.length - 540, 20),
      );
    },
    provider: () =>
        provider = CountingRouteProvider((_, _) async => const <NavRoute>[]),
  );

  flowTest('selectAlternate onto a refetched alternate maps the vehicle onto '
      'it, and the old route stays an alternate while it lies ahead', (
    tester,
    h,
  ) async {
    final north = northRoute();
    // Refetched where the vehicle was, 1000 m along: 1400 m, forking at
    // 500 m (1500 m on north).
    final refetched = NavRoute.fromPoints(
      branchRoute(1500).points.skip(20).toList(),
      name: 'refetched',
      fallbackSpeed: 10,
    );
    h.flow.previewRoutes([north, refetched]);
    h.flow.start();
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 1180.0 + 10 * s));
    final driven = h.session.frame!.routeDistance!;
    expect(driven, closeTo(1200, 15));
    // 1800 m left on north against 1200 m on the alternate, at 10 m/s.
    expect(h.flow.alternates.value.single.minutesDelta, -1);
    h.flow.selectAlternate(0);
    expect(h.session.route, same(refetched));
    expect(
      h.flow.tripProgress.value!.remainingDistance,
      closeTo(refetched.length - (driven - 1000), 5),
      reason: 'the first progress measures the vehicle on the new route',
    );
    // North leaves the new route 528 m along it, ahead of the vehicle.
    final old = h.flow.alternates.value.single;
    expect(old.route, same(north));
    expect(old.minutesDelta, 1);
    await h.run(tester, 1, fixAt: (s) => h.fixOn(refetched, driven - 990));
    expect(
      h.flow.tripProgress.value!.remainingDistance,
      closeTo(refetched.length - (driven - 990), 20),
    );
    expect(h.flow.alternates.value.single.route, same(north));
    expect(h.flow.alternates.value.single.minutesDelta, 1);
  });

  flowTest('Resume onto a refetched alternate from the trip overview maps '
      'the vehicle onto it, and the old route stays an alternate while it '
      'lies ahead', (tester, h) async {
    final north = northRoute();
    final refetched = NavRoute.fromPoints(
      branchRoute(1500).points.skip(20).toList(),
      name: 'refetched',
      fallbackSpeed: 10,
    );
    h.flow.previewRoutes([north, refetched]);
    h.flow.start();
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 1180.0 + 10 * s));
    final driven = h.session.frame!.routeDistance!;
    h.flow.backToOverview();
    h.flow.select(1);
    h.flow.start();
    expect(h.session.route, same(refetched));
    expect(
      h.flow.tripProgress.value!.remainingDistance,
      closeTo(refetched.length - (driven - 1000), 5),
    );
    final old = h.flow.alternates.value.single;
    expect(old.route, same(north));
    expect(old.minutesDelta, 1);
    await h.run(tester, 1, fixAt: (s) => h.fixOn(refetched, driven - 990));
    expect(h.flow.alternates.value.single.route, same(north));
    expect(h.flow.alternates.value.single.minutesDelta, 1);
  });

  flowTest('selectAlternate needs navigating and a valid index', (
    tester,
    h,
  ) async {
    expect(() => h.flow.selectAlternate(0), throwsStateError);
    h.flow.previewRoutes([northRoute()]);
    h.flow.start();
    expect(() => h.flow.selectAlternate(0), throwsRangeError);
  });

  flowTest('a tap on the map selects the alternate', (tester, h) async {
    final fast = branchRoute(1500);
    h.flow.previewRoutes([northRoute(), fast]);
    h.flow.start();
    h.recording.alternateTap!(0);
    expect((h.flow.state.value as FlowNavigating).route, same(fast));
  });

  flowTest('selectAlternate ends a step preview, even on a route with fewer '
      'steps', (tester, h) async {
    final north = northRoute();
    final fast = branchRoute(1500); // no steps
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    await h.run(tester, 2, fixAt: (s) => h.fixOn(north, 300.0 + 10 * s));
    h.flow.previewStep(3);
    expect(h.flow.previewedStep.value, 3, reason: 'the preview is active');
    expect(h.session.follow, isFalse);
    h.flow.selectAlternate(0);
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue);
    await h.run(tester, 1, fixAt: (s) => h.fixOn(fast, 330));
    expect(tester.takeException(), isNull);
  });

  flowTest('the trip overview lists the alternates; Resume on another '
      'switches to it', (tester, h) async {
    final north = northRoute();
    final fast = branchRoute(1500);
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    await h.run(tester, 2, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
    h.flow.backToOverview();
    final overview = h.flow.state.value as FlowOverview;
    expect(overview.routes, [same(north), same(fast)]);
    expect(overview.selected, 0);
    expect(h.flow.alternates.value, isEmpty);
    expect(h.recording.shownAlternates, isNull);
    h.flow.select(1);
    h.flow.start();
    expect(h.session.route, same(fast));
    expect(h.flow.alternates.value.single.route, same(north));
  });

  flowTest('Resume on the same route keeps its alternates', (tester, h) async {
    final north = northRoute();
    final fast = branchRoute(1500);
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    await h.run(tester, 2, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
    h.flow.backToOverview();
    h.flow.start();
    expect(h.session.route, same(north));
    expect(h.flow.alternates.value.single.route, same(fast));
  });

  flowTest('arrival and stop clear the alternates', (tester, h) async {
    final north = northRoute();
    h.flow.previewRoutes([north, branchRoute(1500)]);
    h.flow.start();
    expect(h.flow.alternates.value, hasLength(1));
    h.flow.stop();
    expect(h.flow.alternates.value, isEmpty);
    expect(h.recording.shownAlternates, isNull);
    h.flow.previewRoutes([north, branchRoute(2500)]);
    h.flow.start();
    await h.arriveOn(tester, north);
    expect(h.flow.state.value, isA<FlowArrived>());
    expect(h.flow.alternates.value, isEmpty);
  });

  flowTest('refreshAlternates draws them on a newly attached map', (
    tester,
    h,
  ) async {
    final fast = branchRoute(1500);
    h.flow.previewRoutes([northRoute(), fast]);
    h.flow.start();
    final second = RecordingMap();
    h.session.map = second;
    h.flow.refreshAlternates();
    expect(second.shownAlternates!.single.route, same(fast));
  });

  flowTest(
    'a map without AlternateRoutesMap still gets alternates in the flow',
    (tester, h) async {
      h.flow.previewRoutes([northRoute(), branchRoute(1500)]);
      h.flow.start();
      expect(h.flow.alternates.value, hasLength(1));
      h.flow.refreshAlternates();
    },
    map: PlainMap.new,
  );

  flowTest('selectAlternate publishes the remaining distance on the new route '
      'at once', (tester, h) async {
    final north = northRoute();
    final fast = branchRoute(1500);
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
    final driven = h.session.frame!.routeDistance!;
    final published = <double>[];
    h.flow.tripProgress.addListener(
      () => published.add(h.flow.tripProgress.value!.remainingDistance),
    );
    h.flow.selectAlternate(0);
    final progress = h.flow.tripProgress.value!;
    expect(progress.remainingDistance, closeTo(fast.length - driven, 5));
    expect(progress.remainingDistance, lessThan(fast.length - 400));
    expect(progress.fraction, closeTo(driven / fast.length, 0.01));
    expect(
      published.where((d) => d > fast.length - 400),
      isEmpty,
      reason: 'the whole new route is never published as remaining',
    );
  });

  flowTest('a Start on another route from the trip overview publishes the '
      'remaining distance on it at once', (tester, h) async {
    final north = northRoute();
    final fast = branchRoute(1500);
    h.flow.previewRoutes([north, fast]);
    h.flow.start();
    await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
    final driven = h.session.frame!.routeDistance!;
    h.flow.backToOverview();
    h.flow.select(1);
    h.flow.start();
    expect(h.session.route, same(fast));
    final progress = h.flow.tripProgress.value!;
    expect(progress.remainingDistance, closeTo(fast.length - driven, 5));
    expect(progress.remainingDistance, lessThan(fast.length - 400));
  });

  late CountingRouteProvider throttled;
  late Completer<void> firstReroute;
  var reroutesAsked = 0;
  flowTest(
    'two reroutes within the reroute interval make one alternates request',
    (tester, h) async {
      reroutesAsked = 0;
      firstReroute = Completer();
      final north = northRoute();
      h.flow.previewRoutes([north]);
      h.flow.start();
      NavFix? off(int _) => NavFix(
        position: offsetPoint(north.pointAt(800), 90, 60),
        accuracy: 5,
        speed: 5,
        time: h.now,
      );
      await h.run(tester, 6, fixAt: off);
      expect(throttled.reroutes, 1, reason: 'the first reroute is pending');
      await h.run(tester, 2, fixAt: off);
      firstReroute.complete();
      await h.run(tester, 1, fixAt: off);
      expect(throttled.requests, hasLength(1), reason: 'after the first');
      await h.run(tester, 14, fixAt: off);
      expect(throttled.reroutes, 2);
      expect(throttled.requests, hasLength(1), reason: 'within the interval');
    },
    provider: () => throttled = CountingRouteProvider((from, to) async {
      // The first answer comes late; each one leaves the vehicle off the
      // new route, so the session reroutes again.
      if (++reroutesAsked == 1) await firstReroute.future;
      return [
        NavRoute.fromPoints([offsetPoint(from, 90, 500), to]),
      ];
    }, routesHandler: (_, _) async => const <NavRoute>[]),
  );

  late CountingRouteProvider noRefetch;
  flowTest(
    'with fetchAlternatesOnReroute false a reroute makes no alternates '
    'request',
    (tester, h) async {
      expect(h.flow.fetchAlternatesOnReroute, isFalse);
      final north = northRoute();
      h.flow.previewRoutes([north, branchRoute(1500)]);
      h.flow.start();
      await h.run(tester, 6, fixAt: (s) => h.offRoute(north, s));
      await h.run(tester, 0.5);
      expect(noRefetch.reroutes, 1);
      expect((h.flow.state.value as FlowNavigating).route.name, 'direct');
      expect(noRefetch.requests, isEmpty);
      expect(h.flow.alternates.value, isEmpty);
    },
    fetchAlternatesOnReroute: false,
    provider: () => noRefetch = CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to], name: 'direct'),
        NavRoute.fromPoints([
          from,
          offsetPoint(from, 90, 600),
          to,
        ], name: 'east'),
      ],
    ),
  );

  flowTest('fetchAlternatesOnReroute is on by default', (tester, h) async {
    expect(h.flow.fetchAlternatesOnReroute, isTrue);
  });

  late CountingRouteProvider failing;
  flowTest(
    'a provider failure on the alternates refetch is ignored',
    (tester, h) async {
      final errors = collectFlutterErrors();
      final north = northRoute();
      h.flow.previewRoutes([north]);
      h.flow.start();
      final states = <NavigationFlowState>[];
      h.flow.state.addListener(() => states.add(h.flow.state.value));
      await h.run(tester, 6, fixAt: (s) => h.offRoute(north, s));
      await h.run(tester, 0.5);
      expect(failing.requests, hasLength(1), reason: 'the refetch was tried');
      expect(states, hasLength(1), reason: 'only the reroute changed it');
      expect((h.flow.state.value as FlowNavigating).route.name, 'direct');
      expect(h.flow.alternates.value, isEmpty);
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    },
    provider: () => failing = CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to], name: 'direct'),
      ],
      routesHandler: (_, _) async => throw StateError('offline'),
    ),
  );
}
