import 'package:flutter/material.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// Colours of the Google-style navigation UI.
final class GoogleStyleColors {
  /// Creates a set of colours for the Google-style navigation UI.
  const GoogleStyleColors({
    required this.guidance,
    required this.guidanceSecondary,
    required this.onGuidance,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.accent,
    required this.onAccent,
    required this.alternative,
    required this.etaText,
    required this.warning,
  });

  /// The background of the turn card (green in day mode).
  final Color guidance;

  /// The background of the turn card's "then" strip (darker green in day
  /// mode).
  final Color guidanceSecondary;

  /// The colour of the text and the icons on the turn card.
  final Color onGuidance;

  /// The primary surface colour (white in day mode).
  final Color surface;

  /// The colour for text on surfaces.
  final Color onSurface;

  /// A lighter variant of text colour on surfaces.
  final Color onSurfaceVariant;

  /// The accent colour (blue in day mode): the buttons and the selected
  /// route label. In the drop-in screen it also colours the selected route
  /// option and the route ahead; a bare `GoogleMapsNavigationView` draws
  /// those with its `routeColors.ahead` instead.
  final Color accent;

  /// The colour for text on accents, such as the selected route label.
  final Color onAccent;

  /// The colour of the route options that are not selected and, in the
  /// drop-in screen, of the part of the route already driven.
  final Color alternative;

  /// The colour for ETA text.
  final Color etaText;

  /// The warning colour (red in day mode).
  final Color warning;

  /// The Google-style day theme.
  static const day = GoogleStyleColors(
    guidance: Color(0xFF1E8E3E),
    guidanceSecondary: Color(0xFF137333),
    onGuidance: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF202124),
    onSurfaceVariant: Color(0xFF5F6368),
    accent: Color(0xFF1A73E8),
    onAccent: Color(0xFFFFFFFF),
    alternative: Color(0xFF9AA0A6),
    etaText: Color(0xFF188038),
    warning: Color(0xFFD93025),
  );

  /// The Google-style night theme.
  static const night = GoogleStyleColors(
    guidance: Color(0xFF0D652D),
    guidanceSecondary: Color(0xFF0A4D22),
    onGuidance: Color(0xFFFFFFFF),
    surface: Color(0xFF202124),
    onSurface: Color(0xFFE8EAED),
    onSurfaceVariant: Color(0xFF9AA0A6),
    accent: Color(0xFF8AB4F8),
    onAccent: Color(0xFF202124),
    alternative: Color(0xFF5F6368),
    etaText: Color(0xFF81C995),
    warning: Color(0xFFF28B82),
  );
}

/// The route label colours of a Google-style theme.
extension GoogleStyleRouteLabelColors on GoogleStyleColors {
  /// The route label colours: the selected bubble in [accent] / [onAccent],
  /// the others in [surface] / [onSurface].
  RouteLabelColors get routeLabelColors => RouteLabelColors(
    selectedFill: accent,
    selectedText: onAccent,
    fill: surface,
    text: onSurface,
  );
}
