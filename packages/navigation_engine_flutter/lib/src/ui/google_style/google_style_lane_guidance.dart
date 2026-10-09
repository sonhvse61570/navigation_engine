import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../lane_guidance_row.dart';

/// A row of lane arrows before a manoeuvre. A valid lane shows its active
/// arrow at full colour; an invalid lane shows all its arrows dimmed. It is
/// the shared [LaneGuidanceRow] (the same look in every style), with a
/// white default colour.
class GoogleStyleLaneGuidance extends StatelessWidget {
  /// Creates the lane arrows for [lanes], left to right.
  const GoogleStyleLaneGuidance({
    super.key,
    required this.lanes,
    this.color = const Color(0xFFFFFFFF),
  });

  /// The lanes before the manoeuvre, left to right.
  final List<Lane> lanes;

  /// The arrow colour.
  final Color color;

  @override
  Widget build(BuildContext context) =>
      LaneGuidanceRow(lanes: lanes, color: color);
}
