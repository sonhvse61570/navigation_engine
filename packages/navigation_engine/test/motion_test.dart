import 'dart:math' as math;

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

/// One simulated drive: 60 fps frames, a fix every ~1 s delivered 0.6 s late.
class SimRun {
  final frames = <(double t, double truth, MotionFrame f)>[];
  final rawJumps = <double>[];
  var rejected = 0;
}

SimRun simulate(
  MotionEngine engine, {
  double seconds = 900,
  int seed = 7,
  bool withSpeed = true,
}) {
  final sim = GpsSimulator(
    sampleRoute,
    seed: seed,
    stops: sampleRouteRedLights,
  );
  final filter = FixFilter();
  final run = SimRun();
  final t0 = DateTime.utc(2026);
  const dt = 1 / 60;
  var nextFix = 1.0;
  GeoPoint? lastRaw;
  for (var t = 0.0; t < seconds && !sim.finished; t += dt) {
    sim.advance(dt);
    final now = t0.add(Duration(microseconds: (t * 1e6).round()));
    if (t >= nextFix) {
      nextFix += 0.85 + (seed * t * 7919 % 300) / 1000; // 0.85–1.15 s
      final sampled = sim.sample(now);
      // Some receivers report no speed at all.
      final fix = withSpeed
          ? sampled
          : NavFix(
              position: sampled.position,
              accuracy: sampled.accuracy,
              time: sampled.time,
              heading: sampled.heading,
            );
      if (filter.accept(fix)) {
        if (lastRaw != null) {
          run.rawJumps.add(distanceBetween(lastRaw, fix.position));
        }
        lastRaw = fix.position;
        engine.onFix(fix, now);
      } else {
        run.rejected++;
      }
    }
    final f = engine.tick(dt, now);
    if (f != null) run.frames.add((t, sim.distance, f));
  }
  return run;
}

