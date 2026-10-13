import 'package:navigation_engine/navigation_engine.dart';

// The Routes API v2 `Maneuver` table, apart so that the tests and the live
// check can test values against it. Not exported.

/// Every documented value of the Routes API v2 `Maneuver` enum
/// (`navigationInstruction.maneuver`), with the manoeuvre it maps to.
///
/// - The turns keep their direction; a U-turn either way is
///   [ManeuverModifier.uturn].
/// - `STRAIGHT` keeps going straight on; `NAME_CHANGE` is a
///   [ManeuverType.newName].
/// - `RAMP_*` is an [ManeuverType.onRamp] and `FORK_*` a
///   [ManeuverType.fork], slightly to their side.
/// - `ROUNDABOUT_*` enters a roundabout, turning to its side.
/// - `FERRY`, `FERRY_TRAIN` and `MANEUVER_UNSPECIFIED` ("not used") keep
///   going.
/// - `DEPART` departs and `DESTINATION` arrives (the provider places the
///   arrival at the last point itself).
const Map<String, (ManeuverType, ManeuverModifier)> googleManeuvers = {
  'MANEUVER_UNSPECIFIED': (ManeuverType.continueOn, ManeuverModifier.none),
  'TURN_SLIGHT_LEFT': (ManeuverType.turn, ManeuverModifier.slightLeft),
  'TURN_SHARP_LEFT': (ManeuverType.turn, ManeuverModifier.sharpLeft),
  'UTURN_LEFT': (ManeuverType.turn, ManeuverModifier.uturn),
  'TURN_LEFT': (ManeuverType.turn, ManeuverModifier.left),
  'TURN_SLIGHT_RIGHT': (ManeuverType.turn, ManeuverModifier.slightRight),
  'TURN_SHARP_RIGHT': (ManeuverType.turn, ManeuverModifier.sharpRight),
  'UTURN_RIGHT': (ManeuverType.turn, ManeuverModifier.uturn),
  'TURN_RIGHT': (ManeuverType.turn, ManeuverModifier.right),
  'STRAIGHT': (ManeuverType.continueOn, ManeuverModifier.straight),
  'RAMP_LEFT': (ManeuverType.onRamp, ManeuverModifier.slightLeft),
  'RAMP_RIGHT': (ManeuverType.onRamp, ManeuverModifier.slightRight),
  'MERGE': (ManeuverType.merge, ManeuverModifier.none),
  'FORK_LEFT': (ManeuverType.fork, ManeuverModifier.slightLeft),
  'FORK_RIGHT': (ManeuverType.fork, ManeuverModifier.slightRight),
  'FERRY': (ManeuverType.continueOn, ManeuverModifier.none),
  'FERRY_TRAIN': (ManeuverType.continueOn, ManeuverModifier.none),
  'ROUNDABOUT_LEFT': (ManeuverType.roundabout, ManeuverModifier.left),
  'ROUNDABOUT_RIGHT': (ManeuverType.roundabout, ManeuverModifier.right),
  'DEPART': (ManeuverType.depart, ManeuverModifier.none),
  'NAME_CHANGE': (ManeuverType.newName, ManeuverModifier.none),
  'DESTINATION': (ManeuverType.arrive, ManeuverModifier.none),
};

/// The manoeuvre of a Routes v2 `maneuver` value ([googleManeuvers]); none
/// (null) keeps going; null for a value it does not know, exactly as
/// Google spells them (upper case).
(ManeuverType, ManeuverModifier)? googleManeuver(String? value) => value == null
    ? (ManeuverType.continueOn, ManeuverModifier.none)
    : googleManeuvers[value];
