import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

class _Fixes implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  bool _running = false;
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void dispose() {}
  void add(NavFix fix) => _controller.add(fix);
}

class _PreviewMap implements NavigationMap, RoutePreviewMap {
  @override
  Future<void> moveCamera(CameraTarget target) async {}
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {}
  @override
  void clearRoute() {}
  @override
  void showRouteOptions(List<NavRoute> routes, int selected) {}
  @override
  void clearRouteOptions() {}
  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {}
}

/// What the map builder got at one build.
typedef _MapBuild = ({
  NavigationMapConfig config,
  MapboxStyleColors colors,
  RouteColors routeColors,
  String Function(NavRoute) routeLabel,
});

/// A map that reports itself ready after its first frame.
class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.config});

  final NavigationMapConfig config;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.config.onMapReady(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF808080));
}

void main() {
  final route = sampleRoute;
  final alt = sampleRouteAlternatives.single;
  const formatter = EnglishGuidanceFormatter();
  final teal = MapboxStyleColors.fromColorScheme(
    ColorScheme.fromSeed(seedColor: Colors.teal),
  );

  testWidgets('a smoke run: the pieces per state, and what the map gets', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime.utc(2026, 10, 7, 13);
    final fixes = _Fixes();
    final session = NavigationSession(
      fixes: fixes,
      map: _PreviewMap(),
      clock: () => now,
    );
    final flow = NavigationFlowController(
      session: session,
      nightMode: NightMode.alwaysDay,
      clock: () => now,
    );
    const mine = RouteColors(ahead: Color(0xFF333333));
    final builds = <_MapBuild>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MapboxStyleFlowScaffold(
          session: session,
          flow: flow,
          formatter: formatter,
          dayColors: teal,
          nightRouteColors: mine,
          idleBuilder: (_) => const Text('IDLE'),
          mapBuilder: (context, config, colors, routeColors, routeLabel) {
            builds.add((
              config: config,
              colors: colors,
              routeColors: routeColors,
              routeLabel: routeLabel,
            ));
            return _FakeMap(config: config);
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IDLE'), findsOneWidget);

    // By day: the day colours; route colours from them; durations.
    final day = builds.last;
    expect(day.config.isNight, isFalse);
    expect(day.colors, same(teal));
    expect(day.routeColors.ahead, teal.accent);
    expect(day.routeColors.driven, teal.alternative);
    expect(
      day.routeLabel(alt),
      formatter.duration(Duration(seconds: alt.duration.round())),
    );

    // The overview: Steps but no Retry; a card tap selects.
    flow.previewRoutes([route, alt]);
    await tester.pump();
    final panel = tester.widget<MapboxStyleRoutePanel>(
      find.byType(MapboxStyleRoutePanel),
    );
    expect(panel.colors, same(teal));
    expect(panel.onSteps, isNotNull);
    expect(panel.onRetry, isNull);
    await tester.tap(find.byKey(const ValueKey('route_card_1')));
    await tester.pump();
    expect((flow.state.value as FlowOverview).selected, 1);

    // Navigating: banner, trip progress, speed; the recenter at the bottom
    // end, beside the speed (they do not share a row on 400 dp).
    await tester.tap(find.text('Start'));
    await tester.pump();
    for (var i = 0; i < 4 * 60; i++) {
      if (i % 60 == 0) {
        final s = 500.0 + 10 * (i ~/ 60);
        fixes.add(
          NavFix(
            position: alt.pointAt(s),
            accuracy: 5,
            speed: 10,
            heading: alt.bearingAt(s),
            time: now,
          ),
        );
      }
      now = now.add(const Duration(microseconds: 16667));
      session.tick(1 / 60);
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(flow.state.value, isA<FlowNavigating>());
    expect(find.byType(MapboxStyleManeuverBanner), findsOneWidget);
    expect(find.byType(MapboxStyleTripProgress), findsOneWidget);
    expect(find.byType(MapboxStyleSpeedLimit), findsOneWidget);
    final progress = tester.widget<MapboxStyleTripProgress>(
      find.byType(MapboxStyleTripProgress),
    );
    expect(progress.onEnd, isNotNull);
    expect(progress.onSteps, isNotNull);
    expect(progress.onOverview, isNotNull);
    // The scaffold reads the follow mode on the session's next frames.
    session.follow = false;
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(microseconds: 16667));
      session.tick(1 / 60);
      await tester.pump(const Duration(microseconds: 16667));
    }
    final recenter = tester.getRect(find.byType(MapboxStyleRecenterButton));
    final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
    final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
    expect(recenter.right, closeTo(400 - 16, 1));
    expect(speed.right + 16, lessThanOrEqualTo(recenter.left));
    expect(recenter.bottom, closeTo(footer.top - 16, 1));
    expect(speed.left, closeTo(16, 1));

    // The step sheet on the surface colour.
    await tester.tap(find.byTooltip('Steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapboxStyleStepList), findsOneWidget);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
      teal.surface,
    );
    Navigator.of(tester.element(find.byType(MapboxStyleStepList))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // At night: the night colours, and the night route colours override.
    flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    final night = builds.last;
    expect(night.config.isNight, isTrue);
    expect(night.colors, same(MapboxStyleColors.night));
    expect(night.routeColors, same(mine));
    expect(
      tester
          .widget<MapboxStyleManeuverBanner>(
            find.byType(MapboxStyleManeuverBanner),
          )
          .colors,
      same(MapboxStyleColors.night),
    );

    // End: back to idle.
    await tester.tap(find.byTooltip('Exit navigation'));
    await tester.pump();
    expect(flow.state.value, isA<FlowIdle>());
    expect(find.text('IDLE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  });

  group('safe area', () {
    /// Mounts the scaffold on [size] with [padding] as the view's insets
    /// and [textScale], drives into navigation and stops following.
    /// Unmounts the screen, then disposes the flow (its night timer must
    /// be gone before the pending-timer check) and the session.
    Future<void> Function()? end;

    Future<NavigationSession> drive(
      WidgetTester tester, {
      required Size size,
      required FakeViewPadding padding,
      double textScale = 1,
      GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
      NavigationStrings strings = const NavigationStrings(),
      bool navigate = true,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = padding
        ..viewPadding = padding;
      addTearDown(tester.view.reset);
      var now = DateTime.utc(2026, 10, 7, 13);
      final fixes = _Fixes();
      final session = NavigationSession(
        fixes: fixes,
        map: _PreviewMap(),
        clock: () => now,
      );
      final flow = NavigationFlowController(
        session: session,
        nightMode: NightMode.alwaysDay,
        clock: () => now,
      );
      end = () async {
        await tester.pumpWidget(const SizedBox());
        flow.dispose();
        session.dispose();
      };
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: MapboxStyleFlowScaffold(
            session: session,
            flow: flow,
            formatter: formatter,
            strings: strings,
            mapBuilder: (context, config, colors, routeColors, routeLabel) =>
                _FakeMap(config: config),
          ),
        ),
      );
      await tester.pump();
      Future<void> frames(int n, {double? at}) async {
        for (var i = 0; i < n; i++) {
          if (at != null && i % 60 == 0) {
            final s = at + 10 * (i ~/ 60);
            fixes.add(
              NavFix(
                position: route.pointAt(s),
                accuracy: 5,
                speed: 10,
                heading: route.bearingAt(s),
                time: now,
              ),
            );
          }
          now = now.add(const Duration(microseconds: 16667));
          session.tick(1 / 60);
          await tester.pump(const Duration(microseconds: 16667));
        }
      }

      if (navigate) {
        flow.previewRoutes([route]);
        await tester.pump();
        await tester.tap(find.text(strings.start));
        await tester.pump();
        await frames(4 * 60, at: 500);
        expect(flow.state.value, isA<FlowNavigating>());
      }
      session.follow = false;
      // The scaffold reads the follow mode on the session's frames, and on
      // a touch on the map (when idle there are no frames).
      if (!navigate) await tester.tapAt(Offset(size.width / 2, 100));
      await frames(4);
      return session;
    }

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
      for (final scale in [1.0, 1.3]) {
        testWidgets('844x390 landscape with insets, ${scale}x text, $name', (
          tester,
        ) async {
          final session = await drive(
            tester,
            size: const Size(844, 390),
            padding: const FakeViewPadding(left: 47, right: 47, bottom: 21),
            textScale: scale,
            formatter: formatter,
            strings: strings,
          );
          expect(tester.takeException(), isNull);
          const safe = Rect.fromLTRB(47, 0, 844 - 47, 390 - 21);
          final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
          final recenter = tester.getRect(
            find.byType(MapboxStyleRecenterButton),
          );
          final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
          final banner = tester.getRect(find.byType(MapboxStyleManeuverBanner));
          bool inside(Rect r) =>
              r.left >= safe.left - 0.5 &&
              r.top >= safe.top - 0.5 &&
              r.right <= safe.right + 0.5 &&
              r.bottom <= safe.bottom + 0.5;
          expect(inside(speed), isTrue, reason: 'speed $speed');
          expect(inside(recenter), isTrue, reason: 'recenter $recenter');
          expect(recenter.height, greaterThanOrEqualTo(48));
          expect(recenter.overlaps(speed), isFalse, reason: '$recenter');
          expect(recenter.overlaps(footer), isFalse, reason: '$recenter');
          expect(recenter.overlaps(banner), isFalse, reason: '$recenter');
          expect(speed.overlaps(footer), isFalse, reason: '$speed');
          expect(speed.overlaps(banner), isFalse, reason: '$speed');
          expect(session.follow, isFalse);
          await end!();
        });
      }
    }

    testWidgets('320x480 at 2x text: the recenter keeps its touch target', (
      tester,
    ) async {
      await drive(
        tester,
        size: const Size(320, 480),
        padding: const FakeViewPadding(),
        textScale: 2,
      );
      final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
      final recenter = tester.getRect(find.byType(MapboxStyleRecenterButton));
      final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
      expect(recenter.height, greaterThanOrEqualTo(48));
      expect(recenter.overlaps(speed), isFalse, reason: '$recenter $speed');
      expect(recenter.overlaps(footer), isFalse, reason: '$recenter');
      expect(recenter.left, greaterThanOrEqualTo(0));
      expect(recenter.right, lessThanOrEqualTo(320));
      expect(recenter.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      await end!();
    });

    testWidgets('portrait: the idle recenter keeps above the bottom inset', (
      tester,
    ) async {
      await drive(
        tester,
        size: const Size(390, 844),
        padding: const FakeViewPadding(top: 47, bottom: 34),
        navigate: false,
      );
      final recenter = tester.getRect(find.byType(MapboxStyleRecenterButton));
      expect(recenter.bottom, lessThanOrEqualTo(844 - 34 - 16));
      expect(recenter.right, lessThanOrEqualTo(390 - 16));
      expect(tester.takeException(), isNull);
      await end!();
    });
  });
}
