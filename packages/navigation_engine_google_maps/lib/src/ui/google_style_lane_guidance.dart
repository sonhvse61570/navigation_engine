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

/// A row of lane arrows before a manoeuvre. A valid lane shows its active
/// arrow at full colour; an invalid lane shows all its arrows dimmed.
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
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [for (final lane in lanes) _LaneCell(lane: lane, color: color)],
    );
  }
}

class _LaneCell extends StatelessWidget {
  const _LaneCell({required this.lane, required this.color});

  final Lane lane;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Widget arrows;
    if (lane.valid && (lane.active != null || lane.directions.isNotEmpty)) {
      arrows = Icon(
        laneDirectionIcon(lane.active ?? lane.directions.first),
        size: 28,
        color: color,
      );
    } else {
      final dimmed = color.withValues(alpha: 0.4);
      arrows = Stack(
        alignment: Alignment.center,
        children: [
          for (final d in lane.directions)
            Icon(laneDirectionIcon(d), size: 28, color: dimmed),
        ],
      );
    }
    return SizedBox(
      key: const ValueKey('google_style_lane_cell'),
      width: 32,
      height: 36,
      child: Center(child: arrows),
    );
  }
}
