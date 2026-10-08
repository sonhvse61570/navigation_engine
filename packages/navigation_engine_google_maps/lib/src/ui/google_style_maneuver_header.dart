import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_lane_guidance.dart';
import 'google_style_strings.dart';

/// The green turn card at the top of the navigation screen: the next
/// manoeuvre, the distance to it, the road, the lanes and, when it follows
/// closely, the manoeuvre after it.
class GoogleStyleManeuverHeader extends StatelessWidget {
  /// Creates the turn card for [state].
  const GoogleStyleManeuverHeader({
    super.key,
    required this.state,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const GoogleStyleStrings(),
    this.colors = GoogleStyleColors.day,
  });

  /// What to show.
  final GuidanceState state;

  /// Formats the distance and the instruction.
  final GuidanceFormatter formatter;

  /// The words of the card.
  final GoogleStyleStrings strings;

  /// The colours of the card.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    final step = state.step;
    final thenStep = state.thenStep;
    final on = colors.onGuidance;
    final roadName = step == null
        ? strings.arrived
        : step.roadName.isNotEmpty
        ? step.roadName
        : formatter.instruction(step);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: colors.guidance,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(maneuverIcon(step), size: 48, color: on),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Large text scales stop at 1.6 here, so the
                              // distance stays readable on a narrow phone.
                              MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: MediaQuery.textScalerOf(context)
                                      .clamp(maxScaleFactor: 1.6),
                                ),
                                child: Text(
                                  formatter.distance(state.distanceToStep),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: on,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                roadName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: on,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (step != null && step.lanes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: on.withValues(alpha: 0.24),
                      ),
                      const SizedBox(height: 8),
                      GoogleStyleLaneGuidance(lanes: step.lanes, color: on),
                    ],
                  ],
                ),
              ),
              if (thenStep != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.guidanceSecondary,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            strings.then,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: on, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(maneuverIcon(thenStep), size: 20, color: on),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
