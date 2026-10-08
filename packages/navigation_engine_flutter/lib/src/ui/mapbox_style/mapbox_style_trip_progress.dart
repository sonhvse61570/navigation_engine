import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../flow/trip_progress.dart';
import '../navigation_strings.dart';
import 'mapbox_style_colors.dart';

const _lightIcon = Color(0xFFFFFFFF);

/// The near-black of the night banner.
const _darkIcon = Color(0xFF0F1720);

/// The icon colour on the end button: white or near-black, whichever has
/// the higher contrast against [end] (the palette has no `onEnd` colour).
Color _onEnd(Color end) {
  double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  return ratio(_lightIcon, end) >= ratio(_darkIcon, end)
      ? _lightIcon
      : _darkIcon;
}

/// The bottom panel of the navigation screen: the time left, the distance
/// and the arrival time, and the overview, steps and end buttons.
class MapboxStyleTripProgress extends StatelessWidget {
  /// Creates the panel for [progress].
  const MapboxStyleTripProgress({
    super.key,
    required this.progress,
    this.rerouting = false,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = MapboxStyleColors.day,
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

  /// The words of the panel.
  final NavigationStrings strings;

  /// The colours of the panel.
  final MapboxStyleColors colors;

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
    final outline = BorderSide(color: colors.alternative);

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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Large text scales stop at 1.6 here, so the time
                      // left fits beside the buttons on a narrow phone.
                      MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: MediaQuery.textScalerOf(
                            context,
                          ).clamp(maxScaleFactor: 1.6),
                        ),
                        // The time left shrinks rather than being cut.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            formatter.duration(progress.remainingDuration),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: colors.etaText,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      secondLine,
                    ],
                  ),
                ),
              ),
              if (onOverview != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: IconButton.outlined(
                    onPressed: onOverview,
                    icon: const Icon(Icons.alt_route),
                    color: colors.onSurface,
                    style: IconButton.styleFrom(side: outline),
                    tooltip: strings.overview,
                  ),
                ),
              if (onSteps != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: IconButton.outlined(
                    onPressed: onSteps,
                    icon: const Icon(Icons.format_list_bulleted),
                    color: colors.onSurface,
                    style: IconButton.styleFrom(side: outline),
                    tooltip: strings.steps,
                  ),
                ),
              if (onEnd != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: IconButton.filled(
                    onPressed: onEnd,
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: colors.end,
                      foregroundColor: _onEnd(colors.end),
                      shape: const CircleBorder(),
                    ),
                    tooltip: strings.exitNavigation,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
