import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// A fix source the test feeds by hand.
class FlowFixSource implements FixSource {
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

/// A map that records its camera moves and route options.
class RecordingMap
    implements NavigationMap, RoutePreviewMap, AlternateRoutesMap {
  /// Every camera target the map was sent, in order.
  final cameraMoves = <CameraTarget>[];

  /// The route options shown; null once cleared.
  List<NavRoute>? options;

  /// When set, [moveCamera] throws it.
  Object? cameraError;

  @override
  Future<void> moveCamera(CameraTarget target) async {
    if (cameraError != null) throw cameraError!;
    cameraMoves.add(target);
  }

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

  /// The alternates shown; null once cleared (or never shown).
  List<AlternateRoute>? shownAlternates;

  /// The tap callback of the last [showAlternates].
  void Function(int index)? alternateTap;

  /// How many times [showAlternates] was called.
  var alternateShows = 0;

  @override
  void showAlternates(
    List<AlternateRoute> alternates, {
    required void Function(int index) onTap,
  }) {
    shownAlternates = alternates;
    alternateTap = onTap;
    alternateShows++;
  }

  @override
  void clearAlternates() => shownAlternates = null;
}

/// A map that only draws the route.
class PlainMap implements NavigationMap {
  @override
  Future<void> moveCamera(CameraTarget target) async {}
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {}
  @override
  void clearRoute() {}
}

/// A provider driven by [handler]. It records the flow's requests
/// ([routes]: previews and alternates) and counts the session's reroutes
/// ([route]). [routesHandler], when set, answers [routes] instead.
class CountingRouteProvider extends RouteProvider {
  CountingRouteProvider(this.handler, {this.routesHandler});

  Future<List<NavRoute>> Function(GeoPoint from, GeoPoint to) handler;
  Future<List<NavRoute>> Function(GeoPoint from, GeoPoint to)? routesHandler;

  final requests = <({GeoPoint from, GeoPoint to, int maxAlternatives})>[];
  var reroutes = 0;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async {
    reroutes++;
    return (await handler(from, to)).first;
  }

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) {
    requests.add((from: from, to: to, maxAlternatives: maxAlternatives));
    return (routesHandler ?? handler)(from, to);
  }
}

/// Where the test routes start, in Ho Chi Minh City.
const testOrigin = GeoPoint(10.77, 106.70);

/// Points every 50 m for [length] m from [from] along [bearing].
List<GeoPoint> straight(GeoPoint from, double bearing, double length) => [
  for (var d = 0.0; d <= length + 1e-6; d += 50) offsetPoint(from, bearing, d),
];

/// 3000 m due north at 10 m/s: depart, turns at 1000 m and 2000 m, arrive.
NavRoute northRoute() => NavRoute.fromPoints(
  straight(testOrigin, 0, 3000),
  name: 'north',
  fallbackSpeed: 10,
  steps: const [
    RouteStepSeed.atVertex(0, type: ManeuverType.depart, roadName: 'Start'),
    RouteStepSeed.atVertex(
      20,
      type: ManeuverType.turn,
      modifier: ManeuverModifier.right,
      roadName: 'First Street',
    ),
    RouteStepSeed.atVertex(
      40,
      type: ManeuverType.turn,
      modifier: ManeuverModifier.left,
      roadName: 'Second Street',
    ),
    RouteStepSeed.atVertex(60, type: ManeuverType.arrive),
  ],
);

/// [northRoute]'s road up to [at] m, then [length] m north-east, at
/// [speed] m/s, with no steps.
NavRoute branchRoute(double at, {double length = 900, double speed = 10}) {
  final fork = offsetPoint(testOrigin, 0, at);
  return NavRoute.fromPoints(
    [...straight(testOrigin, 0, at), ...straight(fork, 45, length).skip(1)],
    name: 'branch',
    fallbackSpeed: speed,
  );
}

/// A session and a flow on a fake clock, with no widget: [run] ticks the
/// session and pumps the fake time.
class FlowHarness {
  FlowHarness({
    RouteProvider? provider,
    NavigationMap? map,
    bool fetchAlternatesOnReroute = true,
  }) : map = map ?? RecordingMap() {
    session = NavigationSession(
      fixes: source,
      map: this.map,
      routeProvider: provider,
      clock: () => now,
    );
    flow = NavigationFlowController(
      session: session,
      routeProvider: provider,
      nightMode: NightMode.alwaysDay,
      clock: () => now,
      fetchAlternatesOnReroute: fetchAlternatesOnReroute,
    );
  }

  final source = FlowFixSource();
  final NavigationMap map;
  late final NavigationSession session;
  late final NavigationFlowController flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);

  /// [map] as a [RecordingMap] (the default).
  RecordingMap get recording => map as RecordingMap;

  NavFix fixOn(NavRoute route, double s, {double speed = 10}) => NavFix(
    position: route.pointAt(s),
    accuracy: 5,
    speed: speed,
    heading: route.bearingAt(s),
    time: now,
  );

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

  /// Runs [seconds] of 60 fps frames; [fixAt] may return a fix each second.
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

  /// Drives the last 40 m of [route] until it arrives.
  Future<void> arriveOn(WidgetTester tester, NavRoute route) => run(
    tester,
    8,
    fixAt: (s) => fixOn(route, route.length - 40 + 8.0 * s, speed: 8),
  );

  void dispose() {
    flow.dispose();
    session.dispose();
  }
}

/// A widget test with a [FlowHarness] that is disposed before the
/// pending-timer check.
void flowTest(
  String description,
  Future<void> Function(WidgetTester tester, FlowHarness h) body, {
  RouteProvider? Function()? provider,
  NavigationMap Function()? map,
  bool fetchAlternatesOnReroute = true,
}) {
  testWidgets(description, (tester) async {
    final h = FlowHarness(
      provider: provider?.call(),
      map: map?.call(),
      fetchAlternatesOnReroute: fetchAlternatesOnReroute,
    );
    try {
      await body(tester, h);
    } finally {
      h.dispose();
    }
  });
}

/// Collects [FlutterError] reports until the test ends.
List<FlutterErrorDetails> collectFlutterErrors() {
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  // The test framework's own reports go on to the previous handler: it
  // fails the test. Collecting them here would leave it hanging.
  FlutterError.onError = (details) =>
      details.library == 'Flutter test framework'
      ? old?.call(details)
      : errors.add(details);
  addTearDown(() => FlutterError.onError = old);
  return errors;
}
