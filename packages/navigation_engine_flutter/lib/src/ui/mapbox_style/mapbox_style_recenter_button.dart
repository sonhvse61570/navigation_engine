import 'package:flutter/material.dart';

import '../navigation_strings.dart';
import 'mapbox_style_colors.dart';

/// The pill that brings the camera back to the vehicle after the driver has
/// moved the map.
class MapboxStyleRecenterButton extends StatelessWidget {
  /// Creates the re-center button.
  const MapboxStyleRecenterButton({
    super.key,
    required this.onPressed,
    this.strings = const NavigationStrings(),
    this.colors = MapboxStyleColors.day,
  });

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// The words of the button.
  final NavigationStrings strings;

  /// The colours of the button.
  final MapboxStyleColors colors;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.navigation),
      label: Text(
        strings.recenter,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        iconColor: colors.accent,
        elevation: 4,
        shape: const StadiumBorder(),
      ),
    );
  }
}
