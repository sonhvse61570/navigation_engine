import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

final _progress = TripProgress(
  remainingDistance: 5400,
  remainingDuration: const Duration(minutes: 8),
  eta: DateTime(2026, 10, 7, 14, 35),
  fraction: 0.2,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

void main() {
  group('GoogleStyleTripFooter', () {
    testWidgets('shows duration, distance and clock time', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripFooter(progress: _progress)),
      );
      expect(find.text('8 min'), findsOneWidget);
      expect(find.text('5.4 km · 14:35'), findsOneWidget);
    });

    testWidgets('rerouting replaces the second line', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripFooter(progress: _progress, rerouting: true)),
      );
      expect(find.text('8 min'), findsOneWidget);
      expect(find.text('Rerouting…'), findsOneWidget);
      expect(find.text('5.4 km · 14:35'), findsNothing);
    });

    testWidgets('buttons appear only with their callback', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripFooter(progress: _progress)),
      );
      expect(find.byTooltip('Exit navigation'), findsNothing);
      expect(find.byTooltip('Steps'), findsNothing);
      expect(find.byTooltip('Overview'), findsNothing);

      var end = 0, steps = 0, overview = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleTripFooter(
            progress: _progress,
            onEnd: () => end++,
            onSteps: () => steps++,
            onOverview: () => overview++,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Exit navigation'));
      await tester.tap(find.byTooltip('Steps'));
      await tester.tap(find.byTooltip('Overview'));
      expect([end, steps, overview], [1, 1, 1]);
    });

    testWidgets('each button is independent', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripFooter(progress: _progress, onSteps: () {})),
      );
      expect(find.byTooltip('Steps'), findsOneWidget);
      expect(find.byTooltip('Exit navigation'), findsNothing);
      expect(find.byTooltip('Overview'), findsNothing);
    });

    testWidgets('fits a 320 dp screen with every button', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          GoogleStyleTripFooter(
            progress: _progress,
            onEnd: () {},
            onSteps: () {},
            onOverview: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the Vietnamese formatter', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleTripFooter(
            progress: _progress,
            formatter: const VietnameseGuidanceFormatter(),
          ),
        ),
      );
      expect(find.text('8 phút'), findsOneWidget);
      expect(find.text('5,4 km · 14:35'), findsOneWidget);
    });
  });

  group('GoogleStyleSpeedometer', () {
    testWidgets('shows the speed in km/h', (tester) async {
      await tester.pumpWidget(
        _host(const GoogleStyleSpeedometer(info: SpeedInfo(speed: 11.7))),
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
    });

    testWidgets('speeds and limits go through the formatter', (tester) async {
      await tester.pumpWidget(
        _host(
          const GoogleStyleSpeedometer(
            info: SpeedInfo(speed: 11.7, limit: 20),
            formatter: _MphFormatter(),
          ),
        ),
      );
      expect(find.text('26'), findsOneWidget);
      expect(find.text('mph'), findsOneWidget);
      expect(find.text('45'), findsOneWidget, reason: 'the limit in mph');
      expect(find.text('km/h'), findsNothing);
      expect(find.text('42'), findsNothing);

      await tester.pumpWidget(
        _host(
          const GoogleStyleSpeedometer(
            info: SpeedInfo(speed: 11.7, limit: 20),
            sign: SpeedLimitSign.rectangular,
            formatter: _MphFormatter(),
          ),
        ),
      );
      expect(find.text('45'), findsOneWidget);
    });

    testWidgets('over the limit the speed is drawn in the warning colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedometer(info: SpeedInfo(speed: 20, limit: 50 / 3.6)),
        ),
      );
      final text = tester.widget<Text>(find.text('72'));
      expect(text.style?.color, GoogleStyleColors.day.warning);
    });

    testWidgets('within the limit the speed is drawn in the normal colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedometer(
            info: SpeedInfo(speed: 40 / 3.6, limit: 50 / 3.6),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('40'));
      expect(text.style?.color, GoogleStyleColors.day.onSurface);
    });

    testWidgets('no limit means no sign', (tester) async {
      await tester.pumpWidget(
        _host(const GoogleStyleSpeedometer(info: SpeedInfo(speed: 11.7))),
      );
      expect(find.text('50'), findsNothing);
      expect(find.text('SPEED LIMIT'), findsNothing);
    });

    testWidgets('circular sign shows the limit', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedometer(info: SpeedInfo(speed: 11.7, limit: 50 / 3.6)),
        ),
      );
      expect(find.text('50'), findsOneWidget);
      expect(find.text('SPEED LIMIT'), findsNothing);
    });

    testWidgets('rectangular sign shows SPEED LIMIT', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedometer(
            info: SpeedInfo(speed: 11.7, limit: 50 / 3.6),
            sign: SpeedLimitSign.rectangular,
          ),
        ),
      );
      expect(find.text('SPEED LIMIT'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });
  });

  for (final sign in SpeedLimitSign.values) {
    testWidgets('a three-digit limit fits the $sign sign', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedometer(
            info: SpeedInfo(speed: 11.7, limit: 120 / 3.6),
            sign: sign,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('120'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('120')).style?.fontSize,
        sign == SpeedLimitSign.circular ? 20 : 22,
      );
    });
  }

  for (final (name, strings) in [
    ('English', const NavigationStrings()),
    ('Vietnamese', const NavigationStrings.vietnamese()),
  ]) {
    testWidgets(
      'rectangular sign keeps its font sizes and does not overflow ($name)',
      (tester) async {
        await tester.pumpWidget(
          _host(
            GoogleStyleSpeedometer(
              info: SpeedInfo(speed: 11.7, limit: 50 / 3.6),
              sign: SpeedLimitSign.rectangular,
              strings: strings,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final label = find.text(strings.speedLimit);
        final number = find.text('50');
        expect(
          find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsNothing,
        );
        expect(tester.widget<Text>(label).style?.fontSize, 8);
        expect(tester.widget<Text>(number).style?.fontSize, 22);
        expect(tester.getSize(label).height, greaterThan(10));
      },
    );
  }

  group('GoogleStyleRecenterButton', () {
    testWidgets('shows the label and calls back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(GoogleStyleRecenterButton(onPressed: () => taps++)),
      );
      expect(find.text('Re-center'), findsOneWidget);
      await tester.tap(find.text('Re-center'));
      expect(taps, 1);
    });
  });
}

class _MphFormatter extends EnglishGuidanceFormatter {
  const _MphFormatter();

  @override
  String speedValue(double metresPerSecond) =>
      '${(metresPerSecond * 2.23694).round()}';

  @override
  String get speedUnit => 'mph';
}
