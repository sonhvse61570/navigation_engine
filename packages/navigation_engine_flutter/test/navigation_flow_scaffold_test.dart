import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

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

class FakePreviewMap implements NavigationMap, RoutePreviewMap {
  List<NavRoute>? options;
  @override
  Future<void> moveCamera(CameraTarget target) async {}
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {}
  @override
  void clearRoute() {}
  @override
  void showRouteOptions(List<NavRoute> routes, int selected) =>
      options = routes;
  @override
  void clearRouteOptions() => options = null;
  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {}
}

class FakeRouteProvider extends RouteProvider {
  FakeRouteProvider(this.handler);
  Future<List<NavRoute>> Function(GeoPoint from, GeoPoint to) handler;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await handler(from, to)).first;

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) => handler(from, to);
}

/// Counts the overview padding sets, the overview refreshes and the
/// retries.
class CountingFlow extends NavigationFlowController {
  CountingFlow({
    required super.session,
    super.routeProvider,
    super.nightMode,
    super.clock,
  });

  var paddingSets = 0;
  var refreshes = 0;
  var retries = 0;

  /// When set, [retry] fails with it (as a future) instead of retrying.
  Object? retryError;

  @override
  set overviewPadding(EdgeInsets value) {
    paddingSets++;
    super.overviewPadding = value;
  }

  @override
  void refreshOverview() {
    refreshes++;
    super.refreshOverview();
  }

  @override
  Future<void> retry() {
    retries++;
    final error = retryError;
    if (error != null) return Future.error(error);
    return super.retry();
  }
}

/// A map that records its configs and reports itself ready once. Like a map
/// view, it calls [onTouch] on a pointer down (a map view stops following
/// there).
class FakeMapWidget extends StatefulWidget {
  const FakeMapWidget({
    super.key,
    required this.config,
    this.ready = true,
    this.onTouch,
  });

  final NavigationMapConfig config;
  final bool ready;
  final VoidCallback? onTouch;

  @override
  State<FakeMapWidget> createState() => _FakeMapWidgetState();
}

class _FakeMapWidgetState extends State<FakeMapWidget> {
  @override
  void initState() {
    super.initState();
    if (widget.ready) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.config.onMapReady(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => widget.onTouch?.call(),
    child: const ColoredBox(color: Color(0xFF808080)),
  );
}

const _long =
    'A very long text that has to wrap over several lines on a narrow '
    'screen with a large text scale, and then some more words';

/// A session and a flow on a fake clock, and the scaffold with fake pieces
/// on a 400x800 surface.
class Harness {
  Harness({RouteProvider? provider}) {
    session = NavigationSession(
      fixes: source,
      map: map,
      routeProvider: provider,
      clock: () => now,
    );
    flow = CountingFlow(
      session: session,
      routeProvider: provider,
      nightMode: NightMode.alwaysDay,
      clock: () => now,
    );
  }

  final source = FakeFixSource();
  final map = FakePreviewMap();
  late final NavigationSession session;
  late final CountingFlow flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);

  /// Every config the map builder got, in order.
  final configs = <NavigationMapConfig>[];
  NavigationMapConfig get config => configs.last;

  /// The actions of the last piece built.
  NavigationFlowActions? actions;

  /// The actions the top end slot got at its last build.
  NavigationFlowActions? topEndActions;

  /// The actions the header got at its last build.
  NavigationFlowActions? headerActions;

  /// The step list's last current step and route.
  int? currentStep;
  NavRoute? stepRoute;

  /// The panel's height; a test changes it to resize the panel.
  double panelHeight = 120;

