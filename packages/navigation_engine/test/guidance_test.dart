import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:test/test.dart';

/// Drives [route] from start to end in [step]-metre increments and returns
/// every announcement plus the state seen at each distance.
(List<GuidanceAnnouncement>, List<(double, GuidanceState)>) drive(
  NavRoute route, {
  double step = 1,
}) {
  final g = NavGuidance(route);
  final said = <GuidanceAnnouncement>[];
  final seen = <(double, GuidanceState)>[];
  for (var d = 0.0; d <= route.length + step; d += step) {
    final update = g.update(d);
    said.addAll(update.announcements);
    seen.add((d, update.state));
  }
  return (said, seen);
}

String describe(GuidanceAnnouncement a) =>
    'step ${a.stepIndex} ${a.kind.name} @${a.threshold} '
    '(${a.distance.toStringAsFixed(1)} m)';

void main() {
  final route = sampleRoute;
  final manoeuvres = [
    for (var i = 0; i < route.steps.length; i++)
      if (!isSilentStep(route.steps[i]) && !route.steps[i].isArrival) i,
  ];

  test('every manoeuvre gets exactly one "now" prompt, in route order', () {
    final (said, _) = drive(route);
    final now = said.where((a) => a.threshold == 0 && a.stepIndex >= 0);
    final indices = now.map((a) => a.stepIndex).toList();
    // The arrival prompt is the last "now" one.
    expect(indices.last, route.steps.length - 1);
    expect(indices.sublist(0, indices.length - 1), manoeuvres);
  });

  test('kinds: approaching above 0, now at 0, arrived last', () {
    final (said, _) = drive(route);
    for (final a in said.take(said.length - 1)) {
      expect(
        a.kind,
        a.threshold > 0 ? AnnouncementKind.approaching : AnnouncementKind.now,
        reason: describe(a),
      );
      expect(a.step, same(route.steps[a.stepIndex]));
    }
    expect(said.last.kind, AnnouncementKind.arrived);
  });

  test('"now" fires within 30 m of the manoeuvre, never after it', () {
    final (said, _) = drive(route);
    for (final a in said.where((a) => a.threshold == 0)) {
      expect(a.distance, inInclusiveRange(0, 31), reason: describe(a));
    }
  });

  test('no prompt is repeated and none is stale', () {
    final (said, _) = drive(route);
    final keys = said.map((a) => (a.stepIndex, a.threshold)).toList();
    expect(keys.toSet().length, keys.length);
    // A step that starts 150 m after the previous one must not hear "500 m".
    for (final a in said.where((a) => a.threshold > 0)) {
      expect(a.distance, lessThanOrEqualTo(a.threshold), reason: describe(a));
      expect(
        a.distance,
        greaterThan(a.threshold == 500 ? 200 : 30),
        reason: describe(a),
      );
    }
  });

  test('prompts for one step are at least 80 m apart (no "200 m" twice)', () {
    final (said, _) = drive(route);
    for (var i = 1; i < said.length; i++) {
      final a = said[i - 1], b = said[i];
      if (a.stepIndex != b.stepIndex || b.threshold == 0) continue;
      expect(
        a.distance - b.distance,
        greaterThanOrEqualTo(80),
        reason: '${describe(a)} then ${describe(b)}',
      );
    }
  });

  test('name changes and "go straight" are shown but not spoken', () {
    final (said, seen) = drive(route);
    final silent = [
      for (var i = 0; i < route.steps.length; i++)
        if (isSilentStep(route.steps[i])) i,
    ];
    expect(silent, isNotEmpty);
    expect(said.where((a) => silent.contains(a.stepIndex)), isEmpty);
    final shown = seen.map((s) => s.$2.stepIndex).toSet();
    expect(shown.containsAll(silent.where((i) => i > 0)), isTrue);
  });

  test('the distance counts down along the route, then resets', () {
    final (_, seen) = drive(route);
    for (var i = 1; i < seen.length; i++) {
      final (_, prev) = seen[i - 1];
      final (_, cur) = seen[i];
      if (cur.arrived || prev.arrived) continue;
      if (cur.stepIndex == prev.stepIndex) {
        expect(cur.distanceToStep, lessThan(prev.distanceToStep));
      } else {
        expect(cur.stepIndex, greaterThan(prev.stepIndex));
      }
    }
    expect(seen.last.$2.arrived, isTrue);
  });

  test('big jumps (dropped frames) skip steps without losing the order', () {
    final (said, _) = drive(route, step: 120);
    final steps = said.map((a) => a.stepIndex).toList();
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThanOrEqualTo(steps[i - 1]));
    }
    expect(said.last.kind, AnnouncementKind.arrived);
  });

  test('close manoeuvres are announced together', () {
    // Roundabout, then its exit 30 m later.
    final g = NavGuidance(route);
    final roundabout = route.steps.indexWhere(
      (s) => s.type == ManeuverType.roundabout,
    );
    final update = g.update(route.steps[roundabout].distance - 150);
    expect(update.state.stepIndex, roundabout);
    expect(update.state.thenStep?.type, ManeuverType.exitRoundabout);
    expect(
      update.announcements.single.thenStep?.type,
      ManeuverType.exitRoundabout,
    );
  });

  test('a route without steps still arrives', () {
    const a = GeoPoint(10.77, 106.69);
    final r = NavRoute.fromPoints([a, offsetPoint(a, 90, 300)]);
    final (said, seen) = drive(r);
    expect(said, hasLength(1));
    expect(said.single.kind, AnnouncementKind.arrived);
    expect(said.single.step, isNull);
    expect(said.single.stepIndex, -1);
    expect(seen.last.$2.arrived, isTrue);
    expect(seen.first.$2.step, isNull);
  });

  test('no stale step after the last manoeuvre when there is no arrive', () {
    const a = GeoPoint(10.77, 106.69);
    final r = NavRoute.fromPoints(
      [a, offsetPoint(a, 90, 1000)],
      steps: const [
        RouteStepSeed.atVertex(
          0,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.right,
          roadName: 'B',
        ),
      ],
    );
    final g = NavGuidance(r);
    final mid = g.update(500).state;
    expect(mid.step, isNull);
    expect(mid.stepIndex, -1);
    expect(mid.thenStep, isNull);
    expect(mid.arrived, isFalse);
    expect(mid.distanceToStep, closeTo(r.length - 500, 1e-6));
    expect(mid.remaining, closeTo(r.length - 500, 1e-6));

    final (said, seen) = drive(r);
    expect(seen.last.$2.arrived, isTrue);
    expect(said.where((x) => x.kind == AnnouncementKind.arrived), hasLength(1));
  });

  test('reset starts over', () {
    final g = NavGuidance(route);
    final first = g.update(route.length).announcements;
    expect(first.single.kind, AnnouncementKind.arrived);
    expect(g.update(route.length).announcements, isEmpty);
    g.reset();
    expect(g.update(route.length).announcements, hasLength(1));
  });
}
