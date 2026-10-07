import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

RouteStep step(
  ManeuverType type, [
  ManeuverModifier modifier = ManeuverModifier.none,
  String road = 'Le Lai',
]) => RouteStep(distance: 0, type: type, modifier: modifier, roadName: road);

GuidanceAnnouncement say(
  RouteStep? s,
  AnnouncementKind kind, {
  double distance = 0,
  RouteStep? then,
}) => GuidanceAnnouncement(
  stepIndex: 0,
  step: s,
  kind: kind,
  threshold: kind == AnnouncementKind.approaching ? 200 : 0,
  distance: distance,
  thenStep: then,
);

void main() {
  group('EnglishGuidanceFormatter', () {
    const f = EnglishGuidanceFormatter();
    const m = ManeuverModifier.values;

    test('instructions', () {
      expect(
        f.instruction(step(ManeuverType.turn, ManeuverModifier.right)),
        'Turn right onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.turn, ManeuverModifier.slightLeft, '')),
        'Bear left',
      );
      expect(
        f.instruction(step(ManeuverType.turn, ManeuverModifier.sharpRight)),
        'Turn sharp right onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.continueOn, ManeuverModifier.uturn)),
        'Make a U-turn onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.turn, ManeuverModifier.straight)),
        'Continue straight onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.endOfRoad, ManeuverModifier.right)),
        'At the end of the road, turn right onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.fork, ManeuverModifier.slightRight)),
        'Keep right at the fork onto Le Lai',
      );
      expect(f.instruction(step(ManeuverType.newName)), 'Continue onto Le Lai');
      expect(
        f.instruction(step(ManeuverType.roundabout)),
        'Enter the roundabout',
      );
      expect(
        f.instruction(step(ManeuverType.exitRoundabout)),
        'Exit the roundabout onto Le Lai',
      );
      expect(f.instruction(step(ManeuverType.merge)), 'Merge onto Le Lai');
      expect(
        f.instruction(step(ManeuverType.onRamp)),
        'Take the ramp onto Le Lai',
      );
      expect(
        f.instruction(step(ManeuverType.offRamp)),
        'Take the exit onto Le Lai',
      );
      expect(f.instruction(step(ManeuverType.depart)), 'Head out on Le Lai');
      expect(
        f.instruction(step(ManeuverType.depart, ManeuverModifier.none, '')),
        'Head out',
      );
      expect(
        f.instruction(step(ManeuverType.arrive)),
        'Arrive at your destination',
      );
      // Every combination produces a non-empty, capitalised instruction.
      for (final t in ManeuverType.values) {
        for (final mod in m) {
          final text = f.instruction(step(t, mod));
          expect(text, isNotEmpty);
          expect(text[0], text[0].toUpperCase());
        }
      }
    });

    test('announcements', () {
      final right = step(ManeuverType.turn, ManeuverModifier.right, 'A');
      final left = step(ManeuverType.turn, ManeuverModifier.left, '');
      expect(
        f.announcement(say(right, AnnouncementKind.approaching, distance: 212)),
        'In 200 m, turn right onto A',
      );
      expect(
        f.announcement(say(right, AnnouncementKind.now, then: left)),
        'Turn right onto A, then turn left',
      );
      expect(
        f.announcement(
          say(right, AnnouncementKind.now, then: step(ManeuverType.arrive)),
        ),
        'Turn right onto A',
      );
      expect(
        f.announcement(
          say(step(ManeuverType.arrive), AnnouncementKind.arrived),
        ),
        'You have arrived at your destination',
      );
      expect(
        f.announcement(say(null, AnnouncementKind.arrived)),
        'You have arrived at your destination',
      );
    });

    test('distances', () {
      expect(f.distance(4), '10 m');
      expect(f.distance(87), '90 m');
      expect(f.distance(463), '450 m');
      expect(f.distance(1234), '1.2 km');
      // Rounds to 1000 m: shown as km, like 1000 m itself.
      expect(f.distance(974), '950 m');
      expect(f.distance(980), '1.0 km');
      expect(f.distance(999.9), '1.0 km');
      expect(f.distance(1000), '1.0 km');
    });
  });

  group('VietnameseGuidanceFormatter', () {
    const f = VietnameseGuidanceFormatter();

    test('instructions', () {
      String t(
        ManeuverType type,
        ManeuverModifier mod, [
        String name = 'Lê Lai',
      ]) => f.instruction(step(type, mod, name));
      expect(
        t(ManeuverType.turn, ManeuverModifier.right),
        'Rẽ phải vào Lê Lai',
      );
      expect(
        t(ManeuverType.turn, ManeuverModifier.slightLeft, ''),
        'Chếch trái',
      );
      expect(
        t(ManeuverType.continueOn, ManeuverModifier.uturn),
        'Quay đầu vào Lê Lai',
      );
      expect(
        t(ManeuverType.endOfRoad, ManeuverModifier.right),
        'Cuối đường, rẽ phải vào Lê Lai',
      );
      expect(
        t(ManeuverType.fork, ManeuverModifier.slightRight),
        'Đi theo nhánh bên phải vào Lê Lai',
      );
      expect(
        t(ManeuverType.newName, ManeuverModifier.straight),
        'Đi tiếp vào Lê Lai',
      );
      expect(t(ManeuverType.arrive, ManeuverModifier.straight), 'Đến nơi');
    });

    test('announcements', () {
      final right = step(ManeuverType.turn, ManeuverModifier.right, 'A');
      final left = step(ManeuverType.turn, ManeuverModifier.left, '');
      expect(
        f.announcement(say(right, AnnouncementKind.approaching, distance: 212)),
        'Sau 200 m, rẽ phải vào A',
      );
      expect(
        f.announcement(say(right, AnnouncementKind.now, then: left)),
        'Rẽ phải vào A, rồi rẽ trái',
      );
      expect(
        f.announcement(say(null, AnnouncementKind.arrived)),
        'Bạn đã đến nơi',
      );
    });

    test('distances', () {
      expect(f.distance(4), '10 m');
      expect(f.distance(87), '90 m');
      expect(f.distance(463), '450 m');
      expect(f.distance(1234), '1,2 km');
      expect(f.distance(974), '950 m');
      expect(f.distance(980), '1,0 km');
      expect(f.distance(999.9), '1,0 km');
      expect(f.distance(1000), '1,0 km');
    });
  });

  group('durations, clock times and speeds', () {
    test('English', () {
      const f = EnglishGuidanceFormatter();
      expect(f.duration(const Duration(seconds: 45)), '45 s');
      expect(f.duration(const Duration(minutes: 12, seconds: 20)), '12 min');
      expect(f.duration(const Duration(minutes: 59, seconds: 40)), '1 h');
      expect(f.duration(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
      expect(f.duration(const Duration(seconds: -3)), '0 s');
      expect(f.clockTime(DateTime(2026, 10, 7, 9, 5)), '09:05');
      expect(f.speed(11.7), '42 km/h');
    });

    test('Vietnamese', () {
      const f = VietnameseGuidanceFormatter();
      expect(f.duration(const Duration(seconds: 45)), '45 giây');
      expect(f.duration(const Duration(minutes: 12)), '12 phút');
      expect(f.duration(const Duration(hours: 1)), '1 giờ');
      expect(f.duration(const Duration(hours: 1, minutes: 5)), '1 giờ 5 phút');
      expect(f.clockTime(DateTime(2026, 10, 7, 14, 35)), '14:35');
      expect(f.speed(11.7), '42 km/h');
    });

    test('a custom formatter inherits the defaults', () {
      expect(const _Minimal().duration(const Duration(minutes: 3)), '3 min');
    });

    test('splitDuration is exported for third-party formatters', () {
      expect(splitDuration(const Duration(seconds: 45)), (
        seconds: 45,
        hours: 0,
        minutes: 0,
      ));
      expect(splitDuration(const Duration(hours: 1, minutes: 4, seconds: 40)), (
        seconds: null,
        hours: 1,
        minutes: 5,
      ));
    });
  });
}

class _Minimal extends GuidanceFormatter {
  const _Minimal();
  @override
  String instruction(RouteStep step) => '';
  @override
  String announcement(GuidanceAnnouncement a) => '';
  @override
  String distance(double metres) => '';
}
