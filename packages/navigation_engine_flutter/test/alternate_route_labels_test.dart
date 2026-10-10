import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

AlternateRoute _alternate(Duration delta) => AlternateRoute(
  route: NavRoute.fromPoints(const [
    GeoPoint(10.77, 106.70),
    GeoPoint(10.78, 106.70),
  ]),
  timeDelta: delta,
  divergence: 0,
);

void main() {
  group('alternateRouteLabel', () {
    test('a faster alternate: minutes faster', () {
      expect(
        alternateRouteLabel(
          _alternate(const Duration(minutes: -2)),
          const NavigationStrings(),
        ),
        '2 min faster',
      );
    });

    test('a slower alternate: plus minutes', () {
      expect(
        alternateRouteLabel(
          _alternate(const Duration(minutes: 3)),
          const NavigationStrings(),
        ),
        '+3 min',
      );
    });

    test('under half a minute either way: similar ETA', () {
      for (final s in [-29, 0, 29]) {
        expect(
          alternateRouteLabel(
            _alternate(Duration(seconds: s)),
            const NavigationStrings(),
          ),
          'Similar ETA',
          reason: '$s s',
        );
      }
    });

    test('rounds to whole minutes, as AlternateRoute.minutesDelta', () {
      expect(
        alternateRouteLabel(
          _alternate(const Duration(seconds: -90)),
          const NavigationStrings(),
        ),
        '2 min faster',
      );
      expect(
        alternateRouteLabel(
          _alternate(const Duration(seconds: 89)),
          const NavigationStrings(),
        ),
        '+1 min',
      );
    });

    test('uses the given strings', () {
      const vi = NavigationStrings.vietnamese();
      expect(
        alternateRouteLabel(_alternate(const Duration(minutes: -4)), vi),
        vi.minFaster(4),
      );
      expect(
        alternateRouteLabel(_alternate(const Duration(minutes: 5)), vi),
        vi.minSlower(5),
      );
      expect(alternateRouteLabel(_alternate(Duration.zero), vi), vi.similarEta);
    });
  });

  group('alternateLabelColorsOf', () {
    for (final (name, c) in [
      ('day', MapboxStyleColors.day),
      ('night', MapboxStyleColors.night),
    ]) {
      test('$name: accent or muted text on the surface', () {
        final colors = alternateLabelColorsOf(c);
        final border = c.onSurface.withAlpha(0x33);
        expect(
          colors.faster,
          RouteLabelColors(fill: c.surface, text: c.accent, border: border),
        );
        expect(
          colors.slower,
          RouteLabelColors(
            fill: c.surface,
            text: c.onSurfaceVariant,
            border: border,
          ),
        );
      });
    }

    test('the selected-label colours keep their defaults', () {
      final colors = alternateLabelColorsOf(MapboxStyleColors.day);
      const defaults = RouteLabelColors();
      for (final c in [colors.faster, colors.slower]) {
        expect(c.selectedFill, defaults.selectedFill);
        expect(c.selectedText, defaults.selectedText);
      }
    });
  });

  group('MapDefaultColors', () {
    test('neutral route labels: the RouteLabelColors defaults', () {
      expect(MapDefaultColors.routeLabels, const RouteLabelColors());
    });

    test('faster and slower bubbles: the Mapbox-style day ones', () {
      final day = alternateLabelColorsOf(MapboxStyleColors.day);
      expect(MapDefaultColors.fasterLabels, day.faster);
      expect(MapDefaultColors.slowerLabels, day.slower);
      expect(MapDefaultColors.fasterLabels, isNot(day.slower));
    });

    test('a grey alternate line and a red search pin', () {
      expect(MapDefaultColors.alternate, const Color(0xFF9AA0A6));
      expect(MapDefaultColors.searchPin, MapboxStyleColors.day.warning);
    });
  });
}
