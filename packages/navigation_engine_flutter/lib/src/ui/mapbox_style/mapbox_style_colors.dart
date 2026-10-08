import 'package:flutter/material.dart';

import '../route_label.dart';

/// Colours of the Mapbox-style navigation UI: a dark banner on top, light
/// panels below and one accent. The palette is original to this package.
final class MapboxStyleColors {
  /// Creates a set of colours for the Mapbox-style navigation UI.
  const MapboxStyleColors({
    required this.banner,
    required this.bannerSecondary,
    required this.onBanner,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.accent,
    required this.onAccent,
    required this.alternative,
    required this.etaText,
    required this.warning,
    required this.end,
  });

  /// Creates the colours from an app's [ColorScheme], so the UI follows the
  /// app's theme. The banner takes the inverse surface pair, the panels the
  /// surface pair and the accent the primary pair; each text colour is the
  /// `on*` colour of its background, so the contrast the scheme guarantees
  /// is kept.
  factory MapboxStyleColors.fromColorScheme(ColorScheme cs) =>
      MapboxStyleColors(
        banner: cs.inverseSurface,
        bannerSecondary: Color.lerp(cs.inverseSurface, Colors.black, 0.2)!,
        onBanner: cs.onInverseSurface,
        surface: cs.surface,
        onSurface: cs.onSurface,
        onSurfaceVariant: cs.onSurfaceVariant,
        accent: cs.primary,
        onAccent: cs.onPrimary,
        alternative: cs.outline,
        etaText: cs.onSurface,
        warning: cs.error,
        end: cs.error,
      );

  /// The background of the maneuver banner (dark navy in day mode).
  final Color banner;

  /// The background of the banner's "then" strip (darker than [banner]).
  final Color bannerSecondary;

  /// The colour of the text and the icons on the banner.
  final Color onBanner;

  /// The colour of the panels (white in day mode).
  final Color surface;

  /// The colour of text on [surface].
  final Color onSurface;

  /// A softer text colour on [surface].
  final Color onSurfaceVariant;

  /// The accent colour (blue in day mode): the buttons, the selected route
  /// card and the selected route label. In a drop-in screen it also colours
  /// the selected route option and the route ahead.
  final Color accent;

  /// The colour of text on [accent].
  final Color onAccent;

  /// The colour of the route options that are not selected and, in a
  /// drop-in screen, of the part of the route already driven.
  final Color alternative;

  /// The colour of the time-left text.
  final Color etaText;

  /// The warning colour (red): rerouting and speeding.
  final Color warning;

  /// The colour of the end-navigation button.
  final Color end;

  /// The day theme.
  static const day = MapboxStyleColors(
    banner: Color(0xFF1D2B3A),
    bannerSecondary: Color(0xFF15212D),
    onBanner: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1B1F24),
    onSurfaceVariant: Color(0xFF5C6773),
    accent: Color(0xFF3B6CF6),
    onAccent: Color(0xFFFFFFFF),
    alternative: Color(0xFF9AA5B1),
    etaText: Color(0xFF1B1F24),
    warning: Color(0xFFE5484D),
    end: Color(0xFFE5484D),
  );

  /// The night theme.
  static const night = MapboxStyleColors(
    banner: Color(0xFF0F1720),
    bannerSecondary: Color(0xFF0A1118),
    onBanner: Color(0xFFF2F5F8),
    surface: Color(0xFF1C232B),
    onSurface: Color(0xFFE6EBF0),
    onSurfaceVariant: Color(0xFF9AA5B1),
    accent: Color(0xFF6E95FF),
    onAccent: Color(0xFF0F1720),
    alternative: Color(0xFF5C6773),
    etaText: Color(0xFFE6EBF0),
    warning: Color(0xFFFF6B6B),
    end: Color(0xFFFF6B6B),
  );

  /// The route label colours: the selected bubble in [accent] / [onAccent],
  /// the others in [surface] / [onSurface], with a border of [onSurface] at
  /// 20 % (dark by day, light at night, so it shows on both).
  RouteLabelColors get routeLabelColors => RouteLabelColors(
    selectedFill: accent,
    selectedText: onAccent,
    fill: surface,
    text: onSurface,
    border: onSurface.withAlpha(0x33),
  );

  @override
  bool operator ==(Object other) =>
      other is MapboxStyleColors &&
      other.banner == banner &&
      other.bannerSecondary == bannerSecondary &&
      other.onBanner == onBanner &&
      other.surface == surface &&
      other.onSurface == onSurface &&
      other.onSurfaceVariant == onSurfaceVariant &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.alternative == alternative &&
      other.etaText == etaText &&
      other.warning == warning &&
      other.end == end;

  @override
  int get hashCode => Object.hash(
    banner,
    bannerSecondary,
    onBanner,
    surface,
    onSurface,
    onSurfaceVariant,
    accent,
    onAccent,
    alternative,
    etaText,
    warning,
    end,
  );
}
