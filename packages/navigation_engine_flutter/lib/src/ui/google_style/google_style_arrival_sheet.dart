import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../flow/place_label.dart';
import '../navigation_strings.dart';
import 'google_style_colors.dart';
import 'last_road.dart';

/// The bottom sheet on arrival.
///
/// - It shows [destination]'s name and address, else the route's last named
///   road, else [NavigationStrings.arrived].
/// - Under it is a full-width [NavigationStrings.done] button that calls
///   [onDone].
///
/// The key `google_style_arrival_done` (on the button) is a stable test
/// hook.
class GoogleStyleArrivalSheet extends StatelessWidget {
  /// Creates the arrival sheet for [route].
  const GoogleStyleArrivalSheet({
    super.key,
    required this.route,
    this.destination,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.onDone,
    this.floating = false,
  });

  /// The route that was driven.
  final NavRoute route;

  /// Whether the sheet floats as a card (in a landscape side panel): all
  /// four corners rounded alike. When false (the default) it is a bottom
  /// sheet reaching the screen's bottom edge, rounded at the top only.
  final bool floating;

  /// The destination's label, when known.
  final PlaceLabel? destination;

  /// The words of the sheet.
  final NavigationStrings strings;

  /// The colours of the sheet.
  final GoogleStyleColors colors;

  /// Called by the done button.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final lastRoad = lastRoadName(route);
    final name = destination?.name;
    final title = name != null && name.trim().isNotEmpty
        ? name
        : lastRoad ?? strings.arrived;
    final address = destination?.address;
    return Material(
      color: colors.surface,
      elevation: 8,
      borderRadius: floating
          ? BorderRadius.circular(24)
          : const BorderRadius.vertical(top: Radius.circular(24)),
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
                  Icon(Icons.place, color: colors.warning, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (address != null && address.isNotEmpty)
                          Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('google_style_arrival_done'),
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  minimumSize: const Size.fromHeight(48),
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
