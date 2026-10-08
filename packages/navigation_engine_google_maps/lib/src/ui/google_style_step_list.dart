import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';

/// The list of the steps of a route, each with the distance and the time to
/// the next one.
class GoogleStyleStepList extends StatelessWidget {
  /// Creates the step list of [route].
  const GoogleStyleStepList({
    super.key,
    required this.route,
    this.currentStep = -1,
    this.formatter = const EnglishGuidanceFormatter(),
    this.colors = GoogleStyleColors.day,
  });

  /// The route whose steps are listed.
  final NavRoute route;

  /// The index of the step being driven; the steps before it are dimmed.
  /// Negative when the trip has not started.
  final int currentStep;

  /// Formats the instructions, the distances and the durations.
  final GuidanceFormatter formatter;

  /// The colours of the list.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    final steps = route.steps;
    return Material(
      color: colors.surface,
      child: ListView.separated(
        itemCount: steps.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colors.alternative.withValues(alpha: 0.4),
        ),
        itemBuilder: (context, i) {
          final step = steps[i];
          final nextDistance = i + 1 < steps.length
              ? steps[i + 1].distance
              : route.length;
          final seconds =
              route.durationAt(nextDistance) - route.durationAt(step.distance);
          final tile = ListTile(
            leading: Icon(maneuverIcon(step), color: colors.onSurface),
            title: Text(
              formatter.instruction(step),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurface, fontSize: 16),
            ),
            subtitle: Text(
              '${formatter.distance(nextDistance - step.distance)}'
              ' · ${formatter.duration(Duration(seconds: seconds.round()))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
            ),
          );
          return i < currentStep ? Opacity(opacity: 0.45, child: tile) : tile;
        },
      ),
    );
  }
}
