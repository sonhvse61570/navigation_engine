import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// A Material icon for [step] (a plain arrow when null).
IconData maneuverIcon(RouteStep? step) {
  if (step == null) return Icons.navigation;
  switch (step.type) {
    case ManeuverType.arrive:
      return Icons.flag;
    case ManeuverType.roundabout || ManeuverType.exitRoundabout:
      return step.modifier.isLeft
          ? Icons.roundabout_left
          : Icons.roundabout_right;
    case ManeuverType.fork:
      return step.modifier.isLeft ? Icons.fork_left : Icons.fork_right;
    case ManeuverType.merge:
      return Icons.merge;
    case ManeuverType.onRamp || ManeuverType.offRamp:
      return step.modifier.isLeft ? Icons.ramp_left : Icons.ramp_right;
    default:
      break;
  }
  return switch (step.modifier) {
    ManeuverModifier.left => Icons.turn_left,
    ManeuverModifier.right => Icons.turn_right,
    ManeuverModifier.slightLeft => Icons.turn_slight_left,
    ManeuverModifier.slightRight => Icons.turn_slight_right,
    ManeuverModifier.sharpLeft => Icons.turn_sharp_left,
    ManeuverModifier.sharpRight => Icons.turn_sharp_right,
    ManeuverModifier.uturn => Icons.u_turn_left,
    ManeuverModifier.straight || ManeuverModifier.none => Icons.straight,
  };
}
