import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026);

  test('same seed, same fixes', () {
    final a = GpsSimulator(sampleRoute, seed: 3);
    final b = GpsSimulator(sampleRoute, seed: 3);
    for (var i = 0; i < 100; i++) {
      a.advance(0.1);
      b.advance(0.1);
    }
    final now = t0.add(const Duration(seconds: 10));
    expect(a.sample(now).position, b.sample(now).position);
  });

  test('drives the whole route and finishes', () {
    final sim = GpsSimulator(sampleRoute);
    for (var t = 0.0; t < 1200 && !sim.finished; t += 0.1) {
      sim.advance(0.1);
    }
    expect(sim.finished, isTrue);
    expect(sim.distance, closeTo(sampleRoute.length, 0.01));
  });

  test('fixes are stamped with the time they were measured', () {
    final sim = GpsSimulator(sampleRoute)..advance(5);
    final now = t0.add(const Duration(seconds: 5));
    final fix = sim.sample(now, age: 0.6);
    expect(now.difference(fix.time), const Duration(milliseconds: 600));
    expect(fix.speed, isNotNull);
    expect(fix.heading, isNotNull);
  });

  test('driveOffRoute leaves the route', () {
    final sim = GpsSimulator(sampleRoute)..teleport(1000);
    for (var i = 0; i < 50; i++) {
      sim.advance(0.1);
    }
    sim.driveOffRoute();
    for (var i = 0; i < 100; i++) {
      sim.advance(0.1);
    }
    expect(sim.isOffRoute, isTrue);
    expect(sampleRoute.snap(sim.position).offset, greaterThan(30));
  });

  test('SimulatedFixSource streams fixes in real time', () async {
    final source = SimulatedFixSource(GpsSimulator(sampleRoute));
    addTearDown(source.dispose);
    final first = source.fixes.first;
    source.start();
    expect(source.isRunning, isTrue);
    final fix = await first.timeout(const Duration(seconds: 3));
    source.dispose();
    expect(source.isRunning, isFalse);
    expect(fix.accuracy, inInclusiveRange(5, 48));
    expect(fix.speed, isNotNull);
    expect(fix.heading, isNotNull);
    expect(
      DateTime.now().difference(fix.time).abs(),
      lessThan(const Duration(seconds: 2)),
    );
  });

  test('a different seed gives a different fix', () {
    final a = GpsSimulator(sampleRoute, seed: 3)..advance(5);
    final b = GpsSimulator(sampleRoute, seed: 4)..advance(5);
    final now = t0.add(const Duration(seconds: 5));
    expect(a.sample(now).position, isNot(b.sample(now).position));
  });

  test('setRoute continues from the nearest point and clears off-route', () {
    final sim = GpsSimulator(sampleRoute)..teleport(1000);
    for (var i = 0; i < 50; i++) {
      sim.advance(0.1);
    }
    sim.driveOffRoute();
    for (var i = 0; i < 50; i++) {
      sim.advance(0.1);
    }
    expect(sim.isOffRoute, isTrue);
    final here = sim.position;
    final reroute = NavRoute.fromPoints([here, offsetPoint(here, 90, 500)]);
    sim.setRoute(reroute);
    expect(sim.isOffRoute, isFalse);
    expect(sim.route, same(reroute));
    expect(sim.distance, closeTo(0, 1));
    expect(distanceBetween(sim.position, here), lessThan(1));
  });

  test('setRoute with keepPosition places the car anywhere on the new '
      'route', () {
    // A switch onto a route that shares the road (an alternate picked mid
    // trip): the car stays where it is, 1500 m along, instead of being
    // looked for within the new route's first 150 m.
    final sim = GpsSimulator(sampleRoute)..teleport(1500);
    final here = sim.position;
    final copy = NavRoute.fromPoints(sampleRoute.points);
    sim.setRoute(copy, keepPosition: true);
    expect(sim.route, same(copy));
    expect(sim.distance, closeTo(1500, 1));
    expect(distanceBetween(sim.position, here), lessThan(1));
  });

  test('setRoute with keepPosition onto a diverging alternate takes the '
      'nearest point of the whole route', () {
    final alt = sampleRouteAlternatives.single;
    final sim = GpsSimulator(sampleRoute)..teleport(1500);
    final here = sim.position;
    final nearest = alt.snap(here);
    sim.setRoute(alt, keepPosition: true);
    expect(sim.distance, closeTo(nearest.distance, 1e-6));
    expect(
      distanceBetween(sim.position, here),
      closeTo(nearest.offset, 1),
      reason: 'no jump beyond the gap between the two roads',
    );
    expect(sim.distance, greaterThan(150));
  });

  test('teleport puts the car there, stopped, and skips passed red lights', () {
    final sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights)
      ..teleport(420);
    expect(sim.distance, 420);
    expect(sim.speed, 0);
    for (var i = 0; i < 30; i++) {
      sim.advance(0.1);
    }
    expect(sim.speed, greaterThan(0), reason: 'the light at 420 is behind us');
  });

  test('a red light ahead of a teleport stops the car', () {
    final sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights)
      ..teleport(400);
    var stoppedAfterLight = false;
    for (var t = 0.0; t < 120; t += 0.1) {
      sim.advance(0.1);
      if (sim.distance >= 420 && sim.distance < 426 && sim.speed == 0) {
        stoppedAfterLight = true;
        break;
      }
    }
    expect(stoppedAfterLight, isTrue);
  });

  test('no red lights unless given: they belong to sampleRoute', () {
    expect(sampleRouteRedLights, [420.0, 2650.0]);
    expect(GpsSimulator(sampleRoute).stops, isEmpty);
    final sim = GpsSimulator(sampleRoute)..teleport(400);
    for (var t = 0.0; t < 20; t += 0.1) {
      sim.advance(0.1);
      expect(sim.speed, greaterThan(0), reason: 'at ${sim.distance} m');
    }
    expect(sim.distance, greaterThan(450));
  });

  test('SimulatedFixSource stamps fixes with its clock', () async {
    final fake = DateTime.utc(2030);
    final source = SimulatedFixSource(
      GpsSimulator(sampleRoute),
      clock: () => fake,
    );
    addTearDown(source.dispose);
    final first = source.fixes.first;
    source.start();
    final fix = await first.timeout(const Duration(seconds: 3));
    // Measured 0.6 s before it was delivered, on the injected clock.
    expect(fake.difference(fix.time), const Duration(milliseconds: 600));
  });

  test('SimulatedFixSource lifecycle misuse is harmless', () {
    final source = SimulatedFixSource(GpsSimulator(sampleRoute));
    addTearDown(source.dispose);
    source.stop();
    expect(source.isRunning, isFalse);
    source
      ..start()
      ..start();
    expect(source.isRunning, isTrue);
    source
      ..stop()
      ..stop();
    expect(source.isRunning, isFalse);
    source
      ..dispose()
      ..dispose();
    expect(source.isRunning, isFalse);
    source.start();
    expect(source.isRunning, isFalse);
  });
}
