import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../maneuver_icon.dart';
import '../lane_guidance_row.dart';
import '../navigation_strings.dart';
import 'mapbox_style_colors.dart';

/// The dark banner at the top of the navigation screen: the next manoeuvre,
/// the distance to it, the road, the lanes and, when it follows closely, the
/// manoeuvre after it.
class MapboxStyleManeuverBanner extends StatelessWidget {
  /// Creates the banner for [state].
  const MapboxStyleManeuverBanner({
    super.key,
    required this.state,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = MapboxStyleColors.day,
  });

  /// What to show.
  final GuidanceState state;

  /// Formats the distance and the instruction.
  final GuidanceFormatter formatter;

  /// The words of the banner.
  final NavigationStrings strings;

  /// The colours of the banner.
  final MapboxStyleColors colors;

  @override
  Widget build(BuildContext context) {
    final step = state.step;
    final thenStep = state.thenStep;
    final on = colors.onBanner;
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
          color: colors.banner,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(maneuverIcon(step), size: 40, color: on),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Large text scales stop at 1.6 here, so the
                              // distance stays readable on a narrow phone.
                              MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.6),
                                ),
                                child: Text(
                                  formatter.distance(state.distanceToStep),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: on,
                                    fontSize: 24,
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (step != null && step.lanes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: on.withValues(alpha: 0.24),
                      ),
                      const SizedBox(height: 6),
                      LaneGuidanceRow(lanes: step.lanes, color: on),
                    ],
                  ],
                ),
              ),
              if (thenStep != null)
                ColoredBox(
                  color: colors.bannerSecondary,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
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
