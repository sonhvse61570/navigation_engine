import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';

import 'support/recording_platform.dart';

typedef _Map = MapLibreNavigationMap;

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

/// Renders a search pin as `pin` bytes, without the engine.
Future<Uint8List> _pin({
  required bool focused,
  required double pixelRatio,
  required Color color,
}) async => Uint8List.fromList('pin'.codeUnits);

/// Renders the destination pin as `dest` bytes, without the engine.
Future<Uint8List> _destination({required double pixelRatio}) async =>
    Uint8List.fromList('dest'.codeUnits);

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

/// A session and a flow on a fake clock, the recording MapLibre platform,
/// and the drop-in on a 400x800 surface.
class Harness {
  Harness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.alwaysDay,
  }) {
    createInstance = ml.MapLibrePlatform.createInstance;
    ml.MapLibrePlatform.createInstance = () => platform;
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

  final platform = RecordingPlatform();
  late final ml.MapLibrePlatform Function() createInstance;
  final source = FakeFixSource();
  late final NavigationSession session;
  late final CountingFlow flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);
  final formatter = const EnglishGuidanceFormatter();

  MapLibreNavigationMap get map => session.map! as MapLibreNavigationMap;

  /// The option line layers in the style (not the casings or labels).
  List<String> get optionLines => [
    for (final id in platform.layerIds)
      if (id.startsWith(_Map.optionPrefix) &&
          !id.startsWith('${_Map.optionPrefix}casing_') &&
          id != _Map.optionLabels)
        id,
  ];

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
    String? nightStyleString = 'night.json',
    TextScaler? textScaler,
    bool pushed = false,
    void Function(ml.MapLibreMapController controller)? onMapCreated,
    void Function(GeoPoint point)? onMapTap,
    void Function(GeoPoint point)? onMapLongPress,
  }) {
    final screen = MapLibreStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      styleString: 'day.json',
      nightStyleString: nightStyleString,
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
      onMapTap: onMapTap,
      onMapLongPress: onMapLongPress,
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

  /// Mounts the drop-in; the platform creates the map, and (with
  /// [loadStyle]) the style loads.
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
    String? nightStyleString = 'night.json',
    TextScaler? textScaler,
    bool pushed = false,
    void Function(ml.MapLibreMapController controller)? onMapCreated,
    void Function(GeoPoint point)? onMapTap,
    void Function(GeoPoint point)? onMapLongPress,
    bool loadStyle = true,
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
        nightStyleString: nightStyleString,
        textScaler: textScaler,
        pushed: pushed,
        onMapCreated: onMapCreated,
        onMapTap: onMapTap,
        onMapLongPress: onMapLongPress,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
      // No pumpAndSettle: the map frame's ticker always schedules a frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    map
      ..labelPainter = _painter
      ..pinPainter = _pin
      ..destinationPinPainter = _destination;
    // The platform view is created in a microtask.
    await tester.pump();
    if (loadStyle) await this.loadStyle(tester);
  }

  /// The SDK reports a loaded style.
  Future<void> loadStyle(WidgetTester tester) async {
    unawaited(map.onStyleLoaded());
    await tester.pump();
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
  /// session; restores the platform.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
    ml.MapLibrePlatform.createInstance = createInstance;
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
    expect(find.byType(MapLibreNavigationView), findsOneWidget);
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
    await tester.pump();
    expect(find.byType(MapboxStyleRoutePanel), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(card(0), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(card(2), findsNothing);
    expect(h.optionLines, [_Map.optionLayer(1), _Map.optionLayer(0)]);
    // The labels read the route durations, through the formatter.
    expect(h.platform.layerIds, contains(_Map.optionLabels));
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
    await tester.pump();
    await tester.pump();
    h.platform.tapFeature(_Map.optionLayer(1));
    await tester.pump();
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('the map ready hook refreshes the overview on a late map', (
    tester,
    h,
  ) async {
    h.flow.previewRoutes([route, alt]);
    expect(h.flow.refreshes, 0);
    await h.mount(tester);
    expect(h.flow.refreshes, 1);
    await tester.pump();
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
    expect(h.platform.layerIds, contains(_Map.aheadLayer));
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
    expect(find.byType(MapLibreStyleNavigation), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    // Idle: a back pops the screen.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapLibreStyleNavigation), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  navTest('night loads the night style without recreating the map', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    final adapter = h.map;
    final mapState = tester.state(find.byType(ml.MapLibreMap));
    expect(h.platform.argsOf('buildView').toSet(), {'day.json'});
    expect(materialColor(tester, MapboxStyleTripProgress), day.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), day.banner);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.platform.argsOf('updateMapOptions').last, {
      'styleString': 'night.json',
    });
    expect(tester.state(find.byType(ml.MapLibreMap)), same(mapState));
    expect(h.map, same(adapter), reason: 'the same view');
    expect(materialColor(tester, MapboxStyleTripProgress), night.surface);
    expect(materialColor(tester, MapboxStyleManeuverBanner), night.banner);
    expect(h.map.routeColors.ahead, night.accent);
    expect(h.flow.state.value, isA<FlowNavigating>());

    // The new style loads: the route is drawn again.
    h.platform.reloadStyle();
    await h.loadStyle(tester);
    expect(h.platform.layerIds, contains(_Map.aheadLayer));

    h.flow.nightMode = NightMode.alwaysDay;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.platform.argsOf('updateMapOptions').last, {
      'styleString': 'day.json',
    });
    expect(tester.state(find.byType(ml.MapLibreMap)), same(mapState));
    expect(h.map, same(adapter));
    expect(materialColor(tester, MapboxStyleTripProgress), day.surface);
  });

  navTest('the attribution and the logo keep above the panels (I4)', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    final options = h.platform.creationParams.first['options'] as Map;
    expect(options['attributionButtonMargins'], [8, 8], reason: 'idle');
    expect(options['logoViewMargins'], [8, 8], reason: 'idle');

    /// The margins last sent, from the creation and the option updates.
    Object? last(String name) => [
      options[name],
      for (final update in h.platform.argsOf('updateMapOptions'))
        if ((update! as Map).containsKey(name)) (update as Map)[name],
    ].last;

    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final panel = tester.getSize(find.byType(MapboxStyleRoutePanel)).height;
    expect(last('attributionButtonMargins'), [8, panel + 8]);
    expect(last('logoViewMargins'), [8, panel + 8]);

    await h.startDriving(tester);
    final footer = tester.getSize(find.byType(MapboxStyleTripProgress)).height;
    final speed = tester.getSize(find.byType(MapboxStyleSpeedLimit)).height;
    expect(footer, isNot(closeTo(panel, 1)));
    // Above the speed's band too (re-review R1).
    expect(last('attributionButtonMargins'), [8, footer + speed + 16 + 8]);
    expect(last('logoViewMargins'), [8, footer + speed + 16 + 8]);
  });

  navTest('without a night style, night keeps the day style', (
    tester,
    h,
  ) async {
    await h.mount(tester, nightStyleString: null);
    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.platform.names, isNot(contains('updateMapOptions')));
    final view = tester.widget<MapLibreNavigationView>(
      find.byType(MapLibreNavigationView),
    );
    expect(view.night, isTrue);
    expect(view.nightStyleString, isNull);
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
      );
      final view = tester.widget<MapLibreNavigationView>(
        find.byType(MapLibreNavigationView),
      );
      expect(view.styleString, 'day.json');
      expect(view.nightStyleString, 'night.json');
      expect(view.night, isFalse);
      expect(view.puck, same(puck));
      expect(view.vehicleImage, same(image));
      expect(view.focus, 0.5);
      expect(view.initialZoom, 15);
    },
  );

  test('the defaults', () {
    final session = NavigationSession(fixes: FakeFixSource());
    addTearDown(session.dispose);
    final flow = NavigationFlowController(
      session: session,
      nightMode: NightMode.alwaysDay,
    );
    addTearDown(flow.dispose);
    final screen = MapLibreStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      styleString: 'day.json',
    );
    expect(screen.dayColors, same(MapboxStyleColors.day));
    expect(screen.nightColors, same(MapboxStyleColors.night));
    expect(screen.nightStyleString, isNull);
    expect(screen.puck, isA<CarPuck>());
    expect(screen.vehicleImage, isNull);
    expect(screen.focus, 0.7);
    expect(screen.initialZoom, 17);
  });

  navTest('onMapCreated gets the controller after the overview refresh', (
    tester,
    h,
  ) async {
    h.flow.previewRoutes([route, alt]);
    final calls = <(ml.MapLibreMapController, int)>[];
    await h.mount(
      tester,
      onMapCreated: (c) => calls.add((c, h.flow.refreshes)),
    );
    expect(calls, hasLength(1));
    expect(calls.single.$2, 1, reason: 'config.onMapReady runs first');
    // The very controller the adapter draws with.
    final adapter = h.session.map! as MapLibreNavigationMap;
    expect(calls.single.$1, same(adapter.controller));
    // The adapter's controller: route option taps on it select.
    h.platform.tapFeature(_Map.optionLayer(1));
    await tester.pump();
    expect((h.flow.state.value as FlowOverview).selected, 1);
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

  group('map taps, pins and alternates (SP6)', () {
    navTest('map taps and long presses reach the app', (tester, h) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      await h.mount(tester, onMapTap: taps.add, onMapLongPress: presses.add);
      final view = tester.widget<MapLibreNavigationView>(
        find.byType(MapLibreNavigationView),
      );
      expect(view.onMapTap, isNotNull);
      expect(view.onMapLongPress, isNotNull);
      h.platform
        ..tapMap(const ml.LatLng(10.5, 106.25))
        ..longPressMap(const ml.LatLng(10.25, 106.5));
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(10.5, 106.25)]);
      expect(presses, [const GeoPoint(10.25, 106.5)]);
    });

    navTest('a tap on a route option selects it and is no map tap', (
      tester,
      h,
    ) async {
      final taps = <GeoPoint>[];
      await h.mount(tester, onMapTap: taps.add);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump();
      h.platform
        ..tapFeature(_Map.optionLayer(1))
        ..tapMap(const ml.LatLng(10.5, 106.25));
      await tester.pump(Duration.zero);
      expect((h.flow.state.value as FlowOverview).selected, 1);
      expect(taps, isEmpty);
    });

    navTest('the overview pins the destination, through a night style '
        'reload', (tester, h) async {
      await h.mount(tester);
      expect(h.map, isA<DestinationPinMap>());
      expect(h.map, isA<SearchPinsMap>());
      expect(h.map, isA<AlternateRoutesMap>());
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      await tester.pump();
      List<Object?> pin() =>
          ((h.platform.sources[_Map.destination]!['features'] as List).single
                  as Map)['geometry']['coordinates']
              as List<Object?>;
      expect(h.platform.layerIds, contains(_Map.destination));
      expect(pin(), [route.points.last.lng, route.points.last.lat]);

      h.flow.nightMode = NightMode.alwaysNight;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      h.platform.reloadStyle();
      await h.loadStyle(tester);
      expect(h.platform.layerIds, contains(_Map.destination));
      expect(pin(), [route.points.last.lng, route.points.last.lat]);

      h.flow.stop();
      await tester.pump();
      await tester.pump();
      expect(h.platform.layerIds, isNot(contains(_Map.destination)));
    });

    navTest('alternates and pins use the screen\'s words and colours', (
      tester,
      h,
    ) async {
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
      expect(h.map.alternateColor, day.alternative);
      expect(h.map.pinColor, day.warning);
      expect(h.map.fasterLabelColors.text, day.accent);
      expect(h.map.slowerLabelColors.text, day.onSurfaceVariant);
      expect(h.map.fasterLabelColors.fill, day.surface);

      h.flow.nightMode = NightMode.alwaysNight;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.map.alternateColor, night.alternative);
      expect(h.map.pinColor, night.warning);
      expect(h.map.fasterLabelColors.text, night.accent);
    });
  });
}
