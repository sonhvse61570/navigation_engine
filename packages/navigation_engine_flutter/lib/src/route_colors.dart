import 'dart:ui';

/// How a navigation view draws the route line.
class RouteColors {
  /// Creates the route line's colours and widths.
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

  /// The width of the part already driven, in logical pixels.
  final double drivenWidth;

  /// The width of the part still ahead, in logical pixels.
  final double aheadWidth;
}
