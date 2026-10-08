import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_round_button.dart';

/// A round compass button. Its needle points to north on the screen, and a
/// tap switches the camera between heading up and north up.
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

  /// The map's bearing in degrees; the needle turns to `-bearing`, so it
  /// points to north.
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
      // The tooltip is the one accessibility label: what a tap does.
      icon: Transform.rotate(
        key: const ValueKey('google_style_compass_needle'),
        angle: -bearing * math.pi / 180,
        child: CustomPaint(
          size: const Size(24, 24),
          painter: _NeedlePainter(
            north: colors.warning,
            south: colors.alternative,
          ),
        ),
      ),
    );
  }
}

/// A needle: the north half in [north], the south half in [south].
class _NeedlePainter extends CustomPainter {
  const _NeedlePainter({required this.north, required this.south});

  final Color north;
  final Color south;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final halfWidth = size.width * 0.22;
    final halfHeight = size.height / 2;
    canvas
      ..drawPath(
        Path()
          ..moveTo(c.dx, c.dy - halfHeight)
          ..lineTo(c.dx - halfWidth, c.dy)
          ..lineTo(c.dx + halfWidth, c.dy)
          ..close(),
        Paint()..color = north,
      )
      ..drawPath(
        Path()
          ..moveTo(c.dx, c.dy + halfHeight)
          ..lineTo(c.dx - halfWidth, c.dy)
          ..lineTo(c.dx + halfWidth, c.dy)
          ..close(),
        Paint()..color = south,
      );
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.north != north || old.south != south;
}
