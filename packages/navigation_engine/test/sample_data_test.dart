import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  test('sampleRoute carries OSRM durations and a summary', () {
    expect(sampleRoute.hasProviderDurations, isTrue);
    expect(sampleRoute.duration, closeTo(496.4, 0.5));
    expect(sampleRoute.summary, 'Ly Tu Trong, Nguyen Huu Canh');
  });

  test('each step takes as long as OSRM says, turn penalties included', () {
    final s = sampleRoute.steps;
    double stepTime(int i) =>
        sampleRoute.durationAt(s[i + 1].distance) -
        sampleRoute.durationAt(s[i].distance);
    expect(stepTime(3), closeTo(153.5, 0.05)); // along Ly Tu Trong
    expect(stepTime(8), closeTo(2, 0.05)); // through the roundabout
  });

  test('sampleRoute has synthetic speed limits everywhere', () {
    expect(sampleRoute.speedLimitAt(0), closeTo(50 / 3.6, 1e-9));
    expect(sampleRoute.speedLimitAt(3000), closeTo(60 / 3.6, 1e-9));
    expect(
      sampleRoute.speedLimitAt(sampleRoute.length),
      closeTo(30 / 3.6, 1e-9),
    );
  });

  test('sampleRoute has synthetic lanes on three turns', () {
    final withLanes = [
      for (final s in sampleRoute.steps)
        if (s.lanes.isNotEmpty) s.roadName,
    ];
    expect(withLanes, ['Ly Tu Trong', 'Ton Duc Thang', 'Nguyen Huu Canh']);
    for (final s in sampleRoute.steps.where((s) => s.lanes.isNotEmpty)) {
      expect(s.lanes.where((l) => l.valid), isNotEmpty);
      expect(s.lanes.where((l) => l.active != null), hasLength(1));
    }
  });

  test('sampleRouteAlternatives is a slower route to the same place', () {
    expect(sampleRouteAlternatives, hasLength(1));
    final alt = sampleRouteAlternatives.single;
    expect(alt.length, closeTo(6639.5, 5));
    expect(alt.duration, closeTo(517.7, 0.5));
    expect(alt.duration, greaterThan(sampleRoute.duration));
    expect(alt.summary, 'Nguyen Thi Minh Khai, Dien Bien Phu');
    expect(alt.steps, hasLength(16));
    expect(alt.points.first, sampleRoute.points.first);
    expect(alt.points.last, sampleRoute.points.last);
    expect(() => sampleRouteAlternatives.add(alt), throwsUnsupportedError);
  });

  test('the red lights are on the route', () {
    for (final d in sampleRouteRedLights) {
      expect(d, inExclusiveRange(0, sampleRoute.length));
    }
  });
}
