import '../route/maneuver.dart';
import '../route/route_step.dart';
import 'guidance_announcement.dart';
import 'guidance_formatter.dart';

/// English guidance: "In 200 m, turn right onto Main Street, then turn left".
class EnglishGuidanceFormatter extends GuidanceFormatter {
  const EnglishGuidanceFormatter();

  @override
  String instruction(RouteStep step) {
    final road = step.roadName;
    final onto = road.isEmpty ? '' : ' onto $road';
    final dir = _direction(step.modifier);
    switch (step.type) {
      case ManeuverType.arrive:
        return 'Arrive at your destination';
      case ManeuverType.depart:
        return road.isEmpty ? 'Head out' : 'Head out on $road';
      case ManeuverType.newName:
        return 'Continue$onto';
      case ManeuverType.roundabout:
        return 'Enter the roundabout';
      case ManeuverType.exitRoundabout:
        return 'Exit the roundabout$onto';
      case ManeuverType.fork:
        final side = step.modifier.isLeft ? 'left' : 'right';
        return 'Keep $side at the fork$onto';
      case ManeuverType.merge:
        return 'Merge$onto';
      case ManeuverType.onRamp:
        return 'Take the ramp$onto';
      case ManeuverType.offRamp:
        return 'Take the exit$onto';
      case ManeuverType.endOfRoad:
        return 'At the end of the road, $dir$onto';
      case ManeuverType.turn:
      case ManeuverType.continueOn:
        return capitalizeFirst('$dir$onto');
    }
  }

  @override
  String announcement(GuidanceAnnouncement a) {
    final step = a.step;
    if (a.kind == AnnouncementKind.arrived || step == null) {
      return 'You have arrived at your destination';
    }
    final what = instruction(step);
    final head = a.kind == AnnouncementKind.now
        ? what
        : 'In ${distance(a.distance)}, ${lowerFirst(what)}';
    final then = a.thenStep;
    if (then == null || then.isArrival) return head;
    return '$head, then ${lowerFirst(instruction(then))}';
  }

  @override
  String distance(double metres) {
    final m = roundedMetres(metres);
    // 980 m rounds to 1000 m: say "1.0 km", as for 1000 m itself.
    if (m < 1000) return '$m m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  static String _direction(ManeuverModifier m) => switch (m) {
    ManeuverModifier.left => 'turn left',
    ManeuverModifier.right => 'turn right',
    ManeuverModifier.slightLeft => 'bear left',
    ManeuverModifier.slightRight => 'bear right',
    ManeuverModifier.sharpLeft => 'turn sharp left',
    ManeuverModifier.sharpRight => 'turn sharp right',
    ManeuverModifier.uturn => 'make a U-turn',
    ManeuverModifier.straight || ManeuverModifier.none => 'continue straight',
  };
}
