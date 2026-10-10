import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  final route = sampleRoute;

  test('sample route: 205 points, 14 steps, ~5468 m', () {
    expect(route.points, hasLength(205));
    expect(route.steps, hasLength(14));
    expect(route.length, closeTo(5468, 55));
  });

  test('a point on the route snaps to itself', () {
    final p = route.pointAt(1234);
    final snap = route.snap(p);
    expect(snap.distance, closeTo(1234, 0.5));
    expect(snap.offset, lessThan(0.5));
  });

  test('a point beside the road snaps across to it', () {
    const at = 2000.0;
    final p = offsetPoint(route.pointAt(at), route.bearingAt(at) + 90, 8);
    final snap = route.snap(p, near: at - 10);
    expect(snap.offset, closeTo(8, 0.5));
    expect(snap.distance, closeTo(at, 1));
  });

  group('U-turn on a divided road (out and back)', () {
    final uturn = route.steps.firstWhere(
      (s) => s.modifier == ManeuverModifier.uturn,
    );
    // 100 m before the U-turn on the way out; the opposite carriageway (the
    // way back) runs ~37 m beside it.
    final outbound = uturn.distance - 100;
    final onRoad = route.pointAt(outbound);
    final across = route.snap(
      onRoad,
      near: uturn.distance + 70,
      behind: 0,
      ahead: 120,
    );
    // Multipath pulls the fix 20 m towards the other carriageway.
    final drifted = offsetPoint(
      onRoad,
      bearingBetween(onRoad, across.point),
      20,
    );

    test('the carriageways are ~37 m apart', () {
      expect(across.offset, inInclusiveRange(30, 45));
    });

    test('a global search jumps to the wrong carriageway', () {
      expect(route.snap(drifted).distance, greaterThan(uturn.distance));
    });

    test('a fixed 250 m window still reaches across the U-turn', () {
      final snap = route.snap(drifted, near: outbound - 11);
      expect(snap.distance, greaterThan(uturn.distance));
    });

    test('a window sized to the speed keeps the right carriageway', () {
      // What RouteMotionEngine does: 1 s since the last fix at 11 m/s.
      final snap = route.snap(
        drifted,
        near: outbound - 11,
        behind: 30,
        ahead: 40 + 11 * 1.5,
      );
      expect(snap.distance, closeTo(outbound, 2));
    });
  });

  test('bearingAt turns gradually through a corner', () {
    final turn = route.steps.firstWhere((s) => s.roadName == 'Ly Tu Trong');
    final before = route.bearingAt(turn.distance - 40);
    final after = route.bearingAt(turn.distance + 40);
    final mid = route.bearingAt(turn.distance);
    final total = angleDelta(before, after).abs();
    expect(total, greaterThan(60));
    // Half way through the corner the heading is partly rotated.
    expect(angleDelta(before, mid).abs(), inExclusiveRange(5, total - 5));
  });

  test('splitAt covers the whole route without gaps', () {
    final (done, ahead) = route.splitAt(3000);
    expect(done.last, ahead.first);
    expect(done.length + ahead.length, route.points.length + 2);
  });

  group('pointsBetween', () {
    // 0 m, 100 m, 200 m, 300 m due north.
    final line = NavRoute.fromPoints([
      for (var d = 0.0; d <= 300; d += 100)
        offsetPoint(const GeoPoint(10.77, 106.70), 0, d),
    ]);

    void expectNear(List<GeoPoint> actual, List<GeoPoint> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < actual.length; i++) {
        expect(
          distanceBetween(actual[i], expected[i]),
          lessThan(0.01),
          reason: 'point $i',
        );
      }
    }

    test('interpolates both ends and keeps the vertices between', () {
      expectNear(line.pointsBetween(50, 250), [
        line.pointAt(50),
        line.points[1],
        line.points[2],
        line.pointAt(250),
      ]);
    });

    test('an end on a vertex (to the millimetre) is that vertex, once', () {
      expect(line.pointsBetween(100, 200), [line.points[1], line.points[2]]);
      expect(line.pointsBetween(100 - 1e-4, 200 - 1e-4), [
        line.points[1],
        line.points[2],
      ]);
      expect(line.pointsBetween(100 + 1e-4, 200 + 1e-4), [
        line.points[1],
        line.points[2],
      ]);
      expect(line.pointsBetween(0, line.length), line.points);
    });

    test('within one segment it is the two ends', () {
      expectNear(line.pointsBetween(120, 180), [
        line.pointAt(120),
        line.pointAt(180),
      ]);
    });

    test('the ends are clamped to the route; an empty range is its one '
        'point twice', () {
      expect(line.pointsBetween(-50, 400), line.points);
      expectNear(line.pointsBetween(150, 150), [
        line.pointAt(150),
        line.pointAt(150),
      ]);
      expectNear(line.pointsBetween(200, 100), [
        line.pointAt(200),
        line.pointAt(200),
      ]);
    });

    test('on the sample route it covers the same ground as splitAt', () {
      final part = route.pointsBetween(1000, 3000);
      final (_, ahead) = route.splitAt(1000);
      final (done, _) = route.splitAt(3000);
      final inner = ahead.where((p) => done.contains(p)).toList();
      expectNear(part, [route.pointAt(1000), ...inner, route.pointAt(3000)]);
    });
  });

  test('distanceAtVertex is the distance along the route at each point', () {
    expect(route.distanceAtVertex(0), 0);
    expect(route.distanceAtVertex(route.points.length - 1), route.length);
    for (final i in [1, 50, 120, 203]) {
      final d = route.distanceAtVertex(i);
      expect(
        distanceBetween(route.pointAt(d), route.points[i]),
        lessThan(0.01),
      );
      expect(d, greaterThanOrEqualTo(route.distanceAtVertex(i - 1)));
    }
    expect(() => route.distanceAtVertex(-1), throwsRangeError);
    expect(() => route.distanceAtVertex(route.points.length), throwsRangeError);
  });

  test('nextStep returns the first step strictly ahead', () {
    final second = route.steps[1];
    expect(route.nextStep(second.distance - 10), same(second));
    expect(route.nextStep(route.length), isNull);
  });

  group('RouteStepSeed.atLocation', () {
    test('resolves like atVertex on the sample route', () {
      final rebuilt = NavRoute.fromPoints(
        route.points,
        steps: [
          for (final s in route.steps)
            RouteStepSeed.atLocation(
              route.pointAt(s.distance),
              type: s.type,
              modifier: s.modifier,
              roadName: s.roadName,
            ),
        ],
      );
      for (var i = 0; i < route.steps.length; i++) {
        expect(
          rebuilt.steps[i].distance,
          closeTo(route.steps[i].distance, 0.01),
          reason: 'step $i',
        );
      }
    });

    test('searches forward, so a U-turn back to the start resolves to the '
        'last vertex, not the first', () {
      const a = GeoPoint(10.77, 106.69);
      final b = offsetPoint(a, 0, 100);
      final out = NavRoute.fromPoints(
        [a, b, a],
        steps: [
          const RouteStepSeed.atLocation(a, type: ManeuverType.depart),
          RouteStepSeed.atLocation(
            b,
            type: ManeuverType.continueOn,
            modifier: ManeuverModifier.uturn,
          ),
          const RouteStepSeed.atLocation(a, type: ManeuverType.arrive),
        ],
      );
      expect(out.steps.map((s) => s.distance), [
        0,
        closeTo(100, 0.01),
        closeTo(200, 0.01),
      ]);
    });
  });

  group('fromPoints validation', () {
    test('needs at least 2 points', () {
      expect(
        () => NavRoute.fromPoints(const [GeoPoint(10, 106)]),
        throwsArgumentError,
      );
    });

    test('rejects a vertex out of range', () {
      expect(
        () => NavRoute.fromPoints(
          const [GeoPoint(10, 106), GeoPoint(10.001, 106)],
          steps: const [RouteStepSeed.atVertex(2, type: ManeuverType.arrive)],
        ),
        throwsArgumentError,
      );
    });
  });

  test('duplicate consecutive points (zero-length segments) stay finite', () {
    const a = GeoPoint(10.77, 106.69);
    final b = offsetPoint(a, 90, 50);
    final r = NavRoute.fromPoints([a, a, b, b]);
    expect(r.length, closeTo(50, 0.1));
    for (final d in [0.0, 25.0, 50.0]) {
      expect(r.pointAt(d).lat.isFinite, isTrue);
      expect(r.bearingAt(d), closeTo(90, 0.1));
    }
    final snap = r.snap(offsetPoint(a, 0, 5));
    expect(snap.distance, closeTo(0, 0.1));
    expect(snap.offset, closeTo(5, 0.1));
  });

  test('ManeuverModifier.isLeft', () {
    expect(ManeuverModifier.slightLeft.isLeft, isTrue);
    expect(ManeuverModifier.sharpLeft.isLeft, isTrue);
    expect(ManeuverModifier.right.isLeft, isFalse);
    expect(ManeuverModifier.uturn.isLeft, isFalse);
  });
}
