// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_flutter_map/navigation_engine_flutter_map.dart';
import 'package:navigation_engine_flutter_map/src/flutter_map_navigation_map.dart'
    show toLatLng;

class FakeFixSource implements FixSource {
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

/// A provider whose every request waits on [pending], recording each
/// `from` and `to`.
class PendingRouteProvider extends RouteProvider {
  final requests = <GeoPoint>[];
  final origins = <GeoPoint>[];
  Completer<List<NavRoute>> pending = Completer();

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) =>
      throw UnimplementedError();

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) {
    requests.add(to);
    origins.add(from);
    pending = Completer();
    return pending.future;
  }
}

/// Counts the overview refreshes (the map's ready hook).
class CountingFlow extends NavigationFlowController {
  CountingFlow({
    required super.session,
    super.routeProvider,
    super.nightMode,
    super.clock,
  });

  var refreshes = 0;

  @override
  void refreshOverview() {
    refreshes++;
    super.refreshOverview();
  }
}

const _seeded = Colors.teal;

/// The app's theme in these tests.
final _theme = ThemeData(colorSchemeSeed: _seeded);

/// The colours [NeutralNavigation] derives from [_theme] by day.
final _day = MapboxStyleColors.fromColorScheme(_theme.colorScheme);

/// The colours it derives from [_theme] at night: the dark scheme of the
/// same seed.
final _night = MapboxStyleColors.fromColorScheme(
  ColorScheme.fromSeed(
    seedColor: _theme.colorScheme.primary,
    brightness: Brightness.dark,
  ),
);

/// The fields of [c], to compare two sets of colours.
List<Color> _fields(MapboxStyleColors c) => [
  c.banner,
  c.bannerSecondary,
  c.onBanner,
  c.surface,
  c.onSurface,
  c.onSurfaceVariant,
  c.accent,
  c.onAccent,
  c.alternative,
  c.etaText,
  c.warning,
  c.end,
];

/// A 1x1 transparent PNG, for the engine-free pin painters.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<Uint8List> _fakeSearchPin({
  required bool focused,
  required double pixelRatio,
  required Color color,
}) async => _png;

Future<Uint8List> _fakeDestinationPin({required double pixelRatio}) async =>
    _png;

