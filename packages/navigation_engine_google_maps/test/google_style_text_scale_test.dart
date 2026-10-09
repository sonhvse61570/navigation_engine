import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

/// A 320x640 phone at 2x text scale.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Alignment alignment = Alignment.bottomCenter,
}) async {
  tester.view
    ..physicalSize = const Size(320, 640)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(alignment: alignment, child: child),
      ),
    ),
  );
}

/// The text scale factor [text] is laid out with.
double _scaleOf(WidgetTester tester, String text) =>
    MediaQuery.textScalerOf(tester.element(find.text(text))).scale(10) / 10;

void main() {
  final lanes = sampleRoute.steps.firstWhere((s) => s.lanes.isNotEmpty);
  final then = sampleRoute.steps[sampleRoute.steps.indexOf(lanes) + 1];
  final guidance = GuidanceState(
    step: lanes,
    stepIndex: sampleRoute.steps.indexOf(lanes),
    distanceToStep: 1250,
    thenStep: then,
    remaining: 4000,
    arrived: false,
  );
  final progress = TripProgress(
    remainingDistance: 54321,
    remainingDuration: const Duration(minutes: 85),
    eta: DateTime(2026, 10, 7, 14, 35),
    fraction: 0.2,
  );
  final slow = NavRoute.fromPoints(
    const [GeoPoint(10.0, 106.0), GeoPoint(10.1, 106.0)],
    summary: 'Highway 1',
    segmentDurations: const [5100],
  );

  for (final (name, formatter, strings) in [
    (
      'English',
      const EnglishGuidanceFormatter() as GuidanceFormatter,
      const NavigationStrings(),
    ),
    (
      'Vietnamese',
      const VietnameseGuidanceFormatter(),
      const NavigationStrings.vietnamese(),
    ),
  ]) {
    group('2x text at 320 dp ($name)', () {
      testWidgets('the header, with lanes and a then-step', (tester) async {
        await _pump(
          tester,
          GoogleStyleManeuverHeader(
            state: guidance,
            formatter: formatter,
            strings: strings,
          ),
          alignment: Alignment.topCenter,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(GoogleStyleLaneGuidance), findsOneWidget);
        expect(
          find.text(strings.then),
          findsNothing,
          reason: 'lanes take the band',
        );
        final distance = formatter.distance(1250);
        expect(_scaleOf(tester, distance), 1.6, reason: 'clamped');
      });

      testWidgets('the header, with a then-step and no lanes', (tester) async {
        final plain = sampleRoute.steps.firstWhere((s) => s.lanes.isEmpty);
        await _pump(
          tester,
          GoogleStyleManeuverHeader(
            state: GuidanceState(
              step: plain,
              stepIndex: sampleRoute.steps.indexOf(plain),
              distanceToStep: 1250,
              thenStep: then,
              remaining: 4000,
              arrived: false,
            ),
            formatter: formatter,
            strings: strings,
          ),
          alignment: Alignment.topCenter,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(strings.then), findsOneWidget);
        expect(_scaleOf(tester, strings.then), 2, reason: 'not clamped');
        expect(_scaleOf(tester, formatter.distance(1250)), 1.6);
      });

      testWidgets('the footer, with all buttons', (tester) async {
        await _pump(
          tester,
          GoogleStyleTripSheet(
            progress: progress,
            formatter: formatter,
            strings: strings,
            onClose: () {},
            onRouteOptions: () {},
            actions: [
              GoogleStyleSheetAction(
                icon: Icons.settings,
                label: strings.settings,
                onPressed: () {},
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
        final duration = formatter.duration(progress.remainingDuration);
        expect(_scaleOf(tester, duration), 1.6, reason: 'clamped');
      });

      testWidgets('the speedometer, with both signs and limit 120', (
        tester,
      ) async {
        for (final style in SpeedLimitSignStyle.values) {
          await _pump(
            tester,
            GoogleStyleSpeedCluster(
              info: SpeedInfo(speed: 130 / 3.6, limit: 120 / 3.6),
              style: style,
              strings: strings,
              formatter: formatter,
            ),
          );
          expect(tester.takeException(), isNull, reason: '$style');
          expect(find.text('130'), findsOneWidget);
          expect(find.text('120'), findsOneWidget);
        }
      });

      testWidgets('the overview panel, with two routes of 5100 s', (
        tester,
      ) async {
        await _pump(
          tester,
          GoogleStyleOverviewPanel(
            state: FlowOverview([slow, slow], 0),
            formatter: formatter,
            strings: strings,
            onSteps: () {},
            onClose: () {},
            onStart: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(formatter.duration(const Duration(seconds: 5100))),
          findsNWidgets(2),
        );
      });

      testWidgets('the overview panel while loading and on an error', (
        tester,
      ) async {
        final to = sampleRoute.points.last;
        await _pump(
          tester,
          GoogleStyleOverviewPanel(
            state: FlowLoading(to),
            strings: strings,
            onCancel: () {},
          ),
        );
        expect(tester.takeException(), isNull, reason: 'loading');
        await _pump(
          tester,
          GoogleStyleOverviewPanel(
            state: FlowError(Exception('offline'), const FlowIdle(), to),
            strings: strings,
            onCancel: () {},
            onRetry: () {},
          ),
        );
        expect(tester.takeException(), isNull, reason: 'error');
        expect(find.text(strings.retry), findsOneWidget);
      });

      testWidgets('the arrival panel', (tester) async {
        await _pump(
          tester,
          GoogleStyleArrivalSheet(
            route: sampleRoute,
            strings: strings,
            onDone: () {},
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
