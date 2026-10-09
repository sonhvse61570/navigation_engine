import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'google_style_colors.dart';

/// The height of the bar where the height it is given is unbounded.
const double _unboundedHeight = 120;

/// A vertical bar showing how much of the trip is driven: a 12 dp capsule
/// with the driven part in [GoogleStyleColors.progressDriven] from the
/// bottom and the rest in [GoogleStyleColors.accent], a white dot with an
/// accent ring at the vehicle, and a dot at the top for the destination. It
/// fills the height it is given, or is 120 high where the height is
/// unbounded (in a column or a scroll view). The dot is wider than the bar
/// and travels inside its length: flush with the bottom at 0 and with the
/// top at 1.
class GoogleStyleTripProgressBar extends StatelessWidget {
  /// Creates a bar filled to [fraction].
  const GoogleStyleTripProgressBar({
    super.key,
    required this.fraction,
    this.colors = GoogleStyleColors.day,
    this.width = 12,
  });

  /// The share of the trip driven, 0 to 1; values outside are clamped.
  final double fraction;

  /// The colours of the bar.
  final GoogleStyleColors colors;

  /// The width of the bar.
  final double width;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final dot = width + 6;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : _unboundedHeight;
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(width / 2),
                  child: DecoratedBox(
                    key: const ValueKey('google_style_trip_progress_track'),
                    decoration: BoxDecoration(color: colors.accent),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: f,
                        widthFactor: 1,
                        child: DecoratedBox(
                          key: const ValueKey(
                            'google_style_trip_progress_fill',
                          ),
                          decoration: BoxDecoration(
                            color: colors.progressDriven,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: width,
                height: width,
                child: DecoratedBox(
                  key: const ValueKey('google_style_trip_progress_destination'),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFFFFF),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (width - dot) / 2,
                // Inside the bar's length: no overhang at 0 or 1.
                bottom: f * math.max(0, height - dot),
                width: dot,
                height: dot,
                child: DecoratedBox(
                  key: const ValueKey('google_style_trip_progress_dot'),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.accent, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
