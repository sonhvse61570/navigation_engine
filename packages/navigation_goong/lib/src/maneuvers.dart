import 'package:navigation_engine/navigation_engine.dart';

// The `maneuver` table of direction v2, apart so that the live check can
// test the raw values Goong sends against it. Not exported.

/// The manoeuvre of a Google `maneuver` string, or of Goong's own form of
/// it (`left`, `slight right`, without the `turn-` prefix); null for a
/// value it does not know. Case, spaces and underscores do not matter.
/// None (null or empty) keeps going.
(ManeuverType, ManeuverModifier)? goongManeuver(String? raw) {
  final value = (raw ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'[\s_]+'),
    '-',
  );
  return switch (value) {
    '' => (ManeuverType.continueOn, ManeuverModifier.none),
    'turn-left' || 'left' => (ManeuverType.turn, ManeuverModifier.left),
    'turn-right' || 'right' => (ManeuverType.turn, ManeuverModifier.right),
    'turn-slight-left' ||
    'slight-left' => (ManeuverType.turn, ManeuverModifier.slightLeft),
    'turn-slight-right' ||
    'slight-right' => (ManeuverType.turn, ManeuverModifier.slightRight),
    'turn-sharp-left' ||
    'sharp-left' => (ManeuverType.turn, ManeuverModifier.sharpLeft),
    'turn-sharp-right' ||
    'sharp-right' => (ManeuverType.turn, ManeuverModifier.sharpRight),
    'uturn-left' ||
    'uturn-right' ||
    'uturn' => (ManeuverType.turn, ManeuverModifier.uturn),
    'roundabout-left' => (ManeuverType.roundabout, ManeuverModifier.left),
    'roundabout-right' => (ManeuverType.roundabout, ManeuverModifier.right),
    'keep-left' ||
    'fork-left' => (ManeuverType.fork, ManeuverModifier.slightLeft),
    'keep-right' ||
    'fork-right' => (ManeuverType.fork, ManeuverModifier.slightRight),
    'merge' => (ManeuverType.merge, ManeuverModifier.none),
    'ramp-left' => (ManeuverType.onRamp, ManeuverModifier.left),
    'ramp-right' => (ManeuverType.onRamp, ManeuverModifier.right),
    'straight' => (ManeuverType.continueOn, ManeuverModifier.straight),
    'ferry' ||
    'ferry-train' => (ManeuverType.continueOn, ManeuverModifier.none),
    _ => null,
  };
}
