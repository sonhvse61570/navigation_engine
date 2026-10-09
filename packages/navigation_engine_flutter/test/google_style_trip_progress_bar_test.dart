import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

const _fillKey = ValueKey('google_style_trip_progress_fill');
const _trackKey = ValueKey('google_style_trip_progress_track');
const _dotKey = ValueKey('google_style_trip_progress_dot');
const _destinationKey = ValueKey('google_style_trip_progress_destination');

void main() {
  final bar = find.byType(GoogleStyleTripProgressBar);

  Future<void> pumpBar(
    WidgetTester tester,
    double fraction, {
    GoogleStyleColors colors = GoogleStyleColors.day,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 200,
          child: GoogleStyleTripProgressBar(fraction: fraction, colors: colors),
        ),
      ),
    ),
  );

  BoxDecoration decoration(WidgetTester tester, Key key) =>
      tester.widget<DecoratedBox>(find.byKey(key)).decoration as BoxDecoration;

  for (final (fraction, expected) in [
    (0.0, 0.0),
    (0.25, 0.25),
    (1.0, 1.0),
    (-0.5, 0.0),
    (1.5, 1.0),
    (double.nan, 0.0),
  ]) {
    testWidgets('fraction $fraction drives $expected of the height', (
      tester,
    ) async {
      await pumpBar(tester, fraction);
      final track = tester.getRect(bar);
      expect(track.height, closeTo(200, 0.01));
      expect(track.width, closeTo(12, 0.01), reason: 'a 12 dp capsule');
      final fill = tester.getRect(find.byKey(_fillKey));
      expect(fill.height, closeTo(expected * 200, 1));
      expect(fill.width, closeTo(12, 0.01));
      expect(fill.bottom, closeTo(track.bottom, 0.01), reason: 'from below');
    });
  }

  for (final (fraction, expected) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)]) {
    testWidgets('the vehicle dot travels inside the bar at $fraction', (
      tester,
    ) async {
      await pumpBar(tester, fraction);
      final track = tester.getRect(bar);
      final dot = tester.getRect(find.byKey(_dotKey));
      expect(dot.width, closeTo(18, 0.01), reason: 'width + 6');
      expect(dot.height, closeTo(18, 0.01));
      expect(dot.center.dx, closeTo(track.center.dx, 0.01));
      expect(
        dot.center.dy,
        closeTo(track.bottom - 9 - expected * (track.height - 18), 0.01),
      );
      // Inside the bar: no overhang at 0 or 1.
      expect(dot.top, greaterThanOrEqualTo(track.top - 0.01));
      expect(dot.bottom, lessThanOrEqualTo(track.bottom + 0.01));
      final decoration =
          tester.widget<DecoratedBox>(find.byKey(_dotKey)).decoration
              as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect((decoration.border! as Border).top.width, 2);
    });
  }

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('$name: driven grey, remaining accent, a white dot with an '
        'accent ring, a destination dot on top', (tester) async {
      await pumpBar(tester, 0.5, colors: colors);
      expect(decoration(tester, _fillKey).color, colors.progressDriven);
      expect(decoration(tester, _trackKey).color, colors.accent);
      final dot = decoration(tester, _dotKey);
      expect(dot.color, const Color(0xFFFFFFFF));
      expect((dot.border! as Border).top.color, colors.accent);
      final destination = decoration(tester, _destinationKey);
      expect(destination.color, colors.accent);
      final rect = tester.getRect(find.byKey(_destinationKey));
      expect(rect.top, closeTo(tester.getRect(bar).top, 0.01));
      expect(rect.size, const Size(12, 12));
    });
  }

  testWidgets('an unbounded height gives a 120 high bar, dot inside', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [GoogleStyleTripProgressBar(fraction: 1)],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(bar).height, closeTo(120, 0.01));
    expect(
      tester.getRect(find.byKey(_dotKey)).top,
      closeTo(tester.getRect(bar).top, 0.01),
    );
  });

  testWidgets('width sets the bar width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 100,
            child: GoogleStyleTripProgressBar(fraction: 0.5, width: 10),
          ),
        ),
      ),
    );
    expect(tester.getRect(bar).width, closeTo(10, 0.01));
  });
}
