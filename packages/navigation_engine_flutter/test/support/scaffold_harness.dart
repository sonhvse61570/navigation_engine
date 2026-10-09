import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
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

  var alternateRefreshes = 0;

  @override
  void refreshAlternates() {
    alternateRefreshes++;
    super.refreshAlternates();
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

const longText =
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

  /// When set, the header and the footer are boxes this high instead of
  /// their texts; a test changes them before a rebuild.
  double? headerHeight;
  double? footerHeight;

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
    bool bottomEnd = false,
    double? topEndHeight,
    bool arrivalHeader = false,
    bool recenterReplacesSpeed = false,
    bool landscapeSidePanel = false,
  }) {
    Widget text(String key, String value) =>
        Text(long ? '$value $longText' : value, key: ValueKey(key));
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
        final height = headerHeight;
        return height == null
            ? text('header', 'HEADER ${guidance.stepIndex}')
            : SizedBox(key: const ValueKey('header'), height: height);
      },
      footerBuilder: (context, progress, rerouting, actions) {
        this.actions = actions;
        final height = footerHeight;
        return height == null
            ? text('footer', 'FOOTER $rerouting')
            : SizedBox(key: const ValueKey('footer'), height: height);
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
        final height = topEndHeight;
        return height == null
            ? text('topEnd', 'TOPEND')
            : SizedBox(
                key: const ValueKey('topEnd'),
                width: 48,
                height: height,
              );
      },
      bottomEndBuilder: bottomEnd
          ? (context, actions) => const SizedBox(
              key: ValueKey('bottomEnd'),
              width: 48,
              height: 48,
            )
          : null,
      arrivalHeaderBuilder: arrivalHeader
          ? (context, state) =>
                text('arrivalHeader', 'ARRIVED ${state.destination?.name}')
          : null,
      recenterReplacesSpeed: recenterReplacesSpeed,
      landscapeSidePanel: landscapeSidePanel,
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
    TextDirection? textDirection,
    bool bottomEnd = false,
    double? topEndHeight,
    bool arrivalHeader = false,
    bool recenterReplacesSpeed = false,
    bool landscapeSidePanel = false,
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
        textDirection: textDirection,
        bottomEnd: bottomEnd,
        topEndHeight: topEndHeight,
        arrivalHeader: arrivalHeader,
        recenterReplacesSpeed: recenterReplacesSpeed,
        landscapeSidePanel: landscapeSidePanel,
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
