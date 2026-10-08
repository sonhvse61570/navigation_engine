import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// The Material icon for a lane arrow.
IconData laneDirectionIcon(LaneDirection d) => switch (d) {
  LaneDirection.straight => Icons.straight,
  LaneDirection.slightLeft => Icons.turn_slight_left,
  LaneDirection.left => Icons.turn_left,
  LaneDirection.sharpLeft => Icons.turn_sharp_left,
  LaneDirection.uturn => Icons.u_turn_left,
  LaneDirection.slightRight => Icons.turn_slight_right,
  LaneDirection.right => Icons.turn_right,
  LaneDirection.sharpRight => Icons.turn_sharp_right,
};
