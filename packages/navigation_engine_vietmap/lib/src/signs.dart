import 'package:navigation_engine/navigation_engine.dart';

// The `sign` table of route v4, apart so that the live check can test the
// raw codes Vietmap sends against it. Not exported.

/// The manoeuvre of a GraphHopper `sign` code, as route v4 uses them; null
/// for a code it does not know.
(ManeuverType, ManeuverModifier)? vietmapSign(int sign) => switch (sign) {
  -98 || -8 || 8 => (ManeuverType.turn, ManeuverModifier.uturn),
  -7 => (ManeuverType.fork, ManeuverModifier.slightLeft),
  -6 => (ManeuverType.exitRoundabout, ManeuverModifier.none),
  -3 => (ManeuverType.turn, ManeuverModifier.sharpLeft),
  -2 => (ManeuverType.turn, ManeuverModifier.left),
  -1 => (ManeuverType.turn, ManeuverModifier.slightLeft),
  0 => (ManeuverType.continueOn, ManeuverModifier.straight),
  1 => (ManeuverType.turn, ManeuverModifier.slightRight),
  2 => (ManeuverType.turn, ManeuverModifier.right),
  3 => (ManeuverType.turn, ManeuverModifier.sharpRight),
  4 => (ManeuverType.arrive, ManeuverModifier.none),
  // A via point: the provider sends none, so there is nothing to do.
  5 => (ManeuverType.continueOn, ManeuverModifier.none),
  6 => (ManeuverType.roundabout, ManeuverModifier.none),
  7 => (ManeuverType.fork, ManeuverModifier.slightRight),
  _ => null,
};
