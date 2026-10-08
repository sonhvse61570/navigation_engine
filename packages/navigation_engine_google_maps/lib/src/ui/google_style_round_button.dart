import 'package:flutter/material.dart';

import 'google_style_colors.dart';

/// A round map button: a white (or night) disc with a shadow and one icon,
/// such as the compass, sound and report buttons.
class GoogleStyleRoundButton extends StatelessWidget {
  /// Creates a round button showing [icon].
  const GoogleStyleRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.colors = GoogleStyleColors.day,
  });

  /// What the button shows, usually an [Icon]; it takes the colour of
  /// [GoogleStyleColors.onSurfaceVariant].
  final Widget icon;

  /// The tooltip, which is also the button's accessibility label.
  final String tooltip;

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// The colours of the button.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}