  Widget app({
    bool long = false,
    bool pushed = false,
    bool mapReady = true,
    TextScaler? textScaler,
    AlignmentDirectional recenterAlignment = AlignmentDirectional.bottomStart,
    double overviewMargin = 32,
    VoidCallback? onEnd,
    bool recenter = true,
    bool speed = true,
    String speedText = 'SPEED',
    bool emptySpeed = false,
    TextDirection? textDirection,
  }) {
    Widget text(String key, String value) =>
        Text(long ? '$value $_long' : value, key: ValueKey(key));
    final screen = NavigationFlowScaffold(
      session: session,
      flow: flow,
      recenterAlignment: recenterAlignment,
      overviewMargin: overviewMargin,
      onEnd: onEnd,
      mapBuilder: (context, config) {
        configs.add(config);
        return FakeMapWidget(
          config: config,
          ready: mapReady,
          onTouch: () => session.follow = false,
        );
      },
      idleBuilder: (context) =>
          Align(alignment: Alignment.topCenter, child: text('idle', 'IDLE')),
      panelBuilder: (context, state, actions) {
        this.actions = actions;
        return SizedBox(
          key: const ValueKey('panel'),
          height: long ? null : panelHeight,
          child: text('panel_text', 'PANEL ${state.runtimeType}'),
        );
      },
      headerBuilder: (context, guidance, actions) {
        headerActions = actions;
        return text('header', 'HEADER ${guidance.stepIndex}');
      },
      footerBuilder: (context, progress, rerouting, actions) {
        this.actions = actions;
        return text('footer', 'FOOTER $rerouting');
      },
      speedBuilder: !speed
          ? null
          : emptySpeed
          // A speed piece that shows nothing (such as a limit sign alone
          // with no known limit).
          ? (context, speed) => const SizedBox.shrink(key: ValueKey('speed'))
          : (context, speed) => text('speed', speedText),
      topEndBuilder: (context, actions) {
        topEndActions = actions;
        return text('topEnd', 'TOPEND');
      },
      edgeBuilder: (context, progress) => text('edge', 'EDGE'),
      arrivalBuilder: (context, route, actions) {
        this.actions = actions;
        return text('arrival', 'ARRIVAL');
      },
      stepListBuilder: (context, route, currentStep) {
        stepRoute = route;
        this.currentStep = currentStep;
        return text('steps', 'STEPS $currentStep');
      },
      recenterBuilder: recenter
          ? (context, recenter) => GestureDetector(
              onTap: recenter,
              child: text('recenter', 'RECENTER'),
            )
          : null,
    );
    return MaterialApp(
      builder: textScaler == null && textDirection == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: textScaler ?? TextScaler.noScaling),
              child: textDirection == null
                  ? child!
                  : Directionality(textDirection: textDirection, child: child!),
            ),
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
    Size size = const Size(400, 800),
    bool long = false,
    bool pushed = false,
    bool mapReady = true,
    TextScaler? textScaler,
    AlignmentDirectional recenterAlignment = AlignmentDirectional.bottomStart,
    double overviewMargin = 32,
    VoidCallback? onEnd,
    bool recenter = true,
    bool speed = true,
    String speedText = 'SPEED',
    bool emptySpeed = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        long: long,
        pushed: pushed,
        mapReady: mapReady,
        textScaler: textScaler,
        recenterAlignment: recenterAlignment,
        overviewMargin: overviewMargin,
        onEnd: onEnd,
        recenter: recenter,
        speed: speed,
        speedText: speedText,
        emptySpeed: emptySpeed,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
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

  /// On [route] at second [s] of a drive at 10 m/s from 200 m before its
  /// end, which arrives.
  NavFix nearEnd(NavRoute route, int s) =>
      fixOn(route, math.min(route.length - 200 + 10.0 * s, route.length));

  /// On [route] at 800 m for second 0, then 60 m to its right: off route.
  NavFix offRoute(NavRoute route, int s) {
    final on = route.pointAt(800.0 + s * 5);
    return NavFix(
      position: s == 0 ? on : offsetPoint(on, route.bearingAt(800) + 90, 60),
      accuracy: 5,
      speed: 5,
      time: now,
    );
  }

  /// Runs [seconds] of 60 fps frames, ticking the session (no map view
  /// does it here); [fixAt] may return a fix each second.
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
      now = now.add(const Duration(microseconds: 16667));
      session.tick(1 / 60);
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  /// Starts the trip from the overview and drives 4 s from 500 m.
  Future<void> startDriving(WidgetTester tester, NavRoute route) async {
    actions!.start();
    await tester.pump();
    await run(tester, 4, fixAt: (s) => fixOn(route, 500.0 + 10 * s));
  }

  /// Unmounts the widget, then disposes the flow (its night timer must be
  /// gone before the pending-timer check) and the session.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  }
}

/// A widget test with a [Harness] that is always cleaned up.
void scaffoldTest(
  String description,
  Future<void> Function(WidgetTester tester, Harness h) body, {
  RouteProvider? Function()? provider,
}) {
  testWidgets(description, (tester) async {
    final h = Harness(provider: provider?.call());
    try {
      await body(tester, h);
    } finally {
      await h.end(tester);
    }
  });
}

/// A provider whose every request waits on [pending].
class PendingRouteProvider extends RouteProvider {
  var requests = 0;
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
    requests++;
    pending = Completer();
    return pending.future;
  }
}

