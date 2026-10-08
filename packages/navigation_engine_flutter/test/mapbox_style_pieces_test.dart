import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

const _formatter = EnglishGuidanceFormatter();

/// The WCAG contrast ratio of two colours, from their relative luminance.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _host(
  Widget child, {
  Alignment alignment = Alignment.bottomCenter,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(alignment: alignment, child: child),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

GuidanceState _state(
  RouteStep? step, {
  double distance = 180,
  RouteStep? then,
}) => GuidanceState(
  step: step,
  stepIndex: step == null ? -1 : 3,
  distanceToStep: distance,
  thenStep: then,
  remaining: 2000,
  arrived: false,
);

final _progress = TripProgress(
  remainingDistance: 5400,
  remainingDuration: const Duration(minutes: 8),
  eta: DateTime(2026, 10, 7, 14, 35),
  fraction: 0.2,
);

final _overview = FlowOverview([
  sampleRoute,
  sampleRouteAlternatives.single,
], 0);

class _MphFormatter extends EnglishGuidanceFormatter {
  const _MphFormatter();

  @override
  String speedValue(double metresPerSecond) =>
      '${(metresPerSecond * 2.23694).round()}';

  @override
  String get speedUnit => 'mph';
}

void main() {
  group('MapboxStyleColors', () {
    test('day colors have exact values', () {
      const c = MapboxStyleColors.day;
      expect(c.banner, const Color(0xFF1D2B3A));
      expect(c.bannerSecondary, const Color(0xFF15212D));
      expect(c.onBanner, const Color(0xFFFFFFFF));
      expect(c.surface, const Color(0xFFFFFFFF));
      expect(c.onSurface, const Color(0xFF1B1F24));
      expect(c.onSurfaceVariant, const Color(0xFF5C6773));
      expect(c.accent, const Color(0xFF3B6CF6));
      expect(c.onAccent, const Color(0xFFFFFFFF));
      expect(c.alternative, const Color(0xFF9AA5B1));
      expect(c.etaText, const Color(0xFF1B1F24));
      expect(c.warning, const Color(0xFFE5484D));
      expect(c.end, const Color(0xFFE5484D));
    });

    test('night colors have exact values', () {
      const c = MapboxStyleColors.night;
      expect(c.banner, const Color(0xFF0F1720));
      expect(c.bannerSecondary, const Color(0xFF0A1118));
      expect(c.onBanner, const Color(0xFFF2F5F8));
      expect(c.surface, const Color(0xFF1C232B));
      expect(c.onSurface, const Color(0xFFE6EBF0));
      expect(c.onSurfaceVariant, const Color(0xFF9AA5B1));
      expect(c.accent, const Color(0xFF6E95FF));
      expect(c.onAccent, const Color(0xFF0F1720));
      expect(c.alternative, const Color(0xFF5C6773));
      expect(c.etaText, const Color(0xFFE6EBF0));
      expect(c.warning, const Color(0xFFFF6B6B));
      expect(c.end, const Color(0xFFFF6B6B));
    });

    test('fromColorScheme maps the scheme onto the fields', () {
      final cs = ColorScheme.fromSeed(seedColor: Colors.teal);
      final c = MapboxStyleColors.fromColorScheme(cs);
      expect(c.banner, cs.inverseSurface);
      expect(
        c.bannerSecondary,
        Color.lerp(cs.inverseSurface, Colors.black, 0.2),
      );
      expect(c.onBanner, cs.onInverseSurface);
      expect(c.surface, cs.surface);
      expect(c.onSurface, cs.onSurface);
      expect(c.onSurfaceVariant, cs.onSurfaceVariant);
      expect(c.accent, cs.primary);
      expect(c.onAccent, cs.onPrimary);
      expect(c.alternative, cs.outline);
      expect(c.etaText, cs.onSurface);
      expect(c.warning, cs.error);
      expect(c.end, cs.error);
    });

    test('routeLabelColors takes the accent and surface pairs', () {
      const c = MapboxStyleColors.night;
      final labels = c.routeLabelColors;
      expect(labels.selectedFill, c.accent);
      expect(labels.selectedText, c.onAccent);
      expect(labels.fill, c.surface);
      expect(labels.text, c.onSurface);
    });

    test('contrastRatio helper: black on white is 21, equal colours 1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.teal, Colors.teal), 1);
    });

    // Review Focus 5: an app whose scheme has a light inverseSurface must
    // still get a readable banner, because the on* pairs are used.
    for (final (name, scheme) in [
      ('teal light', ColorScheme.fromSeed(seedColor: Colors.teal)),
      (
        'teal dark',
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      ('yellow light', ColorScheme.fromSeed(seedColor: Colors.yellow)),
    ]) {
      test('fromColorScheme keeps contrast >= 4.5 ($name)', () {
        final c = MapboxStyleColors.fromColorScheme(scheme);
        expect(
          contrastRatio(c.banner, c.onBanner),
          greaterThanOrEqualTo(4.5),
          reason: 'banner / onBanner',
        );
        expect(
          contrastRatio(c.surface, c.onSurface),
          greaterThanOrEqualTo(4.5),
          reason: 'surface / onSurface',
        );
        // The "then" strip is still readable too.
        expect(
          contrastRatio(c.bannerSecondary, c.onBanner),
          greaterThanOrEqualTo(4.5),
          reason: 'bannerSecondary / onBanner',
        );
      });
    }
  });

  group('MapboxStyleManeuverBanner', () {
    final lyTuTrong = sampleRoute.steps[3];

    testWidgets('shows icon, distance and road name on the banner colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleManeuverBanner(state: _state(lyTuTrong)),
          alignment: Alignment.topCenter,
        ),
      );
      expect(find.text(_formatter.distance(180)), findsOneWidget);
      expect(find.text('Ly Tu Trong'), findsOneWidget);
      expect(find.byIcon(Icons.turn_right), findsWidgets);
      final card = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(MapboxStyleManeuverBanner),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.color, MapboxStyleColors.day.banner);
      final icon = tester.widget<Icon>(find.byIcon(Icons.turn_right).first);
      expect(icon.size, 40);
      expect(
        tester.widget<Text>(find.text(_formatter.distance(180))).style,
        isA<TextStyle>()
            .having((s) => s.fontSize, 'fontSize', 24)
            .having((s) => s.fontWeight, 'weight', FontWeight.w700),
      );
      expect(
        tester.widget<Text>(find.text('Ly Tu Trong')).style,
        isA<TextStyle>()
            .having((s) => s.fontSize, 'fontSize', 20)
            .having((s) => s.fontWeight, 'weight', FontWeight.w500),
      );
    });

    testWidgets('uses the colours it is given', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleManeuverBanner(
            state: _state(lyTuTrong, then: sampleRoute.steps[4]),
            colors: MapboxStyleColors.night,
          ),
          alignment: Alignment.topCenter,
        ),
      );
      final text = tester.widget<Text>(find.text('Ly Tu Trong'));
      expect(text.style?.color, MapboxStyleColors.night.onBanner);
    });

    testWidgets('unnamed road shows the instruction', (tester) async {
      final unnamed = sampleRoute.steps.firstWhere((s) => s.roadName == '');
      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(unnamed))),
      );
      expect(find.text(_formatter.instruction(unnamed)), findsOneWidget);
    });

    testWidgets('a null step shows the arrived text', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(null, distance: 0))),
      );
      expect(find.text('You have arrived'), findsOneWidget);
    });

    testWidgets('then strip only with a then step', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(lyTuTrong))),
      );
      expect(find.text('Then'), findsNothing);

      await tester.pumpWidget(
        _host(
          MapboxStyleManeuverBanner(
            state: _state(lyTuTrong, then: sampleRoute.steps[4]),
          ),
        ),
      );
      expect(find.text('Then'), findsOneWidget);
    });

    testWidgets('lanes shown when the step has lanes', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(lyTuTrong))),
      );
      expect(
        find.byKey(const ValueKey('mapbox_style_lane_cell')),
        findsNWidgets(3),
      );

      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(sampleRoute.steps[2]))),
      );
      expect(
        find.byKey(const ValueKey('mapbox_style_lane_cell')),
        findsNothing,
      );
    });

    testWidgets('lane cells: valid opaque active arrow, invalid dimmed', (
      tester,
    ) async {
      final step = NavRoute.fromPoints(
        const [
          GeoPoint(10.0, 106.0),
          GeoPoint(10.001, 106.0),
          GeoPoint(10.002, 106.0),
        ],
        steps: [
          const RouteStepSeed.atVertex(
            1,
            type: ManeuverType.turn,
            modifier: ManeuverModifier.right,
            roadName: 'Lanes',
            lanes: [
              Lane(directions: {LaneDirection.left}),
              Lane(
                directions: {LaneDirection.straight, LaneDirection.right},
                valid: true,
                active: LaneDirection.right,
              ),
            ],
          ),
        ],
      ).steps[0];
      await tester.pumpWidget(
        _host(MapboxStyleManeuverBanner(state: _state(step))),
      );
      final right = tester.widgetList<Icon>(find.byIcon(Icons.turn_right));
      expect(right.any((i) => i.color!.a == 1.0 && i.size == 28), isTrue);
      expect(find.byIcon(Icons.straight), findsNothing);
      final left = tester.widget<Icon>(find.byIcon(Icons.turn_left));
      expect(left.color!.a * 255, closeTo(102, 1));
    });

    testWidgets('Vietnamese formatter and strings', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleManeuverBanner(
            state: _state(lyTuTrong, then: sampleRoute.steps[4]),
            formatter: const VietnameseGuidanceFormatter(),
            strings: const NavigationStrings.vietnamese(),
          ),
        ),
      );
      expect(find.text('Sau đó'), findsOneWidget);
      expect(
        find.text(const VietnameseGuidanceFormatter().distance(180)),
        findsOneWidget,
      );
    });

    testWidgets('no overflow at 320 dp with a 120-character road name', (
      tester,
    ) async {
      _size(tester, const Size(320, 640));
      final longName = List.filled(120, 'x').join();
      final route = NavRoute.fromPoints(
        const [
          GeoPoint(10.0, 106.0),
          GeoPoint(10.001, 106.0),
          GeoPoint(10.002, 106.0),
          GeoPoint(10.003, 106.0),
        ],
        steps: [
          RouteStepSeed.atVertex(
            1,
            type: ManeuverType.turn,
            modifier: ManeuverModifier.right,
            roadName: longName,
            lanes: lyTuTrong.lanes,
          ),
          const RouteStepSeed.atVertex(
            2,
            type: ManeuverType.turn,
            modifier: ManeuverModifier.left,
            roadName: 'Next',
          ),
        ],
      );
      await tester.pumpWidget(
        _host(
          MapboxStyleManeuverBanner(
            state: _state(route.steps[0], then: route.steps[1]),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(longName), findsOneWidget);
    });
  });

  group('MapboxStyleTripProgress', () {
    testWidgets('shows duration, distance and clock time', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleTripProgress(progress: _progress)),
      );
      expect(find.text('8 min'), findsOneWidget);
      expect(find.text('5.4 km · 14:35'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('8 min')).style,
        isA<TextStyle>()
            .having((s) => s.fontSize, 'fontSize', 26)
            .having((s) => s.fontWeight, 'weight', FontWeight.w700)
            .having((s) => s.color, 'color', MapboxStyleColors.day.etaText),
      );
    });

    testWidgets('rerouting replaces the second line, in the warning colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(MapboxStyleTripProgress(progress: _progress, rerouting: true)),
      );
      expect(find.text('8 min'), findsOneWidget);
      expect(find.text('Rerouting…'), findsOneWidget);
      expect(find.text('5.4 km · 14:35'), findsNothing);
      expect(
        tester.widget<Text>(find.text('Rerouting…')).style?.color,
        MapboxStyleColors.day.warning,
      );
    });

    testWidgets('buttons appear only with their callback', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleTripProgress(progress: _progress)),
      );
      expect(find.byTooltip('Exit navigation'), findsNothing);
      expect(find.byTooltip('Steps'), findsNothing);
      expect(find.byTooltip('Overview'), findsNothing);

      var end = 0, steps = 0, overview = 0;
      await tester.pumpWidget(
        _host(
          MapboxStyleTripProgress(
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
      expect(find.byIcon(Icons.alt_route), findsOneWidget);
    });

    testWidgets('the end button is a filled circle in the end colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(MapboxStyleTripProgress(progress: _progress, onEnd: () {})),
      );
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(
        button.style?.backgroundColor?.resolve(const {}),
        MapboxStyleColors.day.end,
      );
    });

    for (final (name, colors) in [
      ('day', MapboxStyleColors.day),
      ('night', MapboxStyleColors.night),
      (
        'teal light',
        MapboxStyleColors.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
      ),
      (
        'teal dark',
        MapboxStyleColors.fromColorScheme(
          ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
      ),
      (
        'yellow light',
        MapboxStyleColors.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.yellow),
        ),
      ),
    ]) {
      testWidgets('the end icon has contrast >= 3 on the end colour ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            MapboxStyleTripProgress(
              progress: _progress,
              colors: colors,
              onEnd: () {},
            ),
          ),
        );
        final icon = IconTheme.of(tester.element(find.byIcon(Icons.close)));
        expect(icon.color, isNotNull);
        expect(contrastRatio(icon.color!, colors.end), greaterThanOrEqualTo(3));
      });
    }

    testWidgets(
      '1 h 25 min shrinks instead of truncating at 320 dp, 2x text, all buttons',
      (tester) async {
        _size(tester, const Size(320, 640));
        final long = TripProgress(
          remainingDistance: 54321,
          remainingDuration: const Duration(minutes: 85),
          eta: DateTime(2026, 10, 7, 14, 35),
          fraction: 0.2,
        );
        final text = _formatter.duration(long.remainingDuration);
        await tester.pumpWidget(
          _host(
            MapboxStyleTripProgress(
              progress: long,
              onEnd: () {},
              onSteps: () {},
              onOverview: () {},
            ),
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(text))
              .didExceedMaxLines,
          isFalse,
        );
      },
    );

    testWidgets('each button is independent', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleTripProgress(progress: _progress, onSteps: () {})),
      );
      expect(find.byTooltip('Steps'), findsOneWidget);
      expect(find.byTooltip('Exit navigation'), findsNothing);
      expect(find.byTooltip('Overview'), findsNothing);
    });

    testWidgets('fits a 320 dp screen with every button', (tester) async {
      _size(tester, const Size(320, 640));
      await tester.pumpWidget(
        _host(
          MapboxStyleTripProgress(
            progress: _progress,
            onEnd: () {},
            onSteps: () {},
            onOverview: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the Vietnamese formatter and strings', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleTripProgress(
            progress: _progress,
            formatter: const VietnameseGuidanceFormatter(),
            strings: const NavigationStrings.vietnamese(),
            onEnd: () {},
          ),
        ),
      );
      expect(find.text('8 phút'), findsOneWidget);
      expect(find.text('5,4 km · 14:35'), findsOneWidget);
      expect(find.byTooltip('Thoát dẫn đường'), findsOneWidget);
    });
  });

  group('MapboxStyleSpeedLimit', () {
    testWidgets('shows the speed in km/h', (tester) async {
      await tester.pumpWidget(
        _host(const MapboxStyleSpeedLimit(info: SpeedInfo(speed: 11.7))),
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
    });

    testWidgets('speeds and limits go through the formatter', (tester) async {
      await tester.pumpWidget(
        _host(
          const MapboxStyleSpeedLimit(
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
          const MapboxStyleSpeedLimit(
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
          MapboxStyleSpeedLimit(info: SpeedInfo(speed: 20, limit: 50 / 3.6)),
        ),
      );
      final text = tester.widget<Text>(find.text('72'));
      expect(text.style?.color, MapboxStyleColors.day.warning);
    });

    testWidgets('within the limit the speed is drawn in the normal colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleSpeedLimit(
            info: SpeedInfo(speed: 40 / 3.6, limit: 50 / 3.6),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('40'));
      expect(text.style?.color, MapboxStyleColors.day.onSurface);
    });

    testWidgets('no limit means no sign', (tester) async {
      await tester.pumpWidget(
        _host(const MapboxStyleSpeedLimit(info: SpeedInfo(speed: 11.7))),
      );
      expect(find.text('50'), findsNothing);
      expect(find.text('SPEED LIMIT'), findsNothing);
    });

    testWidgets('circular sign shows the limit', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleSpeedLimit(info: SpeedInfo(speed: 11.7, limit: 50 / 3.6)),
        ),
      );
      expect(find.text('50'), findsOneWidget);
      expect(find.text('SPEED LIMIT'), findsNothing);
    });

    testWidgets('rectangular sign shows SPEED LIMIT', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleSpeedLimit(
            info: SpeedInfo(speed: 11.7, limit: 50 / 3.6),
            sign: SpeedLimitSign.rectangular,
          ),
        ),
      );
      expect(find.text('SPEED LIMIT'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('showSpeed and showLimit are independent', (tester) async {
      final info = SpeedInfo(speed: 11.7, limit: 50 / 3.6);
      await tester.pumpWidget(
        _host(MapboxStyleSpeedLimit(info: info, showSpeed: false)),
      );
      expect(find.text('42'), findsNothing);
      expect(find.text('50'), findsOneWidget);

      await tester.pumpWidget(
        _host(MapboxStyleSpeedLimit(info: info, showLimit: false)),
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.text('50'), findsNothing);
    });

    for (final sign in SpeedLimitSign.values) {
      testWidgets('a three-digit limit fits the $sign sign', (tester) async {
        await tester.pumpWidget(
          _host(
            MapboxStyleSpeedLimit(
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
              MapboxStyleSpeedLimit(
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
  });

  group('MapboxStyleRecenterButton', () {
    testWidgets('shows the label and calls back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(MapboxStyleRecenterButton(onPressed: () => taps++)),
      );
      expect(find.text('Re-center'), findsOneWidget);
      expect(find.byIcon(Icons.navigation), findsOneWidget);
      await tester.tap(find.text('Re-center'));
      expect(taps, 1);
    });

    testWidgets('speaks the strings it is given', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleRecenterButton(
            onPressed: () {},
            strings: const NavigationStrings.vietnamese(),
          ),
        ),
      );
      expect(find.text('Căn giữa'), findsOneWidget);
    });
  });

  group('MapboxStyleRoutePanel', () {
    testWidgets('loading shows a spinner and the message', (tester) async {
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(state: FlowLoading(sampleRoute.points.last)),
        ),
      );
      expect(find.text('Finding routes…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loading offers Cancel only with onCancel', (tester) async {
      final loading = FlowLoading(sampleRoute.points.last);
      await tester.pumpWidget(_host(MapboxStyleRoutePanel(state: loading)));
      expect(find.text('Cancel'), findsNothing);

      var cancel = 0;
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: loading, onCancel: () => cancel++)),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      expect(cancel, 1);
    });

    testWidgets('the close button shows only with onClose, in an overview', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MapboxStyleRoutePanel(state: _overview)));
      expect(find.byIcon(Icons.close), findsNothing);

      var closed = 0;
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: _overview, onClose: () => closed++)),
      );
      final close = find.widgetWithIcon(IconButton, Icons.close);
      expect(close, findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      // At the top right of the panel.
      final panel = tester.getRect(find.byType(MapboxStyleRoutePanel));
      final button = tester.getRect(close);
      expect(button.top - panel.top, lessThan(24));
      expect(panel.right - button.right, lessThan(24));
      await tester.tap(close);
      expect(closed, 1);

      // Not in loading.
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(
            state: FlowLoading(sampleRoute.points.last),
            onClose: () => closed++,
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows a card per route with duration, distance and via', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MapboxStyleRoutePanel(state: _overview)));
      expect(find.byKey(const ValueKey('route_card_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_card_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_card_2')), findsNothing);
      expect(
        find.text(
          _formatter.duration(Duration(seconds: sampleRoute.duration.round())),
        ),
        findsWidgets,
      );
      expect(find.text('8 min'), findsWidgets);
      expect(find.text(_formatter.distance(sampleRoute.length)), findsWidgets);
      expect(find.text('via Ly Tu Trong, Nguyen Huu Canh'), findsOneWidget);
      expect(find.text('Fastest'), findsOneWidget);
    });

    testWidgets('the selected card is marked with the accent border', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: FlowOverview(_overview.routes, 1))),
      );
      Color? borderOf(int i) {
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byKey(ValueKey('route_card_$i')),
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.shape! as RoundedRectangleBorder).side.color;
      }

      expect(borderOf(1), MapboxStyleColors.day.accent);
      expect(borderOf(0), isNot(MapboxStyleColors.day.accent));
    });

    testWidgets('a single route is not labelled fastest', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: FlowOverview([sampleRoute], 0))),
      );
      expect(find.text('Fastest'), findsNothing);
    });

    testWidgets('tapping a card selects it', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: _overview, onSelect: selected.add)),
      );
      await tester.tap(find.byKey(const ValueKey('route_card_1')));
      expect(selected, [1]);
    });

    testWidgets('start and resume buttons', (tester) async {
      var started = 0;
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(state: _overview, onStart: () => started++),
        ),
      );
      expect(find.text('Resume'), findsNothing);
      await tester.tap(find.text('Start'));
      expect(started, 1);

      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(
            state: _overview,
            tripOverview: true,
            onStart: () => started++,
          ),
        ),
      );
      expect(find.text('Start'), findsNothing);
      await tester.tap(find.text('Resume'));
      expect(started, 2);
    });

    testWidgets('the start button spans the panel width', (tester) async {
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: _overview, onStart: () {})),
      );
      final panel = tester.getRect(find.byType(MapboxStyleRoutePanel));
      final start = tester.getRect(find.widgetWithText(FilledButton, 'Start'));
      expect(start.width, closeTo(panel.width - 32, 0.5));
    });

    testWidgets('Steps appears only with onSteps', (tester) async {
      await tester.pumpWidget(_host(MapboxStyleRoutePanel(state: _overview)));
      expect(find.text('Steps'), findsNothing);

      var steps = 0;
      await tester.pumpWidget(
        _host(MapboxStyleRoutePanel(state: _overview, onSteps: () => steps++)),
      );
      await tester.tap(find.text('Steps'));
      expect(steps, 1);
    });

    testWidgets('error shows the message with retry and cancel', (
      tester,
    ) async {
      var retry = 0, cancel = 0;
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(
            state: FlowError(
              Exception('offline'),
              const FlowIdle(),
              sampleRoute.points.last,
            ),
            onRetry: () => retry++,
            onCancel: () => cancel++,
          ),
        ),
      );
      expect(find.text('No route found'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Cancel'));
      expect([retry, cancel], [1, 1]);
    });

    Future<void> pumpRoutes(
      WidgetTester tester,
      int count, {
      Size size = const Size(400, 900),
      double textScale = 1,
    }) async {
      _size(tester, size);
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(
            state: FlowOverview(List.filled(count, sampleRoute), 0),
            onSteps: () {},
            onStart: () {},
          ),
          textScale: textScale,
        ),
      );
    }

    double maxScroll(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .maxScrollExtent;

    testWidgets('3 routes show without scrolling', (tester) async {
      await pumpRoutes(tester, 3);
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), 0);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('4 routes scroll', (tester) async {
      await pumpRoutes(tester, 4);
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), greaterThan(0));
    });

    testWidgets(
      '3 routes at 2x text scale show without scrolling and do not overflow',
      (tester) async {
        await pumpRoutes(tester, 3, textScale: 2);
        expect(tester.takeException(), isNull);
        expect(maxScroll(tester), 0);
      },
    );

    testWidgets('a 360x360 viewport with 5 routes does not overflow', (
      tester,
    ) async {
      await pumpRoutes(tester, 5, size: const Size(360, 360));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a 1 h 25 min duration is not truncated at 320 dp on the fastest card',
      (tester) async {
        _size(tester, const Size(320, 640));
        final route = NavRoute.fromPoints(
          const [GeoPoint(10.0, 106.0), GeoPoint(10.1, 106.0)],
          summary: 'Highway 1',
          segmentDurations: const [5100],
        );
        final text = _formatter.duration(
          Duration(seconds: route.duration.round()),
        );
        await tester.pumpWidget(
          _host(
            MapboxStyleRoutePanel(
              state: FlowOverview([route, route], 0),
              onSteps: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(text).first)
              .didExceedMaxLines,
          isFalse,
        );
      },
    );

    testWidgets('other states are empty', (tester) async {
      await tester.pumpWidget(
        _host(const MapboxStyleRoutePanel(state: FlowIdle())),
      );
      expect(find.byType(SafeArea), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no overflow at 320 dp with a 150-character summary', (
      tester,
    ) async {
      _size(tester, const Size(320, 640));
      final route = NavRoute.fromPoints(const [
        GeoPoint(10.0, 106.0),
        GeoPoint(10.01, 106.0),
      ], summary: List.filled(150, 'x').join());
      await tester.pumpWidget(
        _host(
          MapboxStyleRoutePanel(
            state: FlowOverview([route, route], 0),
            onSteps: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MapboxStyleStepList', () {
    Future<void> pump(WidgetTester tester, {int currentStep = -1}) async {
      _size(tester, const Size(400, 3000));
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 3000,
            child: MapboxStyleStepList(
              route: sampleRoute,
              currentStep: currentStep,
            ),
          ),
        ),
      );
    }

    testWidgets('one tile per step', (tester) async {
      await pump(tester);
      expect(find.byType(ListTile), findsNWidgets(sampleRoute.steps.length));
      final first = tester.widget<ListTile>(find.byType(ListTile).first);
      expect(
        (first.title! as Text).data,
        _formatter.instruction(sampleRoute.steps[0]),
      );
    });

    testWidgets('the subtitle has the distance and time to the next step', (
      tester,
    ) async {
      await pump(tester);
      final tile = tester.widget<ListTile>(find.byType(ListTile).at(3));
      final subtitle = (tile.subtitle! as Text).data!;
      final step = sampleRoute.steps[3];
      final next = sampleRoute.steps[4].distance;
      expect(
        subtitle,
        '${_formatter.distance(next - step.distance)}'
        ' · ${_formatter.duration(Duration(seconds: (sampleRoute.durationAt(next) - sampleRoute.durationAt(step.distance)).round()))}',
      );
      expect(subtitle, contains('3 min'));
    });

    testWidgets('steps before the current one are dimmed', (tester) async {
      await pump(tester, currentStep: 2);
      double opacityOf(int i) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(ListTile).at(i),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacityOf(0), 0.45);
      expect(opacityOf(1), 0.45);
      expect(
        find.ancestor(
          of: find.byType(ListTile).at(2),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('the current step is highlighted, the others are not', (
      tester,
    ) async {
      await pump(tester, currentStep: 2);
      ListTile tile(int i) =>
          tester.widget<ListTile>(find.byType(ListTile).at(i));
      expect(tile(2).tileColor, isNotNull);
      expect(tile(2).tileColor, isNot(MapboxStyleColors.day.surface));
      expect(tile(3).tileColor, isNull);
      expect(tile(1).tileColor, isNull);
    });

    testWidgets('no step is highlighted before the trip starts', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 0; i < sampleRoute.steps.length; i++) {
        expect(
          tester.widget<ListTile>(find.byType(ListTile).at(i)).tileColor,
          isNull,
        );
      }
    });
  });

  group('MapboxStyleArrivalPanel', () {
    testWidgets('shows the arrival and the last road; done calls back', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        _host(
          MapboxStyleArrivalPanel(route: sampleRoute, onDone: () => done++),
        ),
      );
      expect(find.text('You have arrived'), findsOneWidget);
      expect(find.text('Van Hoa 4'), findsOneWidget);
      expect(find.byIcon(Icons.flag), findsOneWidget);
      await tester.tap(find.text('Done'));
      expect(done, 1);
    });

    testWidgets('without a named road only the message shows', (tester) async {
      final route = NavRoute.fromPoints(const [
        GeoPoint(10.0, 106.0),
        GeoPoint(10.01, 106.0),
      ]);
      await tester.pumpWidget(_host(MapboxStyleArrivalPanel(route: route)));
      expect(find.text('You have arrived'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('2x text at 320 dp', () {
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

    /// The text scale factor [text] is laid out with.
    double scaleOf(WidgetTester tester, String text) =>
        MediaQuery.textScalerOf(tester.element(find.text(text))).scale(10) / 10;

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
      group(name, () {
        Future<void> pump(
          WidgetTester tester,
          Widget child, {
          Alignment alignment = Alignment.bottomCenter,
        }) async {
          _size(tester, const Size(320, 640));
          await tester.pumpWidget(
            _host(child, alignment: alignment, textScale: 2),
          );
        }

        testWidgets('the banner, with lanes and a then-step', (tester) async {
          await pump(
            tester,
            MapboxStyleManeuverBanner(
              state: guidance,
              formatter: formatter,
              strings: strings,
            ),
            alignment: Alignment.topCenter,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('mapbox_style_lane_cell')),
            findsWidgets,
          );
          expect(find.text(strings.then), findsOneWidget);
          expect(
            scaleOf(tester, formatter.distance(1250)),
            1.6,
            reason: 'clamped',
          );
          expect(scaleOf(tester, strings.then), 2, reason: 'not clamped');
        });

        testWidgets('the trip progress, with all buttons', (tester) async {
          await pump(
            tester,
            MapboxStyleTripProgress(
              progress: progress,
              formatter: formatter,
              strings: strings,
              onEnd: () {},
              onSteps: () {},
              onOverview: () {},
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            scaleOf(tester, formatter.duration(progress.remainingDuration)),
            1.6,
            reason: 'clamped',
          );
        });

        testWidgets('the trip progress while rerouting', (tester) async {
          await pump(
            tester,
            MapboxStyleTripProgress(
              progress: progress,
              rerouting: true,
              formatter: formatter,
              strings: strings,
              onEnd: () {},
              onSteps: () {},
              onOverview: () {},
            ),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('the speed limit, with both signs and limit 120', (
          tester,
        ) async {
          for (final sign in SpeedLimitSign.values) {
            await pump(
              tester,
              MapboxStyleSpeedLimit(
                info: SpeedInfo(speed: 130 / 3.6, limit: 120 / 3.6),
                sign: sign,
                strings: strings,
                formatter: formatter,
              ),
            );
            expect(tester.takeException(), isNull, reason: '$sign');
            expect(find.text('130'), findsOneWidget);
            expect(find.text('120'), findsOneWidget);
          }
        });

        testWidgets('the recenter button', (tester) async {
          await pump(
            tester,
            MapboxStyleRecenterButton(onPressed: () {}, strings: strings),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('the route panel, with two routes of 5100 s', (
          tester,
        ) async {
          await pump(
            tester,
            MapboxStyleRoutePanel(
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

        testWidgets('the route panel while loading and on an error', (
          tester,
        ) async {
          final to = sampleRoute.points.last;
          await pump(
            tester,
            MapboxStyleRoutePanel(
              state: FlowLoading(to),
              strings: strings,
              onCancel: () {},
            ),
          );
          expect(tester.takeException(), isNull, reason: 'loading');
          await pump(
            tester,
            MapboxStyleRoutePanel(
              state: FlowError(Exception('offline'), const FlowIdle(), to),
              strings: strings,
              onCancel: () {},
              onRetry: () {},
            ),
          );
          expect(tester.takeException(), isNull, reason: 'error');
          expect(find.text(strings.retry), findsOneWidget);
        });

        testWidgets('the step list', (tester) async {
          await pump(
            tester,
            SizedBox(
              height: 600,
              child: MapboxStyleStepList(
                route: sampleRoute,
                currentStep: 2,
                formatter: formatter,
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('the arrival panel', (tester) async {
          await pump(
            tester,
            MapboxStyleArrivalPanel(
              route: sampleRoute,
              strings: strings,
              onDone: () {},
            ),
          );
          expect(tester.takeException(), isNull);
        });
      });
    }
  });
}
