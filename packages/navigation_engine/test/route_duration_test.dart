import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  const a = GeoPoint(10.77, 106.69);
  final b = offsetPoint(a, 0, 100);
  final c = offsetPoint(b, 0, 100);

  group('durations', () {
    test('provider durations: total, interpolation, remaining, clamping', () {
      final r = NavRoute.fromPoints([a, b, c], segmentDurations: [10, 20]);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(30, 1e-9));
      expect(r.durationAt(0), 0);
      expect(r.durationAt(50), closeTo(5, 1e-6));
      expect(r.durationAt(150), closeTo(20, 1e-6));
      expect(r.remainingDuration(150), closeTo(10, 1e-6));
      expect(r.durationAt(-10), 0);
      expect(r.durationAt(1e6), closeTo(30, 1e-9));
      expect(r.remainingDuration(1e6), closeTo(0, 1e-9));
    });

    test('estimated from speed limits, else the fallback speed', () {
      final r = NavRoute.fromPoints(
        [a, b, c],
        segmentSpeedLimits: [10, null],
        fallbackSpeed: 5,
      );
      expect(r.hasProviderDurations, isFalse);
      expect(r.durationAt(100), closeTo(10, 1e-3));
      expect(r.duration, closeTo(30, 1e-3));
    });

    test('default fallback is 30 km/h', () {
      final r = NavRoute.fromPoints([a, b]);
      expect(r.duration, closeTo(100 / (30 / 3.6), 1e-3));
    });

    test('zero-length segments take no time', () {
      final r = NavRoute.fromPoints([a, a, b], fallbackSpeed: 10);
      expect(r.duration, closeTo(10, 1e-3));
      expect(r.durationAt(0), 0);
    });
  });

  group('speed limits', () {
    test('per segment, null when unknown or absent', () {
      final r = NavRoute.fromPoints([a, b, c], segmentSpeedLimits: [10, null]);
      expect(r.speedLimitAt(50), 10);
      expect(r.speedLimitAt(150), isNull);
      expect(NavRoute.fromPoints([a, b]).speedLimitAt(50), isNull);
    });
  });

  group('validation', () {
    test('rejects lists of the wrong length', () {
      expect(
        () => NavRoute.fromPoints([a, b, c], segmentDurations: [1]),
        throwsArgumentError,
      );
      expect(
        () => NavRoute.fromPoints([a, b, c], segmentSpeedLimits: [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('rejects negative or non-finite durations', () {
      expect(
        () => NavRoute.fromPoints([a, b], segmentDurations: [-1]),
        throwsArgumentError,
      );
      expect(
        () => NavRoute.fromPoints([a, b], segmentDurations: [double.nan]),
        throwsArgumentError,
      );
    });

    test('rejects non-positive speeds', () {
      expect(
        () => NavRoute.fromPoints([a, b], fallbackSpeed: 0),
        throwsArgumentError,
      );
      expect(
        () => NavRoute.fromPoints([a, b], segmentSpeedLimits: [0]),
        throwsArgumentError,
      );
    });
  });

  group('summary', () {
    test('given summary wins', () {
      expect(
        NavRoute.fromPoints([a, b], summary: 'Main St').summary,
        'Main St',
      );
    });

    test('derived: the named road covering the longest distance', () {
      final d = offsetPoint(c, 0, 100);
      final r = NavRoute.fromPoints(
        [a, b, c, d],
        steps: const [
          RouteStepSeed.atVertex(0, type: ManeuverType.depart, roadName: 'A'),
          RouteStepSeed.atVertex(1, type: ManeuverType.turn, roadName: 'B'),
          RouteStepSeed.atVertex(3, type: ManeuverType.arrive),
        ],
      );
      expect(r.summary, 'B');
    });

    test('empty when no step is named', () {
      expect(NavRoute.fromPoints([a, b]).summary, '');
    });
  });
}