void main() {
  final route = sampleRoute;
  final alt = sampleRouteAlternatives.single;
  final from = route.points.first;
  final to = route.points.last;

  Finder key(String k) => find.byKey(ValueKey(k));

  /// The slots present now, among all of them.
  Set<String> slots() => {
    for (final k in [
      'idle',
      'panel',
      'header',
      'footer',
      'speed',
      'topEnd',
      'edge',
      'arrival',
      'recenter',
    ])
      if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) k,
  };

  group('slots by state', () {
    scaffoldTest('idle, overview, navigating and arrived', (tester, h) async {
      await h.mount(tester);
      expect(slots(), {'idle'});

      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      expect(slots(), {'panel'});
      expect(find.text('PANEL FlowOverview'), findsOneWidget);

      h.actions!.start();
      await tester.pump();
      // No guidance and no speed yet right after start.
      expect(h.session.guidanceState, isNull);
      expect(slots(), {'footer', 'topEnd', 'edge'});

      await h.run(tester, 4, fixAt: (s) => h.nearEnd(route, s));
      expect(h.flow.state.value, isA<FlowNavigating>());
      expect(slots(), {'header', 'footer', 'speed', 'topEnd', 'edge'});

      await h.run(tester, 16, fixAt: (s) => h.nearEnd(route, s + 4));
      expect(h.flow.state.value, isA<FlowArrived>());
      expect(slots(), {'arrival'});

      h.actions!.end();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(slots(), {'idle'});
    });

    late PendingRouteProvider pending;
    scaffoldTest('loading and error show the panel', (tester, h) async {
      await h.mount(tester);
      unawaited(h.flow.preview(from: from, to: to));
      await tester.pump();
      expect(h.flow.state.value, isA<FlowLoading>());
      expect(slots(), {'panel'});
      expect(find.text('PANEL FlowLoading'), findsOneWidget);

      pending.pending.completeError(Exception('offline'));
      await tester.pump();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowError>());
      expect(slots(), {'panel'});
      expect(find.text('PANEL FlowError'), findsOneWidget);
    }, provider: () => pending = PendingRouteProvider());
  });

  scaffoldTest('overview padding follows the panel, set only on change', (
    tester,
    h,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    await h.mount(tester, overviewMargin: 20);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.overviewPadding, const EdgeInsets.fromLTRB(20, 44, 20, 140));
    final sets = h.flow.paddingSets;
    expect(sets, 1);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets, reason: 'no change, no set');

    // A safe-area change that leaves the padding as it is (the panel
    // keeps the bottom inset itself).
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets, reason: 'same padding, no set');

    // Side insets (landscape): the routes keep clear of them.
    tester.view.padding = const FakeViewPadding(top: 24, left: 8, right: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets + 1);
    expect(h.flow.overviewPadding, const EdgeInsets.fromLTRB(28, 44, 24, 140));

    // A taller panel.
    h.panelHeight = 200;
    h.flow.select(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets + 2);
    expect(h.flow.overviewPadding, const EdgeInsets.fromLTRB(28, 44, 24, 220));

    // A new top inset.
    tester.view.padding = const FakeViewPadding(top: 40, left: 8, right: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.flow.paddingSets, sets + 3);
    expect(h.flow.overviewPadding, const EdgeInsets.fromLTRB(28, 60, 24, 220));
  });

  scaffoldTest('onMapReady refreshes the overview', (tester, h) async {
    h.flow.previewRoutes([route, alt]);
    h.map.clearRouteOptions(); // as a map attached after the preview
    await h.mount(tester, mapReady: false);
    expect(h.flow.refreshes, 0);
    expect(h.map.options, isNull);

    h.config.onMapReady();
    expect(h.flow.refreshes, 1);
    expect(h.map.options, [same(route), same(alt)]);
  });

  scaffoldTest('the fake map reports itself ready once', (tester, h) async {
    await h.mount(tester);
    expect(h.flow.refreshes, 1);
    h.flow.previewRoutes([route]);
    await tester.pump();
    expect(h.flow.refreshes, 1, reason: 'not on rebuilds');
  });

  group('back', () {
    scaffoldTest('in a preview closes it without popping; idle pops', (
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
      expect(find.byType(NavigationFlowScaffold), findsOneWidget);
      expect(find.text('HOME'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NavigationFlowScaffold), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    scaffoldTest('while loading cancels', (tester, h) async {
      await h.mount(tester, pushed: true);
      unawaited(h.flow.preview(from: from, to: to));
      await tester.pump();
      expect(h.flow.state.value, isA<FlowLoading>());
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(find.byType(NavigationFlowScaffold), findsOneWidget);
    }, provider: PendingRouteProvider.new);

    scaffoldTest('in the trip overview resumes the trip', (tester, h) async {
      await h.mount(tester, pushed: true);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      final running = h.session.route;
      h.flow.backToOverview();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowNavigating>());
      expect(h.session.route, same(running));
      expect(find.byType(NavigationFlowScaffold), findsOneWidget);
    });
  });

  group('retry', () {
    late PendingRouteProvider pending;
    scaffoldTest('a double retry runs one retry', (tester, h) async {
      await h.mount(tester);
      unawaited(h.flow.preview(from: from, to: to));
      pending.pending.completeError(Exception('offline'));
      await tester.pump();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowError>());
      final actions = h.actions!;
      actions.retry();
      expect(h.flow.state.value, isA<FlowLoading>());
      actions.retry();
      await tester.pump();
      expect(h.flow.retries, 1);
      expect(pending.requests, 2, reason: 'preview and one retry');
      expect(tester.takeException(), isNull);
    }, provider: () => pending = PendingRouteProvider());

    scaffoldTest('a failing retry is reported, not thrown', (tester, h) async {
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      await h.mount(tester);
      await h.flow.preview(from: from, to: to);
      await tester.pump();
      expect(h.flow.state.value, isA<FlowError>());
      h.flow.retryError = StateError('retry failed');
      h.actions!.retry();
      await tester.pump();
      await tester.pump();
      FlutterError.onError = old;
      expect(errors.map((e) => e.exception), [isA<StateError>()]);
      expect(h.flow.retries, 1);
    }, provider: () => FakeRouteProvider((_, _) => Future.error('offline')));
  });

  group('step sheet', () {
    scaffoldTest('follows the current step', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      h.actions!.start();
      await tester.pump();
      // Up to just before step 4 (at about 1983 m).
      await h.run(tester, 4, fixAt: (s) => h.fixOn(route, 1930.0 + 10 * s));
      final first = h.session.guidanceState!.stepIndex;
      h.actions!.showSteps();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('steps')), findsOneWidget);
      expect(h.stepRoute, same(route));
      expect(h.currentStep, first);

      await h.run(tester, 6, fixAt: (s) => h.fixOn(route, 1970.0 + 10 * s));
      final now = h.session.guidanceState!.stepIndex;
      expect(now, greaterThan(first));
      expect(h.currentStep, now);
    });

    scaffoldTest('closes on arrival', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      h.actions!.start();
      await tester.pump();
      await h.run(tester, 2, fixAt: (s) => h.nearEnd(route, s));
      expect(h.flow.state.value, isA<FlowNavigating>());
      h.actions!.showSteps();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('steps')), findsOneWidget);

      await h.run(tester, 18, fixAt: (s) => h.nearEnd(route, s + 2));
      expect(h.flow.state.value, isA<FlowArrived>());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('steps')), findsNothing);
      expect(
        find.byKey(const ValueKey('arrival')).hitTestable(),
        findsOneWidget,
      );
    });

    late NavRoute fresh;
    scaffoldTest(
      'closes on a reroute',
      (tester, h) async {
        await h.mount(tester);
        h.flow.previewRoutes([route]);
        await tester.pump();
        h.actions!.start();
        await tester.pump();
        await h.run(tester, 1, fixAt: (s) => h.offRoute(route, s));
        h.actions!.showSteps();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const ValueKey('steps')), findsOneWidget);

        await h.run(tester, 6, fixAt: (s) => h.offRoute(route, s + 1));
        expect(h.session.route, same(fresh), reason: 'rerouted');
        expect((h.flow.state.value as FlowNavigating).route, same(fresh));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const ValueKey('steps')), findsNothing);
      },
      provider: () => FakeRouteProvider((from, to) async {
        fresh = NavRoute.fromPoints([from, to]);
        return [fresh];
      }),
    );

    scaffoldTest('from the overview, with no current step', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route, alt], selected: 1);
      await tester.pump();
      h.actions!.showSteps();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.stepRoute, same(alt));
      expect(h.currentStep, -1);

      // Another selection is another route: the sheet closes.
      h.flow.select(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('steps')), findsNothing);
    });
  });

  group('recenter', () {
    scaffoldTest('shows only when not following, outside the overview', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      expect(h.session.follow, isTrue);
      expect(key('recenter'), findsNothing);

      h.flow.previewRoutes([route]);
      await tester.pump();
      expect(h.session.follow, isFalse);
      expect(key('recenter'), findsNothing, reason: 'the overview');

      await h.startDriving(tester, route);
      expect(key('recenter'), findsNothing, reason: 'following');

      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      expect(key('recenter'), findsOneWidget);

      await tester.tap(key('recenter'));
      await tester.pump();
      expect(h.session.follow, isTrue);
      expect(key('recenter'), findsNothing);
    });

    scaffoldTest('shows in idle after closing a preview', (tester, h) async {
      await h.mount(tester);
      h.session.start();
      h.flow.previewRoutes([route, alt]);
      await tester.pump();
      h.actions!.close!();
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      // No frame came (no fix): the state change alone shows it.
      expect(key('recenter'), findsOneWidget);
      await tester.tap(key('recenter'));
      await tester.pump();
      expect(h.session.follow, isTrue);
      expect(key('recenter'), findsNothing);
    });

    scaffoldTest('a touch on the map shows it at once', (tester, h) async {
      await h.mount(tester);
      h.session.start();
      expect(key('recenter'), findsNothing);
      // The map's own touch handler stops following; the scaffold sees it
      // through the session, whatever order the pointer listeners run in.
      await tester.tap(find.byType(FakeMapWidget));
      await tester.pump();
      expect(h.session.follow, isFalse);
      expect(key('recenter'), findsOneWidget);
    });

    scaffoldTest('an app change of follow shows without a frame or a touch', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      h.session.start();
      var frames = 0;
      final sub = h.session.frames.listen((_) => frames++);
      addTearDown(sub.cancel);
      // The change comes as a stream event (a microtask), then a frame.
      Future<void> settle() async {
        await tester.pump();
        await tester.pump();
      }

      h.session.follow = false;
      await settle();
      expect(key('recenter'), findsOneWidget);
      h.session.follow = true;
      await settle();
      expect(key('recenter'), findsNothing);
      expect(frames, 0, reason: 'no frame flowed');
    });
  });

  scaffoldTest('a null recenterBuilder shows no button and leaves no gap', (
    tester,
    h,
  ) async {
    await h.mount(tester, recenter: false);
    h.session.start();
    h.session.follow = false;
    await tester.tap(find.byType(FakeMapWidget));
    await tester.pump();
    expect(key('recenter'), findsNothing, reason: 'idle, not following');

    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    h.session.follow = false;
    await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
    expect(key('recenter'), findsNothing, reason: 'navigating, not following');
    final footer = tester.getRect(key('footer'));
    final speed = tester.getRect(key('speed'));
    expect(speed.bottom, closeTo(footer.top - 16, 1));

    // The block of the start side is the speed alone: no 8 spacing.
    final block = tester.getRect(
      find.ancestor(of: key('speed'), matching: find.byType(Column)).first,
    );
    expect(block.height, closeTo(speed.height, 1));
    expect(tester.takeException(), isNull);
  });

  scaffoldTest('the top end slot gets guarded actions', (tester, h) async {
    var ended = 0;
    await h.mount(tester, onEnd: () => ended++);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    final stale = h.topEndActions!;
    stale.end();
    expect(ended, 1);

    h.flow.stop();
    await tester.pump();
    expect(h.flow.state.value, isA<FlowIdle>());
    stale.end();
    stale.backToOverview();
    expect(ended, 1, reason: 'a stale action does nothing');
    expect(h.flow.state.value, isA<FlowIdle>());
  });

  scaffoldTest('the header gets guarded actions', (tester, h) async {
    var ended = 0;
    await h.mount(tester, onEnd: () => ended++);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    final stale = h.headerActions!;
    stale.end();
    expect(ended, 1);

    h.flow.stop();
    await tester.pump();
    stale.end();
    stale.showSteps();
    await tester.pump();
    expect(ended, 1, reason: 'a stale action does nothing');
    expect(key('steps'), findsNothing);
  });

  scaffoldTest('changing overviewMargin on rebuild re-applies the padding', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.pump();
    expect(h.flow.overviewPadding.left, 32);
    final sets = h.flow.paddingSets;

    await tester.pumpWidget(h.app(overviewMargin: 8));
    await tester.pump();
    await tester.pump();
    expect(h.flow.overviewPadding.left, 8);
    expect(h.flow.overviewPadding.right, 8);
    expect(h.flow.overviewPadding.bottom, h.panelHeight + 8);
    expect(h.flow.paddingSets, sets + 1);

    // The same margin sets nothing more.
    await tester.pumpWidget(h.app(overviewMargin: 8));
    await tester.pump();
    await tester.pump();
    expect(h.flow.paddingSets, sets + 1);
  });

  scaffoldTest('the map builds once across progress ticks, again at night', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    var ticks = 0;
    void count() => ticks++;
    h.flow.tripProgress.addListener(count);
    addTearDown(() => h.flow.tripProgress.removeListener(count));
    final builds = h.configs.length;
    await h.run(tester, 3.5, fixAt: (s) => h.fixOn(route, 540.0 + 10 * s));
    expect(ticks, greaterThanOrEqualTo(3));
    expect(h.configs, hasLength(builds), reason: 'no rebuild for progress');
    expect(h.config.isNight, isFalse);

    h.flow.nightMode = NightMode.alwaysNight;
    await tester.pump();
    expect(h.configs, hasLength(builds + 1));
    expect(h.config.isNight, isTrue);
  });

  scaffoldTest('a route option tap selects only in the overview', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    h.config.onRouteOptionTap(1);
    expect(h.flow.state.value, isA<FlowIdle>());

    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    h.config.onRouteOptionTap(1);
    expect((h.flow.state.value as FlowOverview).selected, 1);

    h.actions!.start();
    await tester.pump();
    final navigating = h.flow.state.value;
    h.config.onRouteOptionTap(0);
    expect(h.flow.state.value, same(navigating));
    expect(tester.takeException(), isNull);
  });

  scaffoldTest('actions in the wrong state do nothing', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    final overview = h.actions!;
    expect(overview.close, isNotNull, reason: 'a preview');
    overview.start();
    await tester.pump();
    final navigating = h.flow.state.value as FlowNavigating;
    // Stale overview actions.
    overview.select(1);
    overview.start();
    overview.cancel();
    overview.close!();
    overview.retry();
    expect(h.flow.state.value, same(navigating));

    h.actions!.backToOverview();
    await tester.pump();
    expect(h.flow.isTripOverview, isTrue);
    expect(h.actions!.close, isNull, reason: 'the trip overview');
    expect(tester.takeException(), isNull);
  });

  group('layout', () {
    scaffoldTest('slots around the header and the footer', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final header = tester.getRect(key('header'));
      final footer = tester.getRect(key('footer'));
      final speed = tester.getRect(key('speed'));
      final recenter = tester.getRect(key('recenter'));
      final topEnd = tester.getRect(key('topEnd'));
      final edge = tester.getRect(key('edge'));
      expect(speed.bottom, closeTo(footer.top - 16, 1));
      expect(speed.left, closeTo(16, 1));
      expect(recenter.bottom, lessThanOrEqualTo(speed.top));
      expect(recenter.left, closeTo(16, 1));
      expect(topEnd.top, greaterThanOrEqualTo(header.bottom));
      expect(topEnd.right, closeTo(400 - 16, 1));
      expect(edge.top, greaterThanOrEqualTo(header.bottom));
      expect(edge.left, lessThan(16));
    });

    scaffoldTest('recenter at the bottom end sits above the speed band', (
      tester,
      h,
    ) async {
      await h.mount(tester, recenterAlignment: AlignmentDirectional.bottomEnd);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final footer = tester.getRect(key('footer'));
      final speed = tester.getRect(key('speed'));
      final recenter = tester.getRect(key('recenter'));
      expect(speed.bottom, closeTo(footer.top - 16, 1));
      expect(recenter.bottom, closeTo(speed.top - 16, 1));
      expect(recenter.right, closeTo(400 - 16, 1));
    });

    scaffoldTest('without a speed the bottom-end recenter sits above the '
        'footer', (tester, h) async {
      await h.mount(
        tester,
        recenterAlignment: AlignmentDirectional.bottomEnd,
        speed: false,
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      expect(key('speed'), findsNothing);
      final footer = tester.getRect(key('footer'));
      final recenter = tester.getRect(key('recenter'));
      expect(recenter.bottom, closeTo(footer.top - 16, 1));
      expect(recenter.right, closeTo(400 - 16, 1));
    });

    scaffoldTest('a speed as wide as the screen: the bottom-end recenter '
        'does not cover it', (tester, h) async {
      await h.mount(
        tester,
        size: const Size(320, 640),
        recenterAlignment: AlignmentDirectional.bottomEnd,
        speedText: 'SPEED 88 km/h limit 90',
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final speed = tester.getRect(key('speed'));
      final recenter = tester.getRect(key('recenter'));
      // The speed and the button would share a row at the bottom.
      expect(speed.right, greaterThan(recenter.left));
      expect(recenter.overlaps(speed), isFalse);
      expect(recenter.bottom, closeTo(speed.top - 16, 1));
      expect(tester.takeException(), isNull);
    });
  });

  scaffoldTest('the map gets the height of what covers its bottom', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    final height = h.config.bottomOverlayHeight;
    expect(height.value, 0, reason: 'idle');

    h.flow.previewRoutes([route]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(height.value, 120, reason: 'the panel');
    expect(h.config.bottomOverlayHeight, same(height));

    h.actions!.start();
    await tester.pump();
    await h.run(tester, 4, fixAt: (s) => h.nearEnd(route, s));
    expect(key('speed'), findsOneWidget);
    // The footer and the speed's band above it (re-review R1): the map's
    // start-side attribution keeps above the speed too.
    expect(
      height.value,
      greaterThanOrEqualTo(800 - tester.getRect(key('speed')).top),
      reason: 'the speed band',
    );
    expect(
      height.value,
      tester.getSize(key('footer')).height +
          tester.getSize(key('speed')).height +
          16,
    );

    await h.run(tester, 16, fixAt: (s) => h.nearEnd(route, s + 4));
    expect(h.flow.state.value, isA<FlowArrived>());
    await tester.pump(const Duration(milliseconds: 16));
    expect(height.value, tester.getSize(key('arrival')).height);

    h.actions!.end();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(height.value, 0, reason: 'idle again');
  });

  scaffoldTest('without a speed the map gets the footer height only', (
    tester,
    h,
  ) async {
    await h.mount(tester, speed: false);
    final height = h.config.bottomOverlayHeight;
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    expect(key('speed'), findsNothing);
    expect(height.value, tester.getSize(key('footer')).height);

    h.actions!.backToOverview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(height.value, 120, reason: 'the panel again');
  });

  scaffoldTest('with a speed, back to the overview drops the speed band', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    final height = h.config.bottomOverlayHeight;
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    expect(key('speed'), findsOneWidget);
    expect(
      height.value,
      greaterThanOrEqualTo(800 - tester.getRect(key('speed')).top),
    );

    h.actions!.backToOverview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(key('speed'), findsNothing);
    expect(height.value, 120, reason: 'the panel only');
  });

  for (final alignment in [
    AlignmentDirectional.bottomCenter,
    AlignmentDirectional.bottomEnd,
    AlignmentDirectional.centerStart,
  ]) {
    scaffoldTest('a wide speed: the recenter at $alignment does not cover '
        'it (re-review R2)', (tester, h) async {
      await h.mount(
        tester,
        size: const Size(1600, 900),
        recenterAlignment: alignment,
        speedText: 'SPEED 88 km/h limit 90',
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final speed = tester.getRect(key('speed'));
      final recenter = tester.getRect(key('recenter'));
      expect(recenter.overlaps(speed), isFalse, reason: '$recenter $speed');
      expect(recenter.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  }

  group('safe area', () {
    for (final alignment in [
      AlignmentDirectional.bottomStart,
      AlignmentDirectional.bottomEnd,
    ]) {
      scaffoldTest('side insets: the overlays keep inside them ($alignment)', (
        tester,
        h,
      ) async {
        tester.view
          ..padding = const FakeViewPadding(left: 47, right: 47, bottom: 21)
          ..viewPadding = const FakeViewPadding(
            left: 47,
            right: 47,
            bottom: 21,
          );
        await h.mount(
          tester,
          size: const Size(1600, 900),
          recenterAlignment: alignment,
          speedText: 'S',
        );
        h.flow.previewRoutes([route]);
        await tester.pump();
        await h.startDriving(tester, route);
        h.session.follow = false;
        await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
        final speed = tester.getRect(key('speed'));
        final recenter = tester.getRect(key('recenter'));
        final topEnd = tester.getRect(key('topEnd'));
        final edge = tester.getRect(key('edge'));
        expect(speed.left, closeTo(47 + 16, 1));
        expect(edge.left, closeTo(47 + 8, 1));
        expect(topEnd.right, closeTo(1600 - 47 - 16, 1));
        if (alignment == AlignmentDirectional.bottomEnd) {
          expect(recenter.right, closeTo(1600 - 47 - 16, 1));
        } else {
          expect(recenter.left, closeTo(47 + 16, 1));
        }
        expect(recenter.overlaps(speed), isFalse);
      });

      scaffoldTest('idle: the recenter keeps above the bottom inset '
          '($alignment)', (tester, h) async {
        tester.view
          ..padding = const FakeViewPadding(top: 47, bottom: 34)
          ..viewPadding = const FakeViewPadding(top: 47, bottom: 34);
        await h.mount(tester, recenterAlignment: alignment);
        h.session.follow = false;
        await tester.tapAt(const Offset(200, 400));
        await tester.pump();
        final recenter = tester.getRect(key('recenter'));
        expect(recenter.bottom, closeTo(800 - 34 - 16, 1));
      });
    }

    scaffoldTest('a footer lower than the bottom inset: the speed and the '
        'recenter share one bottom', (tester, h) async {
      // The fixture's footer has no SafeArea and is lower than the inset.
      tester.view
        ..padding = const FakeViewPadding(bottom: 100)
        ..viewPadding = const FakeViewPadding(bottom: 100);
      await h.mount(
        tester,
        size: const Size(1600, 900),
        recenterAlignment: AlignmentDirectional.bottomEnd,
        speedText: 'S',
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final footer = tester.getRect(key('footer'));
      final speed = tester.getRect(key('speed'));
      final recenter = tester.getRect(key('recenter'));
      expect(footer.height, lessThan(100), reason: 'the case under test');
      expect(recenter.overlaps(speed), isFalse);
      expect(speed.right, lessThan(recenter.left), reason: 'beside');
      expect(speed.bottom, closeTo(900 - 100 - 16, 1));
      expect(recenter.bottom, closeTo(speed.bottom, 1));
      expect(
        h.config.bottomOverlayHeight.value,
        closeTo(100 + speed.height + 16, 1),
      );
    });

    scaffoldTest('right to left: start and end follow the text direction', (
      tester,
      h,
    ) async {
      tester.view
        ..padding = const FakeViewPadding(left: 47, right: 20)
        ..viewPadding = const FakeViewPadding(left: 47, right: 20);
      tester.view
        ..physicalSize = const Size(1600, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        h.app(
          recenterAlignment: AlignmentDirectional.bottomEnd,
          speedText: 'S',
          textDirection: TextDirection.rtl,
        ),
      );
      await tester.pump();
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      // The start is on the right, behind the right inset.
      expect(tester.getRect(key('speed')).right, closeTo(1600 - 20 - 16, 1));
      expect(tester.getRect(key('edge')).right, closeTo(1600 - 20 - 8, 1));
      expect(tester.getRect(key('recenter')).left, closeTo(47 + 16, 1));
      expect(tester.getRect(key('topEnd')).left, closeTo(47 + 16, 1));
    });
  });

  for (final (height, placement) in [
    (300.0, 'above'),
    (200.0, 'beside'),
    (150.0, 'hidden'),
  ]) {
    scaffoldTest('a low screen ($height): the bottom-start recenter is '
        '$placement (the speed), never on the header', (tester, h) async {
      await h.mount(tester, size: Size(1600, height), speedText: 'S');
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final header = tester.getRect(key('header'));
      final speed = tester.getRect(key('speed'));
      final footer = tester.getRect(key('footer'));
      expect(speed.bottom, closeTo(footer.top - 16, 1));
      if (placement == 'hidden') {
        expect(key('recenter'), findsNothing);
        return;
      }
      final recenter = tester.getRect(key('recenter'));
      expect(recenter.top, greaterThanOrEqualTo(header.bottom));
      expect(recenter.overlaps(speed), isFalse);
      if (placement == 'above') {
        expect(recenter.bottom, closeTo(speed.top - 8, 1));
      } else {
        expect(recenter.left, closeTo(speed.right + 8, 1));
        expect(recenter.bottom, closeTo(speed.bottom, 1));
      }
    });
  }

  scaffoldTest('the speed does not move between its first frames (review '
      'm2)', (tester, h) async {
    await h.mount(tester);
    h.flow.previewRoutes([route]);
    await tester.pump();
    h.actions!.start();
    await tester.pump();
    Rect? first;
    for (var i = 0; i < 4 * 60 && first == null; i++) {
      if (i % 60 == 0) h.source.add(h.fixOn(route, 500.0 + 10 * (i ~/ 60)));
      h.now = h.now.add(const Duration(microseconds: 16667));
      h.session.tick(1 / 60);
      await tester.pump(const Duration(microseconds: 16667));
      if (key('speed').evaluate().isNotEmpty) {
        first = tester.getRect(key('speed'));
      }
    }
    expect(first, isNotNull, reason: 'the speed showed');
    await tester.pump(const Duration(microseconds: 16667));
    expect(tester.getRect(key('speed')), first);
    final footer = tester.getRect(key('footer'));
    expect(first!.bottom, closeTo(footer.top - 16, 1));
  });

  scaffoldTest('the recenter never covers the header, also on its first '
      'frame (review m1)', (tester, h) async {
    await h.mount(tester, size: const Size(1600, 200), speedText: 'S');
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    h.session.follow = false;
    final header = tester.getRect(key('header'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(microseconds: 16667));
      if (key('recenter').evaluate().isEmpty) continue;
      final recenter = tester.getRect(key('recenter'));
      expect(
        recenter.top,
        greaterThanOrEqualTo(header.bottom),
        reason: 'frame $i: $recenter',
      );
    }
    expect(key('recenter'), findsOneWidget);
  });

  scaffoldTest('a hidden recenter comes back when the text scale shrinks '
      '(review m1)', (tester, h) async {
    Future<void> show(double scale) async {
      await tester.pumpWidget(
        h.app(speedText: 'S', textScaler: TextScaler.linear(scale)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
    }

    // At 0.3x the pieces are about 14 high: the button fits above the
    // speed on 1600x100, but a 1.5x button (72 high) fits nowhere.
    tester.view
      ..physicalSize = const Size(1600, 100)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(speedText: 'S', textScaler: const TextScaler.linear(0.3)),
    );
    await tester.pump();
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    h.session.follow = false;
    await show(0.3);
    await show(1.5);
    expect(key('recenter'), findsNothing, reason: 'fits nowhere at 1.5x');
    await show(0.3);
    expect(key('recenter'), findsOneWidget, reason: 'fits again');
    final recenter = tester.getRect(key('recenter'));
    expect(
      recenter.top,
      greaterThanOrEqualTo(tester.getRect(key('header')).bottom),
    );
  });

  scaffoldTest('a speed piece that shows nothing takes no space', (
    tester,
    h,
  ) async {
    await h.mount(tester, emptySpeed: true);
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    h.session.follow = false;
    await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
    expect(key('speed'), findsOneWidget);
    final footer = tester.getRect(key('footer'));
    final recenter = tester.getRect(key('recenter'));
    // No 8 above an empty speed, no band for it.
    expect(recenter.bottom, closeTo(footer.top - 16, 1));
    expect(h.config.bottomOverlayHeight.value, closeTo(footer.height, 1));
  });

  scaffoldTest('320 dp at 2x text with long texts does not overflow', (
    tester,
    h,
  ) async {
    await h.mount(
      tester,
      size: const Size(320, 640),
      textScaler: const TextScaler.linear(2),
      long: true,
    );
    expect(tester.takeException(), isNull, reason: 'idle');
    h.flow.previewRoutes([route, alt]);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'overview');
    h.actions!.start();
    await tester.pump();
    await h.run(tester, 4, fixAt: (s) => h.nearEnd(route, s));
    h.session.follow = false;
    await h.run(tester, 0.1);
    expect(
      slots(),
      containsAll(['header', 'footer', 'speed', 'topEnd', 'edge']),
    );
    // The texts are taller than the screen: the recenter fits nowhere, so
    // it is hidden rather than cover the header.
    expect(key('recenter'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'navigating');
    // Inside the screen horizontally. (The fixture's texts have no
    // Material ancestor, so they use the 48 px fallback style and are far
    // taller than the screen: only the width is meaningful.)
    final topEnd = tester.getRect(key('topEnd'));
    final edge = tester.getRect(key('edge'));
    expect(topEnd.left, greaterThanOrEqualTo(0), reason: '$topEnd');
    expect(topEnd.right, lessThanOrEqualTo(320), reason: '$topEnd');
    expect(topEnd.width, lessThanOrEqualTo(320 - 32));
    expect(edge.left, greaterThanOrEqualTo(0), reason: '$edge');
    expect(edge.right, lessThanOrEqualTo(320), reason: '$edge');
    expect(edge.width, lessThanOrEqualTo(48));
    await h.run(tester, 16, fixAt: (s) => h.nearEnd(route, s + 4));
    expect(h.flow.state.value, isA<FlowArrived>());
    expect(tester.takeException(), isNull, reason: 'arrived');
  });
}
