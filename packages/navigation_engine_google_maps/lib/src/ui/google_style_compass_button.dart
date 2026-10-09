import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_round_button.dart';

/// A round compass button: a red triangle over a bold "N", turned so the
/// triangle points to north on the screen. A tap switches the camera
/// between heading up and north up.
class GoogleStyleCompassButton extends StatelessWidget {
  /// Creates a compass for a map turned to [bearing].
  const GoogleStyleCompassButton({
    super.key,
    required this.bearing,
    required this.headingUp,
    required this.onPressed,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
  });

  /// The map's bearing in degrees; the glyph turns to `-bearing`, so its
  /// triangle points to north.
  final double bearing;

  /// Whether the camera turns with the vehicle. The tooltip, which is also
  /// the button's only accessibility label, names what a tap switches to:
  /// [NavigationStrings.northUp] when true, else
  /// [NavigationStrings.headingUp].
  final bool headingUp;

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// The words of the button.
  final NavigationStrings strings;

  /// The colours of the button.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    return GoogleStyleRoundButton(
      tooltip: headingUp ? strings.northUp : strings.headingUp,
      onPressed: onPressed,
      colors: colors,
      // The tooltip is the one accessibility label: what a tap does. The
      // whole glyph turns, the triangle pointing to north.
      icon: Transform.rotate(
        key: const ValueKey('google_style_compass_needle'),
        angle: -bearing * math.pi / 180,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 24,
            height: 32,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomPaint(
                  key: const ValueKey('google_style_compass_north'),
                  size: const Size(10, 12),
                  painter: _TrianglePainter(colors.compassNorth),
                ),
                const SizedBox(height: 1),
                // A glyph, not text: it keeps its size at any text scale.
                Text(
                  'N',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: colors.buttonIcon,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled triangle pointing up, in [color].
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