void main() {
  group('RouteMotionEngine on the simulated drive', () {
    final run = simulate(RouteMotionEngine(sampleRoute));
    final moving = run.frames.where((r) => r.$1 > 5).toList();

    test('the drive covers the route', () {
      expect(
        moving.last.$3.routeDistance,
        greaterThan(sampleRoute.length - 30),
      );
    });

    test('never moves backwards', () {
      for (var i = 1; i < run.frames.length; i++) {
        expect(
          run.frames[i].$3.routeDistance!,
          greaterThanOrEqualTo(run.frames[i - 1].$3.routeDistance!),
        );
      }
    });

    test('no frame-to-frame jump (smooth at 60 fps)', () {
      var worst = 0.0;
      for (var i = 1; i < moving.length; i++) {
        final d = distanceBetween(
          moving[i - 1].$3.position,
          moving[i].$3.position,
        );
        worst = math.max(worst, d);
      }
      // ~12 m/s (cruise + speed noise) + at most 5 m/s of correction.
      expect(worst, lessThan(17 / 60));
      // ...while consecutive raw fixes are metres apart.
      expect(run.rawJumps.reduce(math.max), greaterThan(10));
    });

    test('the vehicle stays close to the true position', () {
      final errors = [
        for (final r in moving) (r.$3.routeDistance! - r.$2).abs(),
      ]..sort();
      final p95 = errors[(errors.length * 0.95).floor()];
      expect(p95, lessThan(12), reason: 'p95 along-route error $p95 m');
    });

    test('heading never spins, even when stopped at the red lights', () {
      var worst = 0.0;
      for (var i = 1; i < moving.length; i++) {
        worst = math.max(
          worst,
          angleDelta(moving[i - 1].$3.bearing, moving[i].$3.bearing).abs(),
        );
      }
      // The U-turn is the sharpest: 180° over a few seconds.
      expect(worst, lessThan(6));
    });

    test('outliers are filtered', () {
      expect(run.rejected, greaterThan(0));
    });
  });

  group('RouteMotionEngine on the simulated drive without speed', () {
    final run = simulate(RouteMotionEngine(sampleRoute), withSpeed: false);
    final settled = run.frames.where((r) => r.$1 > 10).toList();

    test('the drive covers the route', () {
      expect(
        settled.last.$3.routeDistance,
        greaterThan(sampleRoute.length - 30),
      );
    });

    test('no frame-to-frame jump (smooth at 60 fps)', () {
      var worst = 0.0;
      for (var i = 1; i < settled.length; i++) {
        worst = math.max(
          worst,
          distanceBetween(settled[i - 1].$3.position, settled[i].$3.position),
        );
      }
      // The speed estimated from positions overshoots by up to ~1.5 m/s
      // (vs ~0.5 m/s of noise on a measured speed), on top of ~12 m/s and
      // at most 5 m/s of correction. 17 / 60 is not reachable: the drive
      // with a measured speed already peaks at 0.280.
      expect(worst, lessThan(19 / 60));
    });

    test('the vehicle stays close to the true position', () {
      final errors = [
        for (final r in settled) (r.$3.routeDistance! - r.$2).abs(),
      ]..sort();
      final p95 = errors[(errors.length * 0.95).floor()];
      expect(p95, lessThan(15), reason: 'p95 along-route error $p95 m');
    });
  });

  test('no frame before the first fix', () {
    final engine = RouteMotionEngine(sampleRoute);
    expect(engine.tick(1 / 60, DateTime.utc(2026)), isNull);
  });

  test('stale GPS: dead-reckoning stops instead of driving away', () {
    final engine = RouteMotionEngine(sampleRoute);
    final t0 = DateTime.utc(2026);
    engine.onFix(
      NavFix(
        position: sampleRoute.pointAt(500),
        accuracy: 5,
        speed: 10,
        time: t0,
      ),
      t0,
    );
    MotionFrame? f;
    for (var i = 1; i <= 60 * 10; i++) {
      f = engine.tick(1 / 60, t0.add(Duration(milliseconds: i * 1000 ~/ 60)));
    }
    expect(f!.speed, lessThan(0.5));
    // ~2.5 s at 10 m/s, then a smooth stop.
    expect(f.routeDistance, inInclusiveRange(520, 545));
  });

  test('off-route needs to last 3 s', () {
    final engine = RouteMotionEngine(sampleRoute);
    final t0 = DateTime.utc(2026);
    MotionFrame? last;
    for (var i = 0; i < 8; i++) {
      final t = t0.add(Duration(seconds: i));
      final on = sampleRoute.pointAt(800.0 + i * 5);
      final off = offsetPoint(
        on,
        sampleRoute.bearingAt(800) + 90,
        i == 0 ? 0 : 60,
      );
      engine.onFix(NavFix(position: off, accuracy: 5, speed: 5, time: t), t);
      last = engine.tick(1 / 60, t);
      if (i <= 3) expect(last!.offRoute, isFalse, reason: 'after ${i}s');
    }
    expect(last!.offRoute, isTrue);
  });

  test('a simulated wrong turn is flagged off route within 8 s', () {
    final sim = GpsSimulator(sampleRoute, seed: 11)..teleport(3000);
    final engine = RouteMotionEngine(sampleRoute);
    final filter = FixFilter();
    final t0 = DateTime.utc(2026);
    const dt = 1 / 60;
    double? offAt, flaggedAt;
    for (var t = 0.0; t < 40; t += dt) {
      sim.advance(dt);
      final now = t0.add(Duration(microseconds: (t * 1e6).round()));
      if (t > 10 && offAt == null) {
        sim.driveOffRoute();
        offAt = t;
      }
      if ((t * 60).round() % 60 == 0) {
        final fix = sim.sample(now);
        if (filter.accept(fix)) engine.onFix(fix, now);
      }
      final f = engine.tick(dt, now);
      if (f != null && f.offRoute && flaggedAt == null) flaggedAt = t;
      if (offAt == null) expect(f?.offRoute ?? false, isFalse);
    }
    expect(flaggedAt, isNotNull);
    // 0.6 s GPS latency + ~3 s to be 15 m away and heading across the
    // route + 3 s hysteresis (was ~9 s on distance alone).
    expect(flaggedAt! - offAt!, lessThan(8));
  });

  test('speed estimate starts afresh after a long gap without fixes', () {
    // Fixes without speed: 10 m/s for 10 s, then a 30 s stop with no fixes
    // (a tunnel, a red light), then 10 m/s again.
    final engine = RouteMotionEngine(sampleRoute);
    final t0 = DateTime.utc(2026);
    MotionFrame? f;
    void second(int sec, double? s) {
      final now = t0.add(Duration(seconds: sec));
      if (s != null) {
        engine.onFix(
          NavFix(position: sampleRoute.pointAt(s), accuracy: 5, time: now),
          now,
        );
      }
      for (var k = 0; k < 60; k++) {
        f = engine.tick(1 / 60, now.add(Duration(microseconds: k * 16667)));
      }
    }

    for (var i = 0; i <= 10; i++) {
      second(i, 100.0 + 10 * i);
    }
    for (var i = 11; i < 40; i++) {
      second(i, null);
    }
    for (var i = 40; i <= 43; i++) {
      second(i, 200.0 + 10 * (i - 40));
    }
    // The old fixes would average 10 m over ~30 s (~0.3 m/s).
    expect(f!.speed, greaterThan(7));
  });

  test('FreeMotionEngine is smooth too', () {
    final run = simulate(FreeMotionEngine(), seconds: 90);
    final moving = run.frames.where((r) => r.$1 > 5).toList();
    var worst = 0.0;
    for (var i = 1; i < moving.length; i++) {
      worst = math.max(
        worst,
        distanceBetween(moving[i - 1].$3.position, moving[i].$3.position),
      );
    }
    expect(worst, lessThan(0.8));
  });

  test('FreeMotionEngine is smooth without speed', () {
    final run = simulate(FreeMotionEngine(), seconds: 90, withSpeed: false);
    final settled = run.frames.where((r) => r.$1 > 10).toList();
    var worst = 0.0;
    for (var i = 1; i < settled.length; i++) {
      worst = math.max(
        worst,
        distanceBetween(settled[i - 1].$3.position, settled[i].$3.position),
      );
    }
    expect(worst, lessThan(0.8));
  });

  group('without speed, a jump restarts the estimate', () {
    // Fixes 1 s apart at 10 m/s, then the position jumps 1 km ahead.
    List<NavFix> fixes(GeoPoint Function(double) at) => [
      for (var i = 0; i < 4; i++)
        NavFix(
          position: at(i < 3 ? 500.0 + 10 * i : 1500),
          accuracy: 5,
          time: DateTime.utc(2026).add(Duration(seconds: i)),
        ),
    ];

    void drive(MotionEngine engine, List<NavFix> fixes) {
      for (final fix in fixes) {
        engine.onFix(fix, fix.time);
        final f = engine.tick(1 / 60, fix.time)!;
        expect(f.speed, lessThan(20), reason: 'after the fix at ${fix.time}');
      }
    }

    test('RouteMotionEngine', () {
      drive(RouteMotionEngine(sampleRoute), fixes(sampleRoute.pointAt));
    });

    test('FreeMotionEngine', () {
      const start = GeoPoint(10.77, 106.69);
      drive(FreeMotionEngine(), fixes((d) => offsetPoint(start, 45, d)));
    });
  });
}
