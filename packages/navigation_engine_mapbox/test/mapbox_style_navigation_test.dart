import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';

import 'support/fake_mapbox_view.dart';

typedef _Map = MapboxNavigationMap;

const _dayStyle = 'mapbox://styles/example/day';
const _nightStyle = 'mapbox://styles/example/night';

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

/// Renders a label as `<text>` bytes, without the engine.
Future<Uint8List> _painter(
  String text, {
  required bool selected,
  required double pixelRatio,
  required RouteLabelColors colors,
}) async => Uint8List.fromList(text.codeUnits);

/// The vehicle image, without the engine.
Future<Uint8List> _vehicle(double ratio) async => Uint8List(4);

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

/// A session and a flow on a fake clock, the fake Mapbox view on the
/// recording backend, and the drop-in on a 400x800 surface.
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

  final views = FakeMapboxViews();
  final source = FakeFixSource();
  late final NavigationSession session;
  late final CountingFlow flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);
  final formatter = const EnglishGuidanceFormatter();

  MapboxNavigationMap get map => session.map! as MapboxNavigationMap;

  /// The option line layers in the style (not the casings or labels).
  List<String> get optionLines => [
    for (final id in views.backend.layerIds)
      if (id.startsWith(_Map.optionPrefix) &&
          !id.startsWith('${_Map.optionPrefix}casing_') &&
          id != _Map.optionLabels)
        id,
  ];

  /// The light preset set on the Standard style.
  Object? get lightPreset =>
      views.backend.config[(_Map.basemapImport, 'lightPreset')];

  Widget app({
    WidgetBuilder? idleBuilder,
    VoidCallback? onEnd,
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    MapboxStyleColors dayColors = MapboxStyleColors.day,
    MapboxStyleColors nightColors = MapboxStyleColors.night,
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    VehicleImageBuilder vehicleImage = _vehicle,
    double focus = 0.7,
    double initialZoom = 17,
    String styleUri = mb.MapboxStyles.STANDARD,
    String? nightStyleUri,
    TextScaler? textScaler,
    bool pushed = false,
    void Function(mb.MapboxMap map)? onMapCreated,
  }) {
    final screen = MapboxStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      styleUri: styleUri,
      nightStyleUri: nightStyleUri,
      idleBuilder: idleBuilder,
      onEnd: onEnd,
      formatter: formatter,
      strings: strings,
      dayColors: dayColors,
      nightColors: nightColors,
      dayRouteColors: dayRouteColors,
      nightRouteColors: nightRouteColors,
      puck: puck,
      vehicleImage: vehicleImage,
      focus: focus,
      initialZoom: initialZoom,
      onMapCreated: onMapCreated,
      mapViewBuilder: views.build,
    );
    return MaterialApp(
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

  /// Mounts the drop-in; the map is created, and (with [loadStyle]) the
  /// style loads.
  Future<void> mount(
    WidgetTester tester, {
    WidgetBuilder? idleBuilder,
    VoidCallback? onEnd,
    Size size = const Size(400, 800),
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    MapboxStyleColors dayColors = MapboxStyleColors.day,
    MapboxStyleColors nightColors = MapboxStyleColors.night,
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    VehicleImageBuilder vehicleImage = _vehicle,
    double focus = 0.7,
    double initialZoom = 17,
    String styleUri = mb.MapboxStyles.STANDARD,
    String? nightStyleUri,
    TextScaler? textScaler,
    bool pushed = false,
    void Function(mb.MapboxMap map)? onMapCreated,
    bool createMap = true,
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
        vehicleImage: vehicleImage,
        focus: focus,
        initialZoom: initialZoom,
        styleUri: styleUri,
        nightStyleUri: nightStyleUri,
        textScaler: textScaler,
        pushed: pushed,
        onMapCreated: onMapCreated,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
      // No pumpAndSettle: the map frame's ticker always schedules a frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    map.labelPainter = _painter;
    await tester.pump();
    if (createMap) await this.createMap(tester);
  }

  /// The SDK creates the map, then loads the style.
  Future<void> createMap(WidgetTester tester) async {
    views.createMap();
    await settle(tester);
    await loadStyle(tester);
  }

  /// The SDK reports a loaded style.
  Future<void> loadStyle(WidgetTester tester) async {
    views.loadStyle();
    await settle(tester);
  }

  /// Lets the backend's calls finish: each one completes after a zero
  /// timer, which only a pump with a duration runs.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
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
    // Lets the backend's calls in flight finish.
    await tester.pump(const Duration(milliseconds: 16));
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
  const day = MapboxStyleColors.day;
  const night = MapboxStyleColors.night;

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
    expect(find.byType(FakeMapboxView), findsOneWidget);
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
    await h.settle(tester);
    expect(find.byType(MapboxStyleRoutePanel), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(card(0), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(card(2), findsNothing);
    expect(h.optionLines, [_Map.optionLayer(1), _Map.optionLayer(0)]);
    // The labels read the route durations, through the formatter.
    expect(h.views.backend.layerIds, contains(_Map.optionLabels));
    expect(
      h.map.routeLabel!(alt),
      h.formatter.duration(Duration(seconds: alt.duration.round())),
    );

    await tester.tap(card(1));
    await tester.pump();
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('tapping a route option on the map selects it', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await h.settle(tester);
    h.views.backend.tapFeature(_Map.optionLayer(1));
    await h.settle(tester);
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('the map ready hook refreshes the overview on a late map', (
    tester,
    h,
  ) async {
    h.flow.previewRoutes([route, alt]);
    await h.mount(tester, createMap: false);
    expect(h.flow.refreshes, 0);
    expect(h.optionLines, isEmpty);
    await h.createMap(tester);
    expect(h.flow.refreshes, 1);
    expect(h.optionLines, hasLength(2));
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
    expect(h.optionLines, isEmpty, reason: 'options cleared on start');
    expect(h.views.backend.layerIds, contains(_Map.aheadLayer));
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

  navTest('the logo and the attribution keep above the panels (I4)', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    List<double?> margins(String name) => [
      for (final s in h.views.backend.argsOf(name))
        switch (s) {
          final mb.LogoSettings l => l.marginBottom,
          final mb.AttributionSettings a => a.marginBottom,
          _ => null,
        },
    ];
    expect(margins('updateLogo'), [8], reason: 'placed on map creation');
    expect(margins('updateAttribution'), [8]);

    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await h.settle(tester);
    final panel = tester.getSize(find.byType(MapboxStyleRoutePanel)).height;
    expect(margins('updateLogo').last, panel + 8);
    expect(margins('updateAttribution').last, panel + 8);

    await h.startDriving(tester);
    await h.settle(tester);
    final footer = tester.getSize(find.byType(MapboxStyleTripProgress)).height;
    final speed = tester.getRect(find.byType(MapboxStyleSpeedLimit));
    expect(footer, isNot(closeTo(panel, 1)));
    // Above the speed's band too (re-review R1): the wordmark's bottom edge
    // is at or above the speed's top.
    expect(margins('updateLogo').last, greaterThanOrEqualTo(800 - speed.top));
    expect(
      margins('updateAttribution').last,
      greaterThanOrEqualTo(800 - speed.top),
    );
    expect(margins('updateLogo').last, footer + speed.height + 16 + 8);
    expect(h.views.view.bottomInset, footer + speed.height + 16);
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
    expect(_fields(list.colors), _fields(day));
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, day.surface);
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
    expect(find.byType(MapboxStyleNavigation), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    // Idle: a back pops the screen.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapboxStyleNavigation), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  navTest('night on Standard sets the light preset, no reload, same map', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    final adapter = h.map;
    expect(h.views.view.styleUri, mb.MapboxStyles.STANDARD);
    expect(h.lightPreset, 'day');
    expect(materialColor(tester, MapboxStyleTripProgress), day.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), day.banner);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.views.view.night, isTrue);
    expect(h.lightPreset, 'night');
    expect(h.views.backend.names, isNot(contains('loadStyleURI')));
    expect(h.views.mounted, hasLength(1), reason: 'one map');
    expect(h.map, same(adapter), reason: 'the same view');
    expect(h.views.backend.layerIds, contains(_Map.aheadLayer));
    expect(materialColor(tester, MapboxStyleTripProgress), night.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), night.banner);
    expect(h.map.routeColors.ahead, night.accent);
    expect(h.flow.state.value, isA<FlowNavigating>());

    h.flow.nightMode = NightMode.alwaysDay;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.lightPreset, 'day');
    expect(h.views.mounted, hasLength(1));
    expect(h.map, same(adapter));
    expect(materialColor(tester, MapboxStyleTripProgress), day.surface);
  });

  navTest('night on another style loads nightStyleUri, same map', (
    tester,
    h,
  ) async {
    await h.mount(tester, styleUri: _dayStyle, nightStyleUri: _nightStyle);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    final adapter = h.map;
    expect(h.lightPreset, isNull);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.views.backend.argsOf('loadStyleURI'), [_nightStyle]);
    expect(h.views.mounted, hasLength(1), reason: 'one map');
    expect(h.map, same(adapter));
    // The new style loads: the route is drawn again.
    h.views.backend.resetStyle();
    await h.loadStyle(tester);
    expect(h.views.backend.layerIds, contains(_Map.aheadLayer));
    expect(h.lightPreset, isNull);

    h.flow.nightMode = NightMode.alwaysDay;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.views.backend.argsOf('loadStyleURI'), [_nightStyle, _dayStyle]);
    expect(h.views.mounted, hasLength(1));
  });

  group('the theme reaches the map', () {
    navTest('by day the map uses the day colours', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(h.map.routeColors.ahead, day.accent);
      expect(h.map.routeColors.driven, day.alternative);
      expect(h.map.alternativeColor, day.alternative);
      expect(h.map.labelColors, day.routeLabelColors);
    });

    navTest('at night the map uses the night colours', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(
        _fields(
          tester
              .widget<MapboxStyleRoutePanel>(find.byType(MapboxStyleRoutePanel))
              .colors,
        ),
        _fields(night),
      );
      expect(h.map.routeColors.ahead, night.accent);
      expect(h.map.routeColors.driven, night.alternative);
      expect(h.map.alternativeColor, night.alternative);
      expect(h.map.labelColors, night.routeLabelColors);
      expect(h.lightPreset, 'night');
    }, nightMode: NightMode.alwaysNight);

    navTest('dayColors and nightColors replace the defaults', (
      tester,
      h,
    ) async {
      final teal = MapboxStyleColors.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.teal),
      );
      await h.mount(tester, dayColors: teal, nightColors: teal);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      expect(materialColor(tester, MapboxStyleManeuverBanner), teal.banner);
      expect(h.map.routeColors.ahead, teal.accent);
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
    });
  });

  navTest(
    'the style, focus, puck, vehicleImage and initialZoom are forwarded',
    (tester, h) async {
      const puck = CarPuck(size: 30);
      Future<Uint8List> image(double ratio) async => Uint8List(4);
      await h.mount(
        tester,
        puck: puck,
        vehicleImage: image,
        focus: 0.5,
        initialZoom: 15,
        styleUri: _dayStyle,
        nightStyleUri: _nightStyle,
      );
      final view = h.views.view;
      expect(view.session, same(h.session));
      expect(view.initialCenter, sampleRoute.points.first);
      expect(view.styleUri, _dayStyle);
      expect(view.nightStyleUri, _nightStyle);
      expect(view.night, isFalse);
      expect(view.puck, same(puck));
      expect(view.vehicleImage, same(image));
      expect(view.focus, 0.5);
      expect(view.initialZoom, 15);
      expect(view.recenterButton, isNotNull, reason: 'the own one is hidden');
    },
  );

  testWidgets('by default the real MapboxNavigationView is shown', (
    tester,
  ) async {
    final session = NavigationSession(fixes: FakeFixSource());
    addTearDown(session.dispose);
    // Disposed in the body: its timer must be gone before the
    // pending-timer check.
    final flow = NavigationFlowController(
      session: session,
      nightMode: NightMode.alwaysDay,
    );
    final screen = MapboxStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
    );
    expect(screen.styleUri, mb.MapboxStyles.STANDARD);
    expect(screen.nightStyleUri, isNull);
    expect(screen.dayColors, same(MapboxStyleColors.day));
    expect(screen.nightColors, same(MapboxStyleColors.night));
    expect(screen.puck, isA<CarPuck>());
    expect(screen.vehicleImage, isNull);
    expect(screen.focus, 0.7);
    expect(screen.initialZoom, 17);

    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final view = MapboxNavigationView(
      session: session,
      initialCenter: sampleRoute.points.first,
    );
    expect(screen.mapViewBuilder(context, view), same(view));
    flow.dispose();
  });

  testWidgets('the view forwards its parameters to the adapter (shared '
      'with the real view)', (tester) async {
    final session = NavigationSession(fixes: FakeFixSource());
    addTearDown(session.dispose);
    final views = FakeMapboxViews();
    String label(NavRoute r) => 'L';
    void tap(int i) {}
    MapboxNavigationView view({
      bool night = false,
      String styleUri = mb.MapboxStyles.STANDARD,
      double bottomInset = 0,
      Color alternative = const Color(0xFF123456),
    }) => MapboxNavigationView(
      session: session,
      initialCenter: sampleRoute.points.first,
      styleUri: styleUri,
      nightStyleUri: 'night-style',
      night: night,
      routeLabel: label,
      onRouteOptionTap: tap,
      routeColors: const RouteColors(ahead: Color(0xFFFF0000)),
      labelColors: const RouteLabelColors(selectedFill: Color(0xFF00FF00)),
      alternativeRouteColor: alternative,
      bottomInset: bottomInset,
    );
    Widget host(MapboxNavigationView v) => Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (context) => views.build(context, v)),
    );

    await tester.pumpWidget(host(view()));
    final adapter = views.current.adapter;
    expect(session.map, same(adapter));
    expect(adapter.routeLabel, same(label));
    expect(adapter.onRouteOptionTap, same(tap));
    expect(adapter.routeColors.ahead, const Color(0xFFFF0000));
    expect(adapter.labelColors.selectedFill, const Color(0xFF00FF00));
    expect(adapter.alternativeColor, const Color(0xFF123456));
    expect(adapter.bottomInset, 0);
    expect(adapter.lightPreset, 'day');

    // A rebuild forwards the changes; night on Standard is its preset.
    await tester.pumpWidget(
      host(
        view(
          night: true,
          bottomInset: 120,
          alternative: const Color(0xFF654321),
        ),
      ),
    );
    expect(views.current.adapter, same(adapter), reason: 'one adapter');
    expect(adapter.bottomInset, 120);
    expect(adapter.alternativeColor, const Color(0xFF654321));
    expect(adapter.lightPreset, 'night');

    // On another style night loads the night style.
    views.createMap();
    await tester.pumpWidget(host(view(styleUri: 'day-style')));
    views.backend.calls.clear();
    await tester.pumpWidget(host(view(styleUri: 'day-style', night: true)));
    await tester.pump();
    expect(views.backend.argsOf('loadStyleURI'), ['night-style']);
    expect(adapter.lightPreset, isNull);

    // Unmounted: the session lets the adapter go.
    await tester.pumpWidget(const SizedBox());
    expect(session.map, isNull);
    // The fake backend answers through zero-length timers.
    await tester.pump(Duration.zero);
  });

  navTest('onMapCreated: the overview refreshes; no map, no app call', (
    tester,
    h,
  ) async {
    // The stand-in view has no MapboxMap to give: the drop-in still runs
    // its own hook, and hands the app only a real map.
    h.flow.previewRoutes([route, alt]);
    final maps = <mb.MapboxMap>[];
    await h.mount(tester, onMapCreated: maps.add, createMap: false);
    expect(h.views.view.onMapCreated, isA<void Function(mb.MapboxMap?)>());
    await h.createMap(tester);
    expect(h.flow.refreshes, 1);
    expect(maps, isEmpty);
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
}
