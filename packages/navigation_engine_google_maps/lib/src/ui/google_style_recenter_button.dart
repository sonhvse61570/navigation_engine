import 'package:flutter/material.dart';

import 'google_style_colors.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// The pill that brings the camera back to the vehicle after the driver has
/// moved the map.
class GoogleStyleRecenterButton extends StatelessWidget {
  /// Creates the re-center button.
  const GoogleStyleRecenterButton({
    super.key,
    required this.onPressed,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
  });

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// The words of the button.
  final NavigationStrings strings;

  /// The colours of the button.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.navigation),
      label: Text(strings.recenter),
      style: FilledButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.accent,
        elevation: 4,
        shape: const StadiumBorder(),
      ),
    );
  }
}
