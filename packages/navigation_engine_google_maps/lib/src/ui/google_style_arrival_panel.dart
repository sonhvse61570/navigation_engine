import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'google_style_colors.dart';
import 'google_style_strings.dart';

/// The bottom card shown when the destination is reached: the arrival message,
/// the last road and a done button.
class GoogleStyleArrivalPanel extends StatelessWidget {
  /// Creates the arrival panel for [route].
  const GoogleStyleArrivalPanel({
    super.key,
    required this.route,
    this.strings = const GoogleStyleStrings(),
    this.colors = GoogleStyleColors.day,
    this.onDone,
  });

  /// The route that was driven.
  final NavRoute route;

  /// The words of the panel.
  final GoogleStyleStrings strings;

  /// The colours of the panel.
  final GoogleStyleColors colors;

  /// Called when the done button is pressed.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final lastRoad = route.steps
        .map((step) => step.roadName)
        .where((name) => name.isNotEmpty)
        .lastOrNull;

    return Material(
      color: colors.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, color: colors.guidance, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.arrived,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (lastRoad != null)
                          Text(
                            lastRoad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                ),
                child: Text(strings.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
