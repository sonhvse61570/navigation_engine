import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  test('laneDirectionIcon maps all 8 directions', () {
    expect(laneDirectionIcon(LaneDirection.straight), Icons.straight);
    expect(laneDirectionIcon(LaneDirection.slightLeft), Icons.turn_slight_left);
    expect(laneDirectionIcon(LaneDirection.left), Icons.turn_left);
    expect(laneDirectionIcon(LaneDirection.sharpLeft), Icons.turn_sharp_left);
    expect(laneDirectionIcon(LaneDirection.uturn), Icons.u_turn_left);
    expect(
      laneDirectionIcon(LaneDirection.slightRight),
      Icons.turn_slight_right,
    );
    expect(laneDirectionIcon(LaneDirection.right), Icons.turn_right);
    expect(laneDirectionIcon(LaneDirection.sharpRight), Icons.turn_sharp_right);
  });
}
