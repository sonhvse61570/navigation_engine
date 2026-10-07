import 'dart:ui';

/// How a navigation view draws the route line.
class RouteColors {
  const RouteColors({
    this.driven = const Color(0xFF9AA0A6),
    this.ahead = const Color(0xFF1A73E8),
    this.drivenWidth = 7,
    this.aheadWidth = 8,
  });

  /// The part already driven.
  final Color driven;

  /// The part still ahead.
  final Color ahead;

  /// Line widths in logical pixels.
  final double drivenWidth;
  final double aheadWidth;
}
