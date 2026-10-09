import 'package:flutter/material.dart';

import 'google_style_colors.dart';

/// A round map button: a [size] circle (52 by default, more than a 48 dp
/// touch target) in [GoogleStyleColors.buttonSurface] with a 1 dp
/// [GoogleStyleColors.outline] ring, elevation 1 and one 24 dp icon in
/// [GoogleStyleColors.buttonIcon], such as the compass, search, sound and
/// route-options buttons.
///
/// [surface], [iconColor] and [elevation] override those defaults, such as
/// for the trip sheet's flat close circle.
class GoogleStyleRoundButton extends StatelessWidget {
  /// Creates a round button showing [icon].
  const GoogleStyleRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.colors = GoogleStyleColors.day,
    this.size = 52,
    this.surface,
    this.iconColor,
    this.elevation = 1,
    this.outline,
  });

  /// What the button shows, usually an [Icon]; it takes the colour of
  /// [iconColor], or [GoogleStyleColors.buttonIcon].
  final Widget icon;

  /// The tooltip, which is also the button's accessibility label.
  final String tooltip;

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// The colours of the button.
  final GoogleStyleColors colors;

  /// The diameter of the button.
  final double size;

  /// The colour of the disc; [GoogleStyleColors.buttonSurface] when null.
  final Color? surface;

  /// The colour of the icon; [GoogleStyleColors.buttonIcon] when null.
  final Color? iconColor;

  /// The elevation of the disc.
  final double elevation;

  /// The colour of the disc's 1 dp ring; [GoogleStyleColors.outline] when
  /// null.
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface ?? colors.buttonSurface,
      elevation: elevation,
      shape: CircleBorder(side: BorderSide(color: outline ?? colors.outline)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          onPressed: onPressed,
          icon: icon,
          tooltip: tooltip,
          color: iconColor ?? colors.buttonIcon,
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
        ),
      ),
    );
  }
}