/// A session and a flow on a fake clock, and the drop-in on a 400x800
/// surface.
class Harness {
  Harness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.alwaysDay,
  }) {
    session = NavigationSession(
      fixes: source,
      routeProvider: provider,
      clock: () => now,
    );
    flow = CountingFlow(
      session: session,
      routeProvider: provider,
      nightMode: nightMode,
      clock: () => now,
    );
  }

  final source = FakeFixSource();
  late final NavigationSession session;
  late final CountingFlow flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);
  final formatter = const EnglishGuidanceFormatter();

  FlutterMapNavigationMap get map => session.map! as FlutterMapNavigationMap;

  /// The route indexes of the option lines on the map.
  Set<Object> get optionIndexes => {
    for (final l in map.routeOptionLines.value) l.hitValue!,
  };

  Widget app({
    WidgetBuilder? idleBuilder,
    VoidCallback? onEnd,
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    MapboxStyleColors? dayColors,
    MapboxStyleColors? nightColors,
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    double focus = 0.7,
    double initialZoom = 17,
    String? nightTileUrlTemplate,
    TextScaler? textScaler,
    ThemeData? theme,
    bool pushed = false,
    void Function(fm.MapController controller)? onMapReady,
    List<Widget> children = const [],
    String? attribution,
    void Function(GeoPoint point)? onMapTap,
    void Function(GeoPoint point)? onMapLongPress,
  }) {
    final screen = NeutralNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      userAgentPackageName: 'dev.navigationengine.test',
      tileUrlTemplate: 'day/{z}',
      nightTileUrlTemplate: nightTileUrlTemplate,
      idleBuilder: idleBuilder,
      onEnd: onEnd,
      formatter: formatter,
      strings: strings,
      dayColors: dayColors,
      nightColors: nightColors,
      dayRouteColors: dayRouteColors,
      nightRouteColors: nightRouteColors,
      puck: puck,
      focus: focus,
      initialZoom: initialZoom,
      onMapReady: onMapReady,
      attribution: attribution ?? 'OpenStreetMap contributors',
      onMapTap: onMapTap,
      onMapLongPress: onMapLongPress,
      children: children,
    );
    return MaterialApp(
      theme: theme ?? _theme,
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      // Pushed over a home page, so a back can pop it.
      home: pushed
          ? Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                  child: const Text('HOME'),
                ),
              ),
            )
          : screen,
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    WidgetBuilder? idleBuilder,
    VoidCallback? onEnd,
    Size size = const Size(400, 800),
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    MapboxStyleColors? dayColors,
    MapboxStyleColors? nightColors,
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    double focus = 0.7,
    double initialZoom = 17,
    String? nightTileUrlTemplate,
    TextScaler? textScaler,
    ThemeData? theme,
    bool pushed = false,
    void Function(fm.MapController controller)? onMapReady,
    List<Widget> children = const [],
    String? attribution,
    void Function(GeoPoint point)? onMapTap,
    void Function(GeoPoint point)? onMapLongPress,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        idleBuilder: idleBuilder,
        onEnd: onEnd,
        formatter: formatter,
        strings: strings,
        dayColors: dayColors,
        nightColors: nightColors,
        dayRouteColors: dayRouteColors,
        nightRouteColors: nightRouteColors,
        puck: puck,
        focus: focus,
        initialZoom: initialZoom,
        nightTileUrlTemplate: nightTileUrlTemplate,
        textScaler: textScaler,
        theme: theme,
        pushed: pushed,
        onMapReady: onMapReady,
        children: children,
        attribution: attribution,
        onMapTap: onMapTap,
        onMapLongPress: onMapLongPress,
      ),
    );
    // Engine-free pins: the real painters render through the engine.
    if (session.map case final FlutterMapNavigationMap map) {
      map
        ..pinPainter = _fakeSearchPin
        ..destinationPinPainter = _fakeDestinationPin;
    }
    if (pushed) {
      await tester.tap(find.text('HOME'));
      // No pumpAndSettle: the map frame's ticker always schedules a frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump();
  }

  NavFix fixOn(NavRoute route, double s, {double speed = 10}) => NavFix(
    position: route.pointAt(s),
    accuracy: 5,
    speed: speed,
    heading: route.bearingAt(s),
    time: now,
  );

  /// Runs [seconds] of 16 ms frames; [fixAt] may return a fix each second.
  /// The frame of the view ticks the session.
  Future<void> run(
    WidgetTester tester,
    double seconds, {
    NavFix? Function(int second)? fixAt,
  }) async {
    final frames = (seconds * 60).round();
    for (var i = 0; i < frames; i++) {
      if (i % 60 == 0) {
        final fix = fixAt?.call(i ~/ 60);
        if (fix != null) source.add(fix);
      }
      now = now.add(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Starts the trip from the overview (its button reads [start]) and
  /// drives 4 s from 500 m.
  Future<void> startDriving(
    WidgetTester tester, {
    String start = 'Start',
  }) async {
    await tester.tap(find.text(start));
    await tester.pump();
    await run(
      tester,
      4,
      fixAt: (s) => fixOn(sampleRoute, 500.0 + 10 * s, speed: 10),
    );
  }

  /// Unmounts the widget and disposes the flow (its night timer must be gone
  /// before the pending-timer check, which precedes tearDown) and the
  /// session.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  }
}

/// A widget test with a [Harness] that is always cleaned up.
void navTest(
  String description,
  Future<void> Function(WidgetTester tester, Harness h) body, {
  RouteProvider? Function()? provider,
  NightMode nightMode = NightMode.alwaysDay,
}) {
  testWidgets(description, (tester) async {
    final h = Harness(provider: provider?.call(), nightMode: nightMode);
    try {
      await body(tester, h);
    } finally {
      await h.end(tester);
    }
  });
}

void main() {
  final route = sampleRoute;
  final alt = sampleRouteAlternatives.single;

  Finder card(int i) => find.byKey(ValueKey('route_card_$i'));

  Color materialColor(WidgetTester tester, Type piece) => tester
      .widget<Material>(
        find
            .descendant(of: find.byType(piece), matching: find.byType(Material))
            .first,
      )
      .color!;

  navTest('idle shows the idle overlay only', (tester, h) async {
    await h.mount(tester, idleBuilder: (_) => const Text('IDLE'));
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.byType(FlutterMapNavigationView), findsOneWidget);
    expect(find.byType(MapboxStyleRoutePanel), findsNothing);
    expect(find.byType(MapboxStyleManeuverBanner), findsNothing);
    expect(find.byType(MapboxStyleTripProgress), findsNothing);
  });

  navTest('overview shows the panel and draws route options', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    expect(find.byType(MapboxStyleRoutePanel), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(card(0), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(card(2), findsNothing);
    expect(h.optionIndexes, {0, 1});
    // The labels read the route durations, through the formatter.
    final bubbles = tester
        .widgetList<RouteLabelBubble>(find.byType(RouteLabelBubble))
        .map((b) => b.text);
    expect(
      bubbles,
      containsAll([
        for (final r in [route, alt])
          h.formatter.duration(Duration(seconds: r.duration.round())),
      ]),
    );

    await tester.tap(card(1));
    await tester.pump();
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('tapping a route option on the map selects it', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final other = find.byWidgetPredicate(
      (w) => w is RouteLabelBubble && !w.selected,
    );
    expect(other, findsOneWidget);
    await tester.tap(other);
    await tester.pump(const Duration(milliseconds: 400));
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('the map ready hook refreshes the overview', (tester, h) async {
    h.flow.previewRoutes([route, alt]);
    expect(h.flow.refreshes, 0);
    await h.mount(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.refreshes, greaterThanOrEqualTo(1));
    expect(h.optionIndexes, {0, 1});
  });

  navTest('start shows banner, trip progress and speed while driving', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    // No guidance yet right after start: no banner, not an empty card.
    expect(h.session.guidanceState, isNull);
    expect(find.byType(MapboxStyleManeuverBanner), findsNothing);
    expect(find.byType(MapboxStyleTripProgress), findsOneWidget);
    await h.run(
      tester,
      4,
      fixAt: (s) => h.fixOn(route, 500.0 + 10 * s, speed: 10),
    );
    expect(h.flow.state.value, isA<FlowNavigating>());
    expect(find.byType(MapboxStyleRoutePanel), findsNothing);
    expect(find.byType(MapboxStyleManeuverBanner), findsOneWidget);
    expect(find.byType(MapboxStyleTripProgress), findsOneWidget);
    expect(find.byType(MapboxStyleSpeedLimit), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MapboxStyleTripProgress),
        matching: find.text(
          h.formatter.duration(h.flow.tripProgress.value!.remainingDuration),
        ),
      ),
      findsOneWidget,
    );
    expect(h.optionIndexes, isEmpty, reason: 'options cleared on start');
  });

  navTest('recenter at the bottom end, the speed at the bottom start', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    expect(find.byType(MapboxStyleRecenterButton), findsNothing);
    h.session.follow = false;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final button = tester.getRect(find.byType(MapboxStyleRecenterButton));
    final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
    final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
    expect(button.right, closeTo(400 - 16, 1));
    // They do not share a row on 400 dp: the button sits beside the speed,
    // above the footer (final review I3).
    expect(speed.right + 16, lessThanOrEqualTo(button.left));
    expect(button.bottom, closeTo(footer.top - 16, 1));
    expect(speed.left, closeTo(16, 1));
    expect(speed.bottom, closeTo(footer.top - 16, 1));
    // The view's own recenter button is hidden: only the scaffold's shows.
    expect(find.byTooltip('Recenter'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('Re-center'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.session.follow, isTrue);
  });

  navTest('end exits to idle', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    await tester.tap(find.byTooltip('Exit navigation'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    expect(h.session.isRunning, isFalse);
    expect(find.byType(MapboxStyleTripProgress), findsNothing);

    // With onEnd, the callback is called instead.
    var ended = 0;
    await tester.pumpWidget(h.app(onEnd: () => ended++));
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    await tester.tap(find.byTooltip('Exit navigation'));
    await tester.pump();
    expect(ended, 1);
    expect(h.flow.state.value, isA<FlowNavigating>());
    expect(h.session.isRunning, isTrue);
  });

  navTest('overview button goes back to the trip overview, Resume continues', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    final running = h.session.route;
    await tester.tap(find.byTooltip('Overview'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowNavigating>());
    expect(h.session.route, same(running));
  });

  navTest('steps opens the step list', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    await tester.tap(find.byTooltip('Steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapboxStyleStepList), findsOneWidget);
    final list = tester.widget<MapboxStyleStepList>(
      find.byType(MapboxStyleStepList),
    );
    expect(list.route, same(route));
    expect(list.currentStep, h.session.guidanceState!.stepIndex);
    expect(_fields(list.colors), _fields(_day));
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, _day.surface);
  });

  navTest('arrival shows the panel; Done stops', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await h.run(
      tester,
      8,
      fixAt: (s) => h.fixOn(route, route.length - 40 + 8.0 * s, speed: 8),
    );
    expect(h.flow.state.value, isA<FlowArrived>());
    expect(find.byType(MapboxStyleArrivalPanel), findsOneWidget);
    expect(find.byType(MapboxStyleTripProgress), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    expect(h.session.isRunning, isFalse);
    expect(find.byType(MapboxStyleArrivalPanel), findsNothing);
  });

  late PendingRouteProvider pendingProvider;
  navTest('loading, error, retry and cancel', (tester, h) async {
    final provider = pendingProvider;
    await h.mount(tester);
    final from = route.pointAt(2000);
    final to = route.points.last;
    unawaited(h.flow.preview(from: from, to: to));
    await tester.pump();
    expect(find.text('Finding routes…'), findsOneWidget);

    provider.pending.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();
    expect(h.flow.state.value, isA<FlowError>());
    expect(find.text('No route found'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowLoading>());
    expect(find.text('Finding routes…'), findsOneWidget);
    expect(provider.requests, [to, to]);
    expect(provider.origins, [from, from], reason: 'the same trip');

    provider.pending.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No route found'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    expect(find.byType(MapboxStyleRoutePanel), findsNothing);

    // Cancel while loading too.
    unawaited(h.flow.preview(from: from, to: to));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowLoading>());
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
  }, provider: () => pendingProvider = PendingRouteProvider());

  navTest('a back in a preview returns to idle without popping', (
    tester,
    h,
  ) async {
    await h.mount(tester, pushed: true);
    h.session.start();
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    expect(h.session.isRunning, isTrue);
    expect(find.byType(NeutralNavigation), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    // Idle: a back pops the screen.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NeutralNavigation), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  navTest('night switches the tiles and colours without recreating the map', (
    tester,
    h,
  ) async {
    await h.mount(tester, nightTileUrlTemplate: 'night/{z}');
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    String tiles() =>
        tester.widget<fm.TileLayer>(find.byType(fm.TileLayer)).urlTemplate!;
    final adapter = h.map;
    final mapState = tester.state(find.byType(fm.FlutterMap));
    expect(tiles(), 'day/{z}');
    expect(materialColor(tester, MapboxStyleTripProgress), _day.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), _day.banner);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tiles(), 'night/{z}');
    expect(h.map, same(adapter), reason: 'the same view');
    expect(tester.state(find.byType(fm.FlutterMap)), same(mapState));
    expect(materialColor(tester, MapboxStyleTripProgress), _night.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), _night.banner);
    expect(h.map.routeColors.ahead, _night.accent);
    expect(h.flow.state.value, isA<FlowNavigating>());

    h.flow.nightMode = NightMode.alwaysDay;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tiles(), 'day/{z}');
    expect(h.map, same(adapter));
    expect(materialColor(tester, MapboxStyleTripProgress), _day.surface);
  });

  group('the theme', () {
    navTest('the banner takes its colour from the app theme', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      expect(
        materialColor(tester, MapboxStyleManeuverBanner),
        MapboxStyleColors.fromColorScheme(_theme.colorScheme).banner,
      );
      final banner = tester.widget<MapboxStyleManeuverBanner>(
        find.byType(MapboxStyleManeuverBanner),
      );
      expect(_fields(banner.colors), _fields(_day));
    });

    navTest('another theme gives other colours', (tester, h) async {
      final orange = ThemeData(colorSchemeSeed: Colors.orange);
      await h.mount(tester, theme: orange);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      final colors = MapboxStyleColors.fromColorScheme(orange.colorScheme);
      expect(colors.accent, isNot(_day.accent));
      expect(
        _fields(
          tester
              .widget<MapboxStyleRoutePanel>(find.byType(MapboxStyleRoutePanel))
              .colors,
        ),
        _fields(colors),
      );
      expect(h.map.routeColors.ahead, colors.accent);
    });

    navTest('by day the map uses the day colours', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(h.map.routeColors.ahead, _day.accent);
      expect(h.map.routeColors.driven, _day.alternative);
      expect(h.map.alternativeColor, _day.alternative);
      expect(h.map.labelColors, _day.routeLabelColors);
      final lines = h.map.routeOptionLines.value;
      expect(lines.last.color, _day.accent, reason: 'the selected line');
    });

    navTest('at night: the dark scheme of the same seed', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(_night.banner, isNot(_day.banner));
      expect(
        _fields(
          tester
              .widget<MapboxStyleRoutePanel>(find.byType(MapboxStyleRoutePanel))
              .colors,
        ),
        _fields(_night),
      );
      expect(h.map.routeColors.ahead, _night.accent);
      expect(h.map.routeColors.driven, _night.alternative);
      expect(h.map.alternativeColor, _night.alternative);
      expect(h.map.labelColors, _night.routeLabelColors);
    }, nightMode: NightMode.alwaysNight);

    navTest('dayColors and nightColors override the theme', (tester, h) async {
      await h.mount(
        tester,
        dayColors: MapboxStyleColors.day,
        nightColors: MapboxStyleColors.night,
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      expect(
        materialColor(tester, MapboxStyleManeuverBanner),
        MapboxStyleColors.day.banner,
      );
      h.flow.nightMode = NightMode.alwaysNight;
      await tester.pump();
      expect(
        materialColor(tester, MapboxStyleManeuverBanner),
        MapboxStyleColors.night.banner,
      );
    });

    navTest('nightRouteColors override the night default', (tester, h) async {
      const mine = RouteColors(
        driven: Color(0xFF111111),
        ahead: Color(0xFF222222),
      );
      await h.mount(tester, nightRouteColors: mine);
      h.flow.previewRoutes([route]);
      await tester.pump();
      expect(h.map.routeColors, same(mine));
    }, nightMode: NightMode.alwaysNight);

    navTest('dayRouteColors override the day default', (tester, h) async {
      const mine = RouteColors(ahead: Color(0xFF333333));
      await h.mount(tester, dayRouteColors: mine);
      h.flow.previewRoutes([route]);
      await tester.pump();
      expect(h.map.routeColors, same(mine));
      expect(h.map.routeOptionLines.value.last.color, mine.ahead);
    });
  });

  navTest('focus, puck, initialZoom and the tiles are forwarded', (
    tester,
    h,
  ) async {
    const puck = CarPuck(size: 30);
    await h.mount(
      tester,
      puck: puck,
      focus: 0.5,
      initialZoom: 15,
      nightTileUrlTemplate: 'night/{z}',
    );
    final view = tester.widget<FlutterMapNavigationView>(
      find.byType(FlutterMapNavigationView),
    );
    expect(view.puck, same(puck));
    expect(view.focus, 0.5);
    expect(view.initialZoom, 15);
    expect(view.userAgentPackageName, 'dev.navigationengine.test');
    expect(view.tileUrlTemplate, 'day/{z}');
    expect(view.nightTileUrlTemplate, 'night/{z}');
    expect(view.night, isFalse);
  });

  test('the tiles default to OpenStreetMap', () {
    final session = NavigationSession(fixes: FakeFixSource());
    addTearDown(session.dispose);
    final flow = NavigationFlowController(
      session: session,
      nightMode: NightMode.alwaysDay,
    );
    addTearDown(flow.dispose);
    final screen = NeutralNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      userAgentPackageName: 'dev.navigationengine.test',
    );
    expect(
      screen.tileUrlTemplate,
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    expect(screen.nightTileUrlTemplate, isNull);
    expect(screen.dayColors, isNull);
    expect(screen.nightColors, isNull);
    expect(screen.focus, 0.7);
    expect(screen.initialZoom, 17);
  });

  navTest('onMapReady gets the controller after the overview refresh', (
    tester,
    h,
  ) async {
    h.flow.previewRoutes([route, alt]);
    final calls = <(fm.MapController, int)>[];
    await h.mount(tester, onMapReady: (c) => calls.add((c, h.flow.refreshes)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls, hasLength(1));
    expect(calls.single.$1, same(h.map.controller));
    expect(calls.single.$2, 1, reason: 'config.onMapReady runs first');
  });

  navTest('the app children are drawn on the map', (tester, h) async {
    await h.mount(
      tester,
      children: const [SizedBox(key: ValueKey('app_layer'))],
    );
    expect(
      find.descendant(
        of: find.byType(fm.FlutterMap),
        matching: find.byKey(const ValueKey('app_layer')),
      ),
      findsOneWidget,
    );
  });

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
    navTest('2x text on 320 dp ($name): no overflow', (tester, h) async {
      await h.mount(
        tester,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        formatter: formatter,
        strings: strings,
      );
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overview');
      await h.startDriving(tester, start: strings.start);
      expect(h.flow.state.value, isA<FlowNavigating>());
      expect(find.byType(MapboxStyleManeuverBanner), findsOneWidget);
      expect(find.byType(MapboxStyleTripProgress), findsOneWidget);
      expect(find.byType(MapboxStyleSpeedLimit), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'navigating');
      h.session.follow = false;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(MapboxStyleRecenterButton), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'recenter');
      final recenterRect = tester.getRect(
        find.byType(MapboxStyleRecenterButton),
      );
      final speedRect = tester.getRect(find.byType(MapboxStyleSpeedLimit));
      expect(recenterRect.overlaps(speedRect), isFalse);
    });
  }

  navTest('844x390 landscape with insets at 1.3x text (I3)', (tester, h) async {
    const insets = FakeViewPadding(left: 47, right: 47, bottom: 21);
    tester.view
      ..padding = insets
      ..viewPadding = insets;
    await h.mount(
      tester,
      size: const Size(844, 390),
      textScaler: const TextScaler.linear(1.3),
      formatter: const VietnameseGuidanceFormatter(),
      strings: const NavigationStrings.vietnamese(),
    );
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(
      tester,
      start: const NavigationStrings.vietnamese().start,
    );
    h.session.follow = false;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    const safe = Rect.fromLTRB(47, 0, 844 - 47, 390 - 21);
    final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
    final recenter = tester.getRect(find.byType(MapboxStyleRecenterButton));
    final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
    for (final r in [speed, recenter]) {
      expect(safe.inflate(0.5).contains(r.topLeft), isTrue, reason: '$r');
      expect(safe.inflate(0.5).contains(r.bottomRight), isTrue, reason: '$r');
    }
    expect(recenter.height, greaterThanOrEqualTo(48));
    expect(recenter.overlaps(speed), isFalse);
    expect(recenter.overlaps(footer), isFalse);
    expect(
      tester.getRect(find.byTooltip('Attributions')).left,
      greaterThanOrEqualTo(47),
    );
  });

  navTest('route labels at 2x text fit their marker (M5)', (tester, h) async {
    await h.mount(tester, textScaler: const TextScaler.linear(2));
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final bubbles = find.byType(RouteLabelBubble);
    expect(bubbles, findsNWidgets(2));
    for (final bubble in bubbles.evaluate()) {
      final finder = find.byWidget(bubble.widget);
      final rect = tester.getRect(finder);
      // The marker's box: the Align the marker puts the bubble in.
      final box = tester.getRect(
        find.ancestor(of: finder, matching: find.byType(Align)).first,
      );
      expect(rect.left, greaterThanOrEqualTo(box.left), reason: '$rect $box');
      expect(rect.right, lessThanOrEqualTo(box.right), reason: '$rect $box');
      final text = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
      expect(text.didExceedMaxLines, isFalse);
      // Not clipped: the text has the room it asks for.
      expect(
        text.size.width,
        greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity) - 0.5),
      );
    }
    expect(tester.takeException(), isNull);
  });

  group('attribution (final review I4)', () {
    /// The attribution's button, which stays on the map.
    Rect attribution(WidgetTester tester) =>
        tester.getRect(find.byTooltip('Attributions'));

    navTest('stays above the route panel and the trip progress', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(attribution(tester).bottom, closeTo(800, 8), reason: 'idle');

      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final panel = tester.getRect(find.byType(MapboxStyleRoutePanel));
      expect(
        attribution(tester).bottom,
        lessThanOrEqualTo(panel.top),
        reason: 'overview: ${attribution(tester)} $panel',
      );

      await h.startDriving(tester);
      final footer = tester.getRect(find.byType(MapboxStyleTripProgress));
      expect(
        attribution(tester).bottom,
        lessThanOrEqualTo(footer.top),
        reason: 'navigating: ${attribution(tester)} $footer',
      );
      // Not under the speed sign either (re-review R1).
      final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
      expect(
        attribution(tester).overlaps(speed),
        isFalse,
        reason: 'navigating: ${attribution(tester)} $speed',
      );
      expect(tester.takeException(), isNull);
    });

    navTest('keeps its state (an open popup) when the inset comes and goes', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      final idle = tester.state(find.byType(fm.RichAttributionWidget));
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        attribution(tester).bottom,
        lessThan(800 - 8),
        reason: 'the inset is above 0',
      );
      expect(
        tester.state(find.byType(fm.RichAttributionWidget)),
        same(idle),
        reason: 'not remounted',
      );
      h.flow.closeOverview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.state(find.byType(fm.RichAttributionWidget)), same(idle));
    });

    navTest('NeutralNavigation(attribution:) shows the app\'s text', (
      tester,
      h,
    ) async {
      await h.mount(tester, attribution: 'X');
      expect(find.text('© X'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsNothing);
    });
  });

  group('map taps, pins and alternates (SP6)', () {
    navTest('map taps and long presses reach the app', (tester, h) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      void onTap(GeoPoint p) => taps.add(p);
      void onPress(GeoPoint p) => presses.add(p);
      await h.mount(tester, onMapTap: onTap, onMapLongPress: onPress);
      final view = tester.widget<FlutterMapNavigationView>(
        find.byType(FlutterMapNavigationView),
      );
      expect(view.onMapTap, same(onTap));
      expect(view.onMapLongPress, same(onPress));

      const at = Offset(200, 300);
      final expected = h.map.controller.camera.screenOffsetToLatLng(at);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(Duration.zero);
      expect(taps, hasLength(1));
      expect(taps.single.lat, closeTo(expected.latitude, 1e-9));
      expect(taps.single.lng, closeTo(expected.longitude, 1e-9));
      await tester.longPressAt(at);
      await tester.pump();
      expect(presses, hasLength(1));
      expect(taps, hasLength(1));
    });

    navTest('a tap on a route option selects it and is no map tap', (
      tester,
      h,
    ) async {
      final taps = <GeoPoint>[];
      await h.mount(tester, onMapTap: taps.add);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(
        find.byWidgetPredicate((w) => w is RouteLabelBubble && !w.selected),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(Duration.zero);
      expect((h.flow.state.value as FlowOverview).selected, 1);
      expect(taps, isEmpty);
    });

    navTest('the overview pins the destination; stop removes it', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      expect(h.map, isA<DestinationPinMap>());
      expect(h.map, isA<SearchPinsMap>());
      expect(h.map, isA<AlternateRoutesMap>());
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.map.destinationPin.value?.point, toLatLng(route.points.last));

      h.flow.stop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.map.destinationPin.value, isNull);
    });

    navTest('alternates and pins use the screen\'s words and the theme\'s '
        'colours', (tester, h) async {
      await h.mount(tester);
      AlternateRoute a(int minutes) => AlternateRoute(
        route: alt,
        timeDelta: Duration(minutes: minutes),
        divergence: 0,
      );
      const strings = NavigationStrings();
      final label = h.map.alternateLabel!;
      expect(label(a(-2)), strings.minFaster(2));
      expect(label(a(3)), strings.minSlower(3));
      expect(label(a(0)), strings.similarEta);
      expect(h.map.alternateColor, _day.alternative);
      expect(h.map.pinColor, _day.warning);
      expect(h.map.fasterLabelColors.text, _day.accent);
      expect(h.map.fasterLabelColors.fill, _day.surface);
      expect(h.map.slowerLabelColors.text, _day.onSurfaceVariant);

      h.flow.nightMode = NightMode.alwaysNight;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.map.alternateColor, _night.alternative);
      expect(h.map.pinColor, _night.warning);
      expect(h.map.fasterLabelColors.text, _night.accent);
      expect(h.map.slowerLabelColors.text, _night.onSurfaceVariant);
    });

    navTest('the screen\'s strings word the alternate bubbles', (
      tester,
      h,
    ) async {
      await h.mount(tester, strings: const NavigationStrings.vietnamese());
      final label = h.map.alternateLabel!;
      expect(
        label(
          AlternateRoute(
            route: alt,
            timeDelta: const Duration(minutes: -4),
            divergence: 0,
          ),
        ),
        const NavigationStrings.vietnamese().minFaster(4),
      );
    });
  });
}
