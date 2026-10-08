import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

void main() {
  group('GoogleStyleColors', () {
    test('day colors have exact values', () {
      expect(GoogleStyleColors.day.guidance, const Color(0xFF1E8E3E));
      expect(GoogleStyleColors.day.guidanceSecondary, const Color(0xFF137333));
      expect(GoogleStyleColors.day.etaText, const Color(0xFF188038));
      expect(GoogleStyleColors.day.alternative, const Color(0xFF9AA0A6));
    });

    test('night colors have exact values', () {
      expect(GoogleStyleColors.night.guidance, const Color(0xFF0D652D));
      expect(
        GoogleStyleColors.night.guidanceSecondary,
        const Color(0xFF0A4D22),
      );
      expect(GoogleStyleColors.night.etaText, const Color(0xFF81C995));
      expect(GoogleStyleColors.night.alternative, const Color(0xFF5F6368));
    });

    test('routeLabelColors maps accent, onAccent, surface and onSurface', () {
      // A distinct colour per field, so a swapped field is caught.
      const c = GoogleStyleColors(
        guidance: Color(0xFF000001),
        guidanceSecondary: Color(0xFF000002),
        onGuidance: Color(0xFF000003),
        surface: Color(0xFF000004),
        onSurface: Color(0xFF000005),
        onSurfaceVariant: Color(0xFF000006),
        accent: Color(0xFF000007),
        onAccent: Color(0xFF000008),
        alternative: Color(0xFF000009),
        etaText: Color(0xFF00000A),
        warning: Color(0xFF00000B),
      );
      final labels = c.routeLabelColors;
      expect(labels.selectedFill, const Color(0xFF000007));
      expect(labels.selectedText, const Color(0xFF000008));
      expect(labels.fill, const Color(0xFF000004));
      expect(labels.text, const Color(0xFF000005));
      expect(labels.border, const Color(0xFF000005).withAlpha(0x33));
    });

    for (final (name, c) in [
      ('day', GoogleStyleColors.day),
      ('night', GoogleStyleColors.night),
    ]) {
      test('routeLabelColors border is visible on the label ($name)', () {
        final labels = c.routeLabelColors;
        final edge = Color.alphaBlend(labels.border, labels.fill);
        double ratio(Color a, Color b) {
          final la = a.computeLuminance();
          final lb = b.computeLuminance();
          return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
        }

        expect(ratio(edge, labels.fill), greaterThanOrEqualTo(1.5));
      });
    }
  });
}
