import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_google_maps/src/routing/maneuvers.dart';

void main() {
  test('every documented Maneuver value is mapped', () {
    // The full enum of the Routes API v2 reference (NavigationInstruction
    // .maneuver), checked on 2026-10-12.
    const expected = <String, (ManeuverType, ManeuverModifier)>{
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
    expect(googleManeuvers.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(key: value, value: mapped) in expected.entries) {
      expect(googleManeuver(value), mapped, reason: value);
    }
  });

  test('none keeps going; an unknown value is null', () {
    expect(googleManeuver(null), (
      ManeuverType.continueOn,
      ManeuverModifier.none,
    ));
    expect(googleManeuver('TURN_SIDEWAYS'), isNull);
    expect(googleManeuver('turn_left'), isNull);
    expect(googleManeuver(''), isNull);
  });
}
