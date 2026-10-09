import 'package:flutter/material.dart';

import '../navigation_strings.dart';
import 'google_style_colors.dart';

/// The pill that brings the camera back to the vehicle after the driver has
/// moved the map: a white pill (night `#303134`) with the icon and the label
/// in the accent blue.
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
        backgroundColor: colors.buttonSurface,
        foregroundColor: colors.accent,
        elevation: 3,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
      ),
    );
  }
}
