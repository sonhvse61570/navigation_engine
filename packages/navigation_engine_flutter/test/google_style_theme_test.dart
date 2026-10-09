import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  group('GoogleStyleColors', () {
    test('day colors have exact values', () {
      expect(GoogleStyleColors.day.guidance, const Color(0xFF015F61));
      expect(GoogleStyleColors.day.guidanceSecondary, const Color(0xFF015053));
      expect(GoogleStyleColors.day.etaText, const Color(0xFF188038));
      expect(GoogleStyleColors.day.alternative, const Color(0xFF9AA0A6));
    });

    test('night colors have exact values', () {
      expect(GoogleStyleColors.night.guidance, const Color(0xFF014446));
      expect(
        GoogleStyleColors.night.guidanceSecondary,
        const Color(0xFF013436),
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

    test('the SP4 tokens have exact day and night values', () {
      const d = GoogleStyleColors.day;
      const n = GoogleStyleColors.night;
      expect(
        [
          d.guidancePreview,
          d.buttonSurface,
          d.buttonIcon,
          d.selectedTint,
          d.outline,
          d.speedometerSurface,
          d.speedometerText,
          d.speeding,
          d.progressDriven,
        ],
        const [
          Color(0xFF5F6368),
          Color(0xFFFFFFFF),
          Color(0xFF3C4043),
          Color(0xFFD2E3FC),
          Color(0xFFDADCE0),
          Color(0xFFFFFFFF),
          Color(0xFF202124),
          Color(0xFFD93025),
          Color(0xFFBDC1C6),
        ],
      );
      expect(
        [
          n.guidancePreview,
          n.buttonSurface,
          n.buttonIcon,
          n.selectedTint,
          n.outline,
          n.speedometerSurface,
          n.speedometerText,
          n.speeding,
          n.progressDriven,
        ],
        const [
          Color(0xFF3C4043),
          Color(0xFF303134),
          Color(0xFFE8EAED),
          Color(0xFF394457),
          Color(0xFF5F6368),
          Color(0xFF202124),
          Color(0xFFFFFFFF),
          Color(0xFFD93025),
          Color(0xFF5F6368),
        ],
      );
      expect(d.etaText, const Color(0xFF188038));
      expect(n.etaText, const Color(0xFF81C995));
      expect(d.accent, const Color(0xFF1A73E8));
      expect(n.accent, const Color(0xFF8AB4F8));
    });
  });

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('round button: a 52 dp circle in the $name colours', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: GoogleStyleRoundButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: () => taps++,
              colors: colors,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(GoogleStyleRoundButton)),
        const Size(52, 52),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(GoogleStyleRoundButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, colors.buttonSurface);
      expect(material.elevation, 1);
      expect(material.shape, isA<CircleBorder>());
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).color,
        colors.buttonIcon,
      );
      await tester.tap(find.byTooltip('Search'));
      expect(taps, 1);
    });
  }

  testWidgets('round button: surface, iconColor and elevation override', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GoogleStyleRoundButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () {},
            surface: const Color(0xFF123456),
            iconColor: const Color(0xFF654321),
            elevation: 0,
            size: 40,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(GoogleStyleRoundButton)),
      const Size(40, 40),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GoogleStyleRoundButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, const Color(0xFF123456));
    expect(material.elevation, 0);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).color,
      const Color(0xFF654321),
    );
  });
}
