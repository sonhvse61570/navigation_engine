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

  group('"Then" rule', () {
    const a = GeoPoint(10.77, 106.69);

    /// A straight line east with a vertex at each of [at] (metres) and the
    /// end at [length]; `steps[i]` sits at `at[i]`.
    NavRoute line(
      List<double> at,
      List<(ManeuverType, ManeuverModifier, String)> steps, {
      required double length,
    }) => NavRoute.fromPoints(
      [for (final d in at) offsetPoint(a, 90, d), offsetPoint(a, 90, length)],
      steps: [
        for (var i = 0; i < steps.length; i++)
          RouteStepSeed.atVertex(
            i,
            type: steps[i].$1,
            modifier: steps[i].$2,
            roadName: steps[i].$3,
          ),
      ],
    );

    const none = ManeuverModifier.none;
    const straight = ManeuverModifier.straight;

    test('the default is 300 m', () {
      expect(NavGuidance(sampleRoute).thenWithin, 300);
    });

    test('(a) a straight-on step shows a turn 1.2 km away', () {
      for (final (type, modifier) in [
        (ManeuverType.continueOn, none),
        (ManeuverType.continueOn, straight),
        (ManeuverType.newName, none),
        (ManeuverType.turn, none),
      ]) {
        final r = line(
          [0, 300, 1500, 2000],
          [
            (ManeuverType.depart, none, 'A'),
            (type, modifier, 'B'),
            (ManeuverType.turn, ManeuverModifier.right, 'C'),
            (ManeuverType.arrive, none, ''),
          ],
          length: 2000,
        );
        final state = NavGuidance(r).update(100).state;
        expect(state.stepIndex, 1, reason: '$type $modifier');
        expect(state.thenStep, same(r.steps[2]), reason: '$type $modifier');
      }
    });

    test('(a) does not apply to a real turn far from the next one', () {
      final r = line(
        [0, 300, 1500, 2000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.continueOn, ManeuverModifier.left, 'B'),
          (ManeuverType.turn, ManeuverModifier.right, 'C'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 2000,
      );
      expect(NavGuidance(r).update(100).state.thenStep, isNull);
    });

    test('(a) skips silent and straight-on steps to the next manoeuvre', () {
      final r = line(
        [0, 300, 900, 1500, 2100, 2600, 3000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.newName, none, 'B'),
          (ManeuverType.continueOn, straight, 'C'),
          (ManeuverType.newName, none, 'D'),
          (ManeuverType.continueOn, none, 'E'),
          (ManeuverType.turn, ManeuverModifier.left, 'F'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 3000,
      );
      final g = NavGuidance(r);
      expect(g.update(100).state.thenStep, same(r.steps[5]));
      expect(g.update(1000).state.thenStep, same(r.steps[5]));
    });

    test('(a) shows the arrival when no manoeuvre is left', () {
      final r = line(
        [0, 300, 900, 1500],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.newName, none, 'B'),
          (ManeuverType.continueOn, straight, 'C'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 1500,
      );
      final state = NavGuidance(r).update(100).state;
      expect(state.stepIndex, 1);
      expect(state.thenStep, same(r.steps[3]));
      expect(state.thenStep!.isArrival, isTrue);
    });

    test('(a) without a manoeuvre or an arrival left shows none', () {
      final r = line(
        [0, 300],
        [(ManeuverType.depart, none, 'A'), (ManeuverType.newName, none, 'B')],
        length: 1500,
      );
      final state = NavGuidance(r).update(100).state;
      expect(state.stepIndex, 1);
      expect(state.thenStep, isNull);
    });

    for (final type in [
      ManeuverType.roundabout,
      ManeuverType.exitRoundabout,
      ManeuverType.onRamp,
      ManeuverType.offRamp,
      ManeuverType.fork,
      ManeuverType.merge,
      ManeuverType.endOfRoad,
    ]) {
      test('(a) never skips a ${type.name} going straight', () {
        final r = line(
          [0, 300, 900, 1500, 2000],
          [
            (ManeuverType.depart, none, 'A'),
            (ManeuverType.continueOn, none, 'B'),
            (type, straight, 'C'),
            (ManeuverType.turn, ManeuverModifier.right, 'D'),
            (ManeuverType.arrive, none, ''),
          ],
          length: 2000,
        );
        // 600 m to the straight manoeuvre, 1.2 km to the right turn.
        final state = NavGuidance(r).update(300).state;
        expect(state.stepIndex, 2, reason: 'past the continue');
        final before = NavGuidance(r).update(100).state;
        expect(before.stepIndex, 1);
        expect(before.thenStep, same(r.steps[2]), reason: type.name);
      });

      test('(a) a ${type.name} going straight is no trigger', () {
        final r = line(
          [0, 300, 1500, 2000],
          [
            (ManeuverType.depart, none, 'A'),
            (type, straight, 'B'),
            (ManeuverType.turn, ManeuverModifier.right, 'C'),
            (ManeuverType.arrive, none, ''),
          ],
          length: 2000,
        );
        final state = NavGuidance(r).update(100).state;
        expect(state.stepIndex, 1);
        expect(state.thenStep, isNull, reason: '1.2 km on, no rule');
      });
    }

    test('(b) skips straight-on steps within 300 m, never past it', () {
      // A turn, a name change 200 m later, a left turn 280 m after the
      // turn: the left turn shows.
      final withTurn = line(
        [0, 500, 700, 780, 2000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.turn, ManeuverModifier.right, 'B'),
          (ManeuverType.newName, straight, 'C'),
          (ManeuverType.turn, ManeuverModifier.left, 'D'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 2000,
      );
      final shown = NavGuidance(withTurn).update(100);
      expect(shown.state.thenStep, same(withTurn.steps[3]));
      // Speech is unchanged: the step right after, within 100 m only.
      expect(shown.announcements.single.thenStep, isNull);

      // Only the name change within 300 m: no "Then continue straight".
      final alone = line(
        [0, 500, 700, 1500, 2000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.turn, ManeuverModifier.right, 'B'),
          (ManeuverType.newName, straight, 'C'),
          (ManeuverType.turn, ManeuverModifier.left, 'D'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 2000,
      );
      expect(NavGuidance(alone).update(100).state.thenStep, isNull);
    });

    NavRoute twoTurns(double gap) => line(
      [0, 500, 500 + gap, 2000],
      [
        (ManeuverType.depart, none, 'A'),
        (ManeuverType.turn, ManeuverModifier.right, 'B'),
        (ManeuverType.turn, ManeuverModifier.left, 'C'),
        (ManeuverType.arrive, none, ''),
      ],
      length: 2000,
    );

    test('(b) a turn 250 m after a turn shows, 350 m does not', () {
      final near = twoTurns(250);
      final shown = NavGuidance(near).update(100);
      expect(shown.state.thenStep, same(near.steps[2]));
      // Shown, but too far to be spoken (spokenThenWithin, 100 m).
      expect(shown.announcements.single.thenStep, isNull);

      final far = twoTurns(350);
      final hidden = NavGuidance(far).update(100);
      expect(hidden.state.thenStep, isNull);
      expect(hidden.announcements.single.thenStep, isNull);
    });

    test('speech: "then" within spokenThenWithin (100 m) only', () {
      expect(NavGuidance(sampleRoute).spokenThenWithin, 100);
      const f = EnglishGuidanceFormatter();

      final close = twoTurns(90);
      final spoken = NavGuidance(close).update(100);
      expect(spoken.state.thenStep, same(close.steps[2]));
      expect(spoken.announcements.single.thenStep, same(close.steps[2]));
      expect(
        f.announcement(spoken.announcements.single),
        'In 400 m, turn right onto B, then turn left onto C',
      );

      final far = twoTurns(250);
      final quiet = NavGuidance(far).update(100);
      expect(quiet.state.thenStep, same(far.steps[2]), reason: 'shown');
      expect(quiet.announcements.single.thenStep, isNull);
      expect(
        f.announcement(quiet.announcements.single),
        'In 400 m, turn right onto B',
      );

      // Configurable.
      final loud = NavGuidance(far, spokenThenWithin: 300).update(100);
      expect(loud.announcements.single.thenStep, same(far.steps[2]));
    });

    test('(b) thenWithin stays configurable', () {
      final near = twoTurns(250);
      final update = NavGuidance(near, thenWithin: 100).update(100);
      expect(update.state.thenStep, isNull);
      expect(update.announcements.single.thenStep, isNull);
      expect(
        NavGuidance(twoTurns(350), thenWithin: 400).update(100).state.thenStep,
        isNotNull,
      );
    });

    test('(a) is shown, never spoken: speech reads as before', () {
      // A spoken straight-on step (a continue without a modifier) whose
      // next turn is 1.2 km away.
      final r = line(
        [0, 300, 1500, 2000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.continueOn, none, 'B'),
          (ManeuverType.turn, ManeuverModifier.right, 'C'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 2000,
      );
      final update = NavGuidance(r).update(100);
      expect(update.state.thenStep, same(r.steps[2]));
      final said = update.announcements.single;
      expect(said.thenStep, isNull);
      expect(
        const EnglishGuidanceFormatter().announcement(said),
        'In 200 m, continue straight onto B',
      );
      expect(
        const VietnameseGuidanceFormatter().announcement(said),
        isNot(contains(', rồi ')),
      );
    });

    test('(a) skipping does not change what is spoken under (b)', () {
      // Straight on, then a name change 80 m later: the display skips to
      // the turn, speech keeps the close step as before.
      final r = line(
        [0, 300, 380, 1500, 2000],
        [
          (ManeuverType.depart, none, 'A'),
          (ManeuverType.continueOn, none, 'B'),
          (ManeuverType.newName, none, 'C'),
          (ManeuverType.turn, ManeuverModifier.right, 'D'),
          (ManeuverType.arrive, none, ''),
        ],
        length: 2000,
      );
      final update = NavGuidance(r).update(100);
      expect(update.state.thenStep, same(r.steps[3]));
      expect(update.announcements.single.thenStep, same(r.steps[2]));
    });
  });
}
