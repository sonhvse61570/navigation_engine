import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_strings.dart';

/// The bottom card of the navigation screen: the time left, the distance and
/// the arrival time, and the end, steps and overview buttons.
class GoogleStyleTripFooter extends StatelessWidget {
  /// Creates the footer for [progress].
  const GoogleStyleTripFooter({
    super.key,
    required this.progress,
    this.rerouting = false,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const GoogleStyleStrings(),
    this.colors = GoogleStyleColors.day,
    this.onEnd,
    this.onSteps,
    this.onOverview,
  });

  /// What to show.
  final TripProgress progress;

  /// Whether a new route is being looked for; shown instead of the distance
  /// and the arrival time.
  final bool rerouting;

  /// Formats the duration, the distance and the arrival time.
  final GuidanceFormatter formatter;

  /// The words of the footer.
  final GoogleStyleStrings strings;

  /// The colours of the footer.
  final GoogleStyleColors colors;

  /// Called when the end button is pressed; the button is hidden when null.
  final VoidCallback? onEnd;

  /// Called when the steps button is pressed; the button is hidden when null.
  final VoidCallback? onSteps;

  /// Called when the overview button is pressed; the button is hidden when
  /// null.
  final VoidCallback? onOverview;

  @override
  Widget build(BuildContext context) {
    final secondLine = rerouting
        ? Text(
            strings.rerouting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.warning, fontSize: 15),
          )
        : Text(
            '${formatter.distance(progress.remainingDistance)}'
            ' · ${formatter.clockTime(progress.eta)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 15),
          );

    return Material(
      color: colors.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (onEnd != null)
                IconButton.filledTonal(
                  onPressed: onEnd,
                  icon: const Icon(Icons.close),
                  tooltip: strings.exitNavigation,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Large text scales stop at 1.6 here, so the time
                      // left fits beside the buttons on a narrow phone.
                      MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.6),
                        ),
                        child: Text(
                          formatter.duration(progress.remainingDuration),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.etaText,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      secondLine,
                    ],
                  ),
                ),
              ),
              if (onSteps != null)
                IconButton(
                  onPressed: onSteps,
                  icon: const Icon(Icons.format_list_bulleted),
                  color: colors.onSurfaceVariant,
                  tooltip: strings.steps,
                ),
              if (onOverview != null)
                IconButton(
                  onPressed: onOverview,
                  icon: const Icon(Icons.alt_route),
                  color: colors.onSurfaceVariant,
                  tooltip: strings.overview,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
