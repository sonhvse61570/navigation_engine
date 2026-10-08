import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/fake_google_maps_platform.dart';

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

/// Counts the assignments to [overviewPadding].
class CountingFlow extends NavigationFlowController {
  CountingFlow({
    required super.session,
    super.routeProvider,
    super.nightMode,
    super.clock,
  });

  var paddingSets = 0;

  /// When set, [retry] fails with it (as a future) instead of retrying.
  Object? retryError;
  var retries = 0;

  @override
  set overviewPadding(EdgeInsets value) {
    paddingSets++;
    super.overviewPadding = value;
  }

  @override
  Future<void> retry() {
    retries++;
    final error = retryError;
    if (error != null) return Future.error(error);
    return super.retry();
  }
}

/// A session and a flow on a fake clock, the fake Google platform, and the
/// drop-in on a 400x800 surface.
class Harness {
  Harness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.alwaysDay,
  }) {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
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

  late final FakeGoogleMapsPlatform platform;
  final source = FakeFixSource();
  late final NavigationSession session;
  late final CountingFlow flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);
  final formatter = const EnglishGuidanceFormatter();

  GoogleMapsNavigationMap get map => session.map! as GoogleMapsNavigationMap;

  Set<String> get polylineIds => {
    for (final p in platform.polylines) p.polylineId.value,
  };

  Widget app({
    WidgetBuilder? idleBuilder,
    VoidCallback? onEnd,
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    VehicleImageBuilder? vehicleImage,
    double focus = 0.7,
    double initialZoom = 17,
    TextScaler? textScaler,
    bool pushed = false,
  }) {
    final screen = GoogleStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      idleBuilder: idleBuilder,
      onEnd: onEnd,
      formatter: formatter,
      strings: strings,
      dayRouteColors: dayRouteColors,
      nightRouteColors: nightRouteColors,
      puck: puck,
      vehicleImage: vehicleImage,
      focus: focus,
      initialZoom: initialZoom,
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
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => screen)),
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
    bool createView = true,
    Size size = const Size(400, 800),
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    Widget puck = const CarPuck(),
    VehicleImageBuilder? vehicleImage,
    double focus = 0.7,
    double initialZoom = 17,
    TextScaler? textScaler,
    bool pushed = false,
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
        dayRouteColors: dayRouteColors,
        nightRouteColors: nightRouteColors,
        puck: puck,
        vehicleImage: vehicleImage,
        focus: focus,
        initialZoom: initialZoom,
        textScaler: textScaler,
        pushed: pushed,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
      // No pumpAndSettle: the map frame's ticker always schedules a frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    if (createView) {
      platform.createView();
      await tester.pump();
    }
  }

  /// The colour of the polyline [id] of the last build.
  Color polylineColor(String id) =>
      platform.polylines.singleWhere((p) => p.polylineId.value == id).color;

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

  Color footerColor(WidgetTester tester) => tester
      .widget<Material>(
        find
            .descendant(
              of: find.byType(GoogleStyleTripFooter),
              matching: find.byType(Material),
            )
            .first,
      )
      .color!;

  navTest('idle shows the idle overlay only', (tester, h) async {
    await h.mount(tester, idleBuilder: (_) => const Text('IDLE'));
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.byType(GoogleStyleOverviewPanel), findsNothing);
    expect(find.byType(GoogleStyleManeuverHeader), findsNothing);
    expect(find.byType(GoogleStyleTripFooter), findsNothing);
  });

  navTest('overview shows the panel and draws route options', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);
    expect(card(0), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(card(2), findsNothing);
    expect(
      h.polylineIds,
      containsAll(['navigation_engine_option_0', 'navigation_engine_option_1']),
    );

    await tester.tap(card(1));
    await tester.pump();
    final s = h.flow.state.value as FlowOverview;
    expect(s.selected, 1);
  });

  navTest('tapping a route option on the map selects it', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    h.map.routeOptionPolylines.value
        .singleWhere((p) => p.polylineId.value == 'navigation_engine_option_1')
        .onTap!();
    await tester.pump();
    expect((h.flow.state.value as FlowOverview).selected, 1);
  });

  navTest('start shows header, footer and speedometer while driving', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    // No guidance yet right after start: no header, not an empty card.
    expect(h.session.guidanceState, isNull);
    expect(find.byType(GoogleStyleManeuverHeader), findsNothing);
    expect(find.byType(GoogleStyleTripFooter), findsOneWidget);
    await h.run(
      tester,
      4,
      fixAt: (s) => h.fixOn(route, 500.0 + 10 * s, speed: 10),
    );
    expect(h.flow.state.value, isA<FlowNavigating>());
    expect(find.byType(GoogleStyleOverviewPanel), findsNothing);
    expect(find.byType(GoogleStyleManeuverHeader), findsOneWidget);
    expect(find.byType(GoogleStyleTripFooter), findsOneWidget);
    expect(find.byType(GoogleStyleSpeedometer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GoogleStyleTripFooter),
        matching: find.text(
          h.formatter.duration(h.flow.tripProgress.value!.remainingDuration),
        ),
      ),
      findsOneWidget,
    );
  });

  navTest('the recenter button sits above the footer', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    expect(find.byType(GoogleStyleRecenterButton), findsNothing);
    await h.startDriving(tester);
    expect(find.byType(GoogleStyleRecenterButton), findsNothing);
    h.session.follow = false;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final button = tester.getRect(find.byType(GoogleStyleRecenterButton));
    final footer = tester.getRect(find.byType(GoogleStyleTripFooter));
    // At the bottom start (spec D7), stacked above the speedometer.
    final speed = tester.getRect(find.byType(GoogleStyleSpeedometer));
    expect(button.left, closeTo(16, 1));
    expect(button.center.dx, lessThan(400 / 2));
    expect(button.bottom, closeTo(speed.top - 8, 1), reason: '8 above');
    expect(speed.bottom, closeTo(footer.top - 16, 1));
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
    expect(find.byType(GoogleStyleTripFooter), findsNothing);

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
    expect(find.byType(GoogleStyleStepList), findsOneWidget);
    final list = tester.widget<GoogleStyleStepList>(
      find.byType(GoogleStyleStepList),
    );
    expect(list.route, same(route));
    expect(list.currentStep, h.session.guidanceState!.stepIndex);
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
    expect(find.byType(GoogleStyleArrivalPanel), findsOneWidget);
    expect(find.byType(GoogleStyleTripFooter), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    expect(h.session.isRunning, isFalse);
    expect(find.byType(GoogleStyleArrivalPanel), findsNothing);
  });

  late PendingRouteProvider pendingProvider;
  navTest('loading, error, retry and cancel', (tester, h) async {
    final provider = pendingProvider;
    await h.mount(tester);
    // A last fix elsewhere: the retry must not start from it.
    h.session.start();
    h.source.add(h.fixOn(route, 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.session.lastFix, isNotNull);

    final from = route.pointAt(2000);
    final to = route.points.last;
    expect(h.session.lastFix!.position, isNot(from));
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
    expect(find.byType(GoogleStyleOverviewPanel), findsNothing);
  }, provider: () => pendingProvider = PendingRouteProvider());

  navTest('night mode restyles without recreating the map', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    // google_maps_flutter sends a null style as '' (no style).
    expect(h.platform.mapConfiguration.style, '');
    expect(footerColor(tester), GoogleStyleColors.day.surface);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.platform.mapConfiguration.style, googleStyleNightMapStyle);
    expect(h.platform.creationIds, hasLength(1));
    expect(footerColor(tester), GoogleStyleColors.night.surface);
    expect(h.flow.state.value, isA<FlowNavigating>());

    // Back to day: no style (null, sent as '') clears the night one.
    h.flow.nightMode = NightMode.alwaysDay;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.platform.mapConfiguration.style, '');
    expect(h.platform.creationIds, hasLength(1));
    expect(footerColor(tester), GoogleStyleColors.day.surface);
  });

  navTest('overview padding follows the panel', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    // No pumpAndSettle: the map frame's ticker always schedules a frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final panel = tester.getSize(find.byType(GoogleStyleOverviewPanel));
    expect(h.flow.overviewPadding.bottom, closeTo(panel.height + 32, 1));
    expect(h.flow.overviewPadding.left, 32);
    expect(h.flow.overviewPadding.right, 32);
    expect(h.flow.overviewPadding.top, 32);

    final sets = h.flow.paddingSets;
    final animations = h.platform.cameraAnimations.length;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets, reason: 'no change, no set');
    expect(h.platform.cameraAnimations, hasLength(animations));

    // A side inset (final review I3): the routes keep clear of it; the
    // panel keeps its size.
    tester.view.padding = const FakeViewPadding(left: 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(find.byType(GoogleStyleOverviewPanel)), panel);
    expect(h.flow.paddingSets, sets + 1);
    expect(h.flow.overviewPadding.left, 32 + 8);
    expect(h.flow.overviewPadding.right, 32);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets + 1, reason: 'no change, no set');

    await h.flow.preview(from: route.points.first, to: route.points.last);
    expect(h.flow.state.value, isA<FlowError>());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final error = tester.getSize(find.byType(GoogleStyleOverviewPanel));
    expect(error.height, isNot(closeTo(panel.height, 1)));
    expect(h.flow.paddingSets, sets + 2);
    expect(h.flow.overviewPadding.bottom, closeTo(error.height + 32, 1));
  }, provider: () => _FailingRouteProvider());

  navTest('refreshOverview on map creation draws options on a late map', (
    tester,
    h,
  ) async {
    h.flow.previewRoutes([route, alt]);
    await h.mount(tester, createView: false);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.polylineIds, isNot(contains('navigation_engine_option_0')));
    expect(h.platform.cameraMoves, isEmpty);

    h.platform.createView();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      h.polylineIds,
      containsAll(['navigation_engine_option_0', 'navigation_engine_option_1']),
    );
    expect(h.platform.cameraMoves, hasLength(1));
  });

  group('ways out (I2)', () {
    navTest('loading shows Cancel; tapping it returns to idle', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      unawaited(
        h.flow.preview(from: route.points.first, to: route.points.last),
      );
      await tester.pump();
      expect(h.flow.state.value, isA<FlowLoading>());
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(find.byType(GoogleStyleOverviewPanel), findsNothing);
    }, provider: PendingRouteProvider.new);

    navTest('the close button of a preview returns to idle', (tester, h) async {
      await h.mount(tester);
      h.session.start();
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      final close = find.descendant(
        of: find.byType(GoogleStyleOverviewPanel),
        matching: find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(h.session.isRunning, isTrue, reason: 'the session is untouched');
      expect(h.polylineIds, isNot(contains('navigation_engine_option_0')));
    });

    navTest('after closing a preview, recenter brings the vehicle back', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      h.session.start();
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(h.session.follow, isFalse, reason: 'the overview stops following');
      await tester.tap(
        find.descendant(
          of: find.byType(GoogleStyleOverviewPanel),
          matching: find.widgetWithIcon(IconButton, Icons.close),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.flow.state.value, isA<FlowIdle>());
      final recenter = find.byType(GoogleStyleRecenterButton);
      expect(recenter, findsOneWidget);
      await tester.tap(recenter);
      await tester.pump();
      expect(h.session.follow, isTrue);
    });

    navTest('the trip overview has no close button', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      await tester.tap(find.byTooltip('Overview'));
      await tester.pump();
      expect(h.flow.isTripOverview, isTrue);
      expect(
        find.descendant(
          of: find.byType(GoogleStyleOverviewPanel),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
    });

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
      expect(find.byType(GoogleStyleNavigation), findsOneWidget);
      expect(find.text('HOME'), findsNothing);

      // Idle: a back pops the screen.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleNavigation), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    navTest('a back while loading cancels', (tester, h) async {
      await h.mount(tester, pushed: true);
      unawaited(
        h.flow.preview(from: route.points.first, to: route.points.last),
      );
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(find.byType(GoogleStyleNavigation), findsOneWidget);
    }, provider: PendingRouteProvider.new);

    navTest('a back in an error cancels', (tester, h) async {
      await h.mount(tester, pushed: true);
      await h.flow.preview(from: route.points.first, to: route.points.last);
      expect(h.flow.state.value, isA<FlowError>());
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(find.byType(GoogleStyleNavigation), findsOneWidget);
    }, provider: () => _FailingRouteProvider());

    navTest('a back in the trip overview resumes navigation', (
      tester,
      h,
    ) async {
      await h.mount(tester, pushed: true);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      final running = h.session.route;
      h.flow.backToOverview();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowNavigating>());
      expect(h.session.route, same(running));
      expect(find.byType(GoogleStyleNavigation), findsOneWidget);
    });
  });

  group('the theme reaches the map (I3)', () {
    navTest('at night the routes and labels use the night colours', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      const night = GoogleStyleColors.night;
      expect(h.polylineColor('navigation_engine_option_0'), night.accent);
      expect(h.polylineColor('navigation_engine_option_1'), night.alternative);
      expect(h.map.labelColors, night.routeLabelColors);

      await h.startDriving(tester);
      expect(h.polylineColor('navigation_engine_ahead'), night.accent);
      expect(h.map.routeColors.driven, night.alternative);
    }, nightMode: NightMode.alwaysNight);

    navTest('by day the route keeps the day colours', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      const day = GoogleStyleColors.day;
      expect(h.polylineColor('navigation_engine_ahead'), day.accent);
      expect(h.map.routeColors.driven, day.alternative);
      expect(h.map.labelColors, day.routeLabelColors);
    });

    navTest('nightRouteColors override the night default', (tester, h) async {
      const mine = RouteColors(
        driven: Color(0xFF111111),
        ahead: Color(0xFF222222),
      );
      await h.mount(tester, nightRouteColors: mine);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester);
      expect(h.polylineColor('navigation_engine_ahead'), mine.ahead);
      expect(h.map.routeColors, same(mine));
    }, nightMode: NightMode.alwaysNight);

    navTest('dayRouteColors override the day default', (tester, h) async {
      const mine = RouteColors(ahead: Color(0xFF333333));
      await h.mount(tester, dayRouteColors: mine);
      h.flow.previewRoutes([route]);
      await tester.pump();
      expect(h.polylineColor('navigation_engine_option_0'), mine.ahead);
    });

    navTest('focus, puck, vehicleImage and initialZoom are forwarded', (
      tester,
      h,
    ) async {
      const puck = CarPuck(size: 30);
      Future<Uint8List> image(double ratio) async => Uint8List.fromList([1]);
      await h.mount(
        tester,
        puck: puck,
        vehicleImage: image,
        focus: 0.5,
        initialZoom: 15,
      );
      final view = tester.widget<GoogleMapsNavigationView>(
        find.byType(GoogleMapsNavigationView),
      );
      expect(view.puck, same(puck));
      expect(view.vehicleImage, same(image));
      expect(view.focus, 0.5);
      expect(view.initialZoom, 15);
    });
  });

  navTest('speeds go through the formatter (I4)', (tester, h) async {
    const mph = _MphFormatter();
    await h.mount(tester, formatter: mph);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    final speedometer = tester.widget<GoogleStyleSpeedometer>(
      find.byType(GoogleStyleSpeedometer),
    );
    expect(speedometer.formatter, same(mph));
    expect(find.text('mph'), findsOneWidget);
    expect(find.text('km/h'), findsNothing);
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
    navTest('navigating at 2x text on 320 dp ($name) (I5)', (tester, h) async {
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
      expect(find.byType(GoogleStyleManeuverHeader), findsOneWidget);
      expect(find.byType(GoogleStyleTripFooter), findsOneWidget);
      expect(find.byType(GoogleStyleSpeedometer), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'navigating');
      // Vertically too: inside the screen, the speedometer between the
      // header and the footer.
      final header = tester.getRect(find.byType(GoogleStyleManeuverHeader));
      final footer = tester.getRect(find.byType(GoogleStyleTripFooter));
      final speed = tester.getRect(find.byType(GoogleStyleSpeedometer));
      expect(header.top, greaterThanOrEqualTo(0));
      expect(footer.bottom, lessThanOrEqualTo(640));
      expect(speed.top, greaterThanOrEqualTo(header.bottom), reason: '$speed');
      expect(speed.bottom, closeTo(footer.top - 16, 1));
    });

    for (final scale in [1.0, 1.3]) {
      navTest('844x390 landscape with insets, ${scale}x text ($name)', (
        tester,
        h,
      ) async {
        const insets = FakeViewPadding(left: 47, right: 47, bottom: 21);
        tester.view
          ..padding = insets
          ..viewPadding = insets;
        await h.mount(
          tester,
          size: const Size(844, 390),
          textScaler: TextScaler.linear(scale),
          formatter: formatter,
          strings: strings,
        );
        h.flow.previewRoutes([route]);
        await tester.pump();
        await h.startDriving(tester, start: strings.start);
        expect(h.flow.state.value, isA<FlowNavigating>());
        h.session.follow = false;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        const safe = Rect.fromLTRB(47, 0, 844 - 47, 390 - 21);
        bool inside(Rect r) =>
            r.left >= safe.left - 0.5 &&
            r.top >= safe.top - 0.5 &&
            r.right <= safe.right + 0.5 &&
            r.bottom <= safe.bottom + 0.5;
        final speed = tester.getRect(find.byType(GoogleStyleSpeedometer));
        final recenter = tester.getRect(find.byType(GoogleStyleRecenterButton));
        final footer = tester.getRect(find.byType(GoogleStyleTripFooter));
        final bar = tester.getRect(find.byType(GoogleStyleTripProgressBar));
        expect(inside(speed), isTrue, reason: 'speed $speed');
        expect(inside(recenter), isTrue, reason: 'recenter $recenter');
        expect(inside(bar), isTrue, reason: 'progress bar $bar');
        expect(recenter.height, greaterThanOrEqualTo(48));
        expect(recenter.overlaps(speed), isFalse, reason: '$recenter');
        expect(recenter.overlaps(footer), isFalse, reason: '$recenter');
        expect(speed.overlaps(footer), isFalse, reason: '$speed');
        // The header spans the width: the stack would reach into it, so
        // the recenter sits beside the speed.
        final header = tester.getRect(find.byType(GoogleStyleManeuverHeader));
        expect(recenter.overlaps(header), isFalse, reason: '$recenter');
        expect(speed.overlaps(header), isFalse, reason: '$speed');
        expect(recenter.left, greaterThan(speed.right));
      });
    }
  }

  navTest('the step sheet closes on arrival (M8)', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await h.run(
      tester,
      2,
      fixAt: (s) => h.fixOn(route, route.length - 120 + 8.0 * s, speed: 8),
    );
    expect(h.flow.state.value, isA<FlowNavigating>());
    await tester.tap(find.byTooltip('Steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GoogleStyleStepList), findsOneWidget);

    await h.run(
      tester,
      12,
      fixAt: (s) => h.fixOn(route, route.length - 100 + 8.0 * s, speed: 8),
    );
    expect(h.flow.state.value, isA<FlowArrived>());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GoogleStyleStepList), findsNothing);
    expect(find.byType(GoogleStyleArrivalPanel), findsOneWidget);
    expect(find.text('Done').hitTestable(), findsOneWidget);
  });

  navTest('the step sheet follows the current step (M8)', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    // Up to just before step 4 (at about 1983 m).
    await h.run(
      tester,
      4,
      fixAt: (s) => h.fixOn(route, 1930.0 + 10 * s, speed: 10),
    );
    final first = h.session.guidanceState!.stepIndex;
    await tester.tap(find.byTooltip('Steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    GoogleStyleStepList list() =>
        tester.widget<GoogleStyleStepList>(find.byType(GoogleStyleStepList));
    expect(list().currentStep, first);

    // On past it.
    await h.run(
      tester,
      6,
      fixAt: (s) => h.fixOn(route, 1970.0 + 10 * s, speed: 10),
    );
    final now = h.session.guidanceState!.stepIndex;
    expect(now, greaterThan(first));
    expect(list().currentStep, now);
  });

  navTest('the step sheet closes on stop (M8)', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    await tester.tap(find.byTooltip('Steps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    h.flow.stop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GoogleStyleStepList), findsNothing);
  });

  navTest('progress ticks do not rebuild the map view (M9)', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester);
    var ticks = 0;
    void count() => ticks++;
    h.flow.tripProgress.addListener(count);
    addTearDown(() => h.flow.tripProgress.removeListener(count));
    GoogleMapsNavigationView view() => tester.widget<GoogleMapsNavigationView>(
      find.byType(GoogleMapsNavigationView),
    );
    final before = view();
    await h.run(
      tester,
      3.5,
      fixAt: (s) => h.fixOn(route, 540.0 + 10 * s, speed: 10),
    );
    expect(ticks, greaterThanOrEqualTo(3));
    expect(view(), same(before), reason: 'no rebuild for progress');

    // Night still restyles the map.
    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    expect(view(), isNot(same(before)));
    expect(view().style, googleStyleNightMapStyle);
  });

  group('guarded retry (M10)', () {
    late PendingRouteProvider pending;
    navTest('a double-tapped Retry retries once', (tester, h) async {
      await h.mount(tester);
      unawaited(
        h.flow.preview(from: route.points.first, to: route.points.last),
      );
      pending.pending.completeError(Exception('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      // The first tap moves the flow to loading; the second, before the
      // next frame, still finds the Retry button.
      await tester.tap(find.text('Retry'));
      expect(h.flow.state.value, isA<FlowLoading>());
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(h.flow.retries, 1);
      expect(pending.requests, hasLength(2), reason: 'preview and one retry');
      expect(tester.takeException(), isNull);
    }, provider: () => pending = PendingRouteProvider());

    navTest('a failed retry is reported through FlutterError', (
      tester,
      h,
    ) async {
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      await h.mount(tester);
      await h.flow.preview(from: route.points.first, to: route.points.last);
      await tester.pump();
      h.flow.retryError = StateError('retry failed');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      FlutterError.onError = old;
      expect(errors.map((e) => e.exception), [isA<StateError>()]);
    }, provider: () => _FailingRouteProvider());
  });
}

/// Speeds in mph.
class _MphFormatter extends EnglishGuidanceFormatter {
  const _MphFormatter();

  @override
  String speedValue(double metresPerSecond) =>
      '${(metresPerSecond * 2.23694).round()}';

  @override
  String get speedUnit => 'mph';
}

class _FailingRouteProvider extends RouteProvider {
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) =>
      Future.error(Exception('offline'));

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) => Future.error(Exception('offline'));
}
