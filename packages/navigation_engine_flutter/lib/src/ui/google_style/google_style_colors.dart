import 'package:flutter/material.dart';

import '../route_label.dart';

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
    this.guidancePreview = const Color(0xFF5F6368),
    this.buttonSurface = const Color(0xFFFFFFFF),
    this.buttonIcon = const Color(0xFF3C4043),
    this.selectedTint = const Color(0xFFD2E3FC),
    this.onSelectedTint = const Color(0xFF1967D2),
    this.outline = const Color(0xFFDADCE0),
    this.speedometerSurface = const Color(0xFFFFFFFF),
    this.speedometerText = const Color(0xFF202124),
    this.speeding = const Color(0xFFD93025),
    this.progressDriven = const Color(0xFFBDC1C6),
    this.compassNorth = const Color(0xFFEA4335),
    this.switchThumb = const Color(0xFFFFFFFF),
    this.switchTrackOff = const Color(0xFFDADCE0),
    this.closeOutline = const Color(0xFFC4C7C5),
  });

  /// The background of the turn card (teal).
  final Color guidance;

  /// The background of the turn card's "Then" tab and lanes band (a darker
  /// teal).
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
  /// option and the route ahead; a bare map view draws those with its
  /// `routeColors.ahead` instead.
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

  /// The grey of the turn card while a step is previewed or a new route is
  /// looked for.
  final Color guidancePreview;

  /// The surface of the round map buttons (and the trip sheet's circles),
  /// the report button and the Re-center pill.
  final Color buttonSurface;

  /// The icons of the round map buttons and the report button, and the
  /// compass's "N".
  final Color buttonIcon;

  /// The fill of a selected option: the sound pill's, the selected search
  /// chip and the focused search result.
  final Color selectedTint;

  /// The text and icons on [selectedTint], such as the selected search
  /// chip's label and icon.
  final Color onSelectedTint;

  /// The drag handle of the trip sheet and the outline of chips and round
  /// buttons.
  final Color outline;

  /// The surface of the speed cluster.
  final Color speedometerSurface;

  /// The speed text when not speeding.
  final Color speedometerText;

  /// Speeding: the text of a minor alert, the background of a major one.
  final Color speeding;

  /// The driven part of the trip progress bar.
  final Color progressDriven;

  /// The compass's north triangle (red, day and night).
  final Color compassNorth;

  /// The thumb of the trip sheet's switches, on and off (white by day).
  final Color switchThumb;

  /// The track of a trip sheet switch that is off (light grey by day); an
  /// on track is [accent].
  final Color switchTrackOff;

  /// The ring of the trip sheet's close circle, a little darker than
  /// [outline].
  final Color closeOutline;

  /// The Google-style day theme.
  static const day = GoogleStyleColors(
    guidance: Color(0xFF015F61),
    guidanceSecondary: Color(0xFF015053),
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
    guidance: Color(0xFF014446),
    guidanceSecondary: Color(0xFF013436),
    onGuidance: Color(0xFFFFFFFF),
    surface: Color(0xFF202124),
    onSurface: Color(0xFFE8EAED),
    onSurfaceVariant: Color(0xFF9AA0A6),
    accent: Color(0xFF8AB4F8),
    onAccent: Color(0xFF202124),
    alternative: Color(0xFF5F6368),
    etaText: Color(0xFF81C995),
    warning: Color(0xFFF28B82),
    guidancePreview: Color(0xFF3C4043),
    buttonSurface: Color(0xFF303134),
    buttonIcon: Color(0xFFE8EAED),
    selectedTint: Color(0xFF394457),
    onSelectedTint: Color(0xFF8AB4F8),
    outline: Color(0xFF5F6368),
    speedometerSurface: Color(0xFF202124),
    speedometerText: Color(0xFFFFFFFF),
    speeding: Color(0xFFD93025),
    progressDriven: Color(0xFF5F6368),
    switchThumb: Color(0xFFE8EAED),
    switchTrackOff: Color(0xFF5F6368),
    closeOutline: Color(0xFF80868B),
  );
}

/// The route label colours of a Google-style theme.
extension GoogleStyleRouteLabelColors on GoogleStyleColors {
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

  /// The bubble of an alternate route that is faster: green text on a
  /// button surface.
  RouteLabelColors get fasterLabelColors => RouteLabelColors(
    fill: buttonSurface,
    text: etaText,
    border: onSurface.withAlpha(0x33),
  );

  /// The bubble of an alternate route that is slower or as fast: grey text
  /// on a button surface.
  RouteLabelColors get slowerLabelColors => RouteLabelColors(
    fill: buttonSurface,
    text: onSurfaceVariant,
    border: onSurface.withAlpha(0x33),
  );
}
