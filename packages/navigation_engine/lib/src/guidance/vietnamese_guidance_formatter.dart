import '../route/maneuver.dart';
import '../route/route_step.dart';
import 'guidance_announcement.dart';
import 'guidance_formatter.dart';

/// Vietnamese guidance: "Sau 200 m, rẽ phải vào Lý Tự Trọng, rồi rẽ trái".
class VietnameseGuidanceFormatter extends GuidanceFormatter {
  const VietnameseGuidanceFormatter();

  @override
  String instruction(RouteStep step) {
    final road = step.roadName;
    final onto = road.isEmpty ? '' : ' vào $road';
    final dir = _direction(step.modifier);
    switch (step.type) {
      case ManeuverType.arrive:
        return 'Đến nơi';
      case ManeuverType.depart:
        return road.isEmpty ? 'Xuất phát' : 'Xuất phát trên $road';
      case ManeuverType.newName:
        return 'Đi tiếp$onto';
      case ManeuverType.roundabout:
        return 'Vào vòng xoay';
      case ManeuverType.exitRoundabout:
        return 'Ra khỏi vòng xoay$onto';
      case ManeuverType.fork:
        final side = step.modifier.isLeft ? 'bên trái' : 'bên phải';
        return 'Đi theo nhánh $side$onto';
      case ManeuverType.merge:
        return 'Nhập làn$onto';
      case ManeuverType.onRamp:
        return 'Vào đường dẫn$onto';
      case ManeuverType.offRamp:
        return 'Ra khỏi đường dẫn$onto';
      case ManeuverType.endOfRoad:
        return 'Cuối đường, $dir$onto';
      case ManeuverType.turn:
      case ManeuverType.continueOn:
        return capitalizeFirst('$dir$onto');
    }
  }

  @override
  String announcement(GuidanceAnnouncement a) {
    final step = a.step;
    if (a.kind == AnnouncementKind.arrived || step == null) {
      return 'Bạn đã đến nơi';
    }
    final what = instruction(step);
    final head = a.kind == AnnouncementKind.now
        ? what
        : 'Sau ${distance(a.distance)}, ${lowerFirst(what)}';
    final then = a.thenStep;
    if (then == null || then.isArrival) return head;
    return '$head, rồi ${lowerFirst(instruction(then))}';
  }

  @override
  String distance(double metres) {
    final m = roundedMetres(metres);
    // 980 m rounds to 1000 m: say "1,0 km", as for 1000 m itself.
    if (m < 1000) return '$m m';
    return '${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  @override
  String duration(Duration d) {
    final (:seconds, :hours, :minutes) = splitDuration(d);
    if (seconds != null) return '$seconds giây';
    if (hours == 0) return '$minutes phút';
    return minutes == 0 ? '$hours giờ' : '$hours giờ $minutes phút';
  }

  static String _direction(ManeuverModifier m) => switch (m) {
    ManeuverModifier.left => 'rẽ trái',
    ManeuverModifier.right => 'rẽ phải',
    ManeuverModifier.slightLeft => 'chếch trái',
    ManeuverModifier.slightRight => 'chếch phải',
    ManeuverModifier.sharpLeft => 'quẹo gắt trái',
    ManeuverModifier.sharpRight => 'quẹo gắt phải',
    ManeuverModifier.uturn => 'quay đầu',
    ManeuverModifier.straight || ManeuverModifier.none => 'đi thẳng',
  };
}
