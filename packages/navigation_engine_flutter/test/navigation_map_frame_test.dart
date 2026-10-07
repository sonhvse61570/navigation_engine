import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

class FakeFixSource implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  var starts = 0, stops = 0;
  bool _running = false;
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() {
    starts++;
    _running = true;
  }

  @override
  void stop() {
    stops++;
    _running = false;
  }

  @override
  void dispose() {}
  void add(NavFix fix) => _controller.add(fix);
}

class FakeMap implements NavigationMap, VehicleMarkerMap {
  final moves = <CameraTarget>[];
  final shown = <(GeoPoint, double)>[];
  var hides = 0;
  @override
  Future<void> moveCamera(CameraTarget target) async => moves.add(target);
  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {}
  @override
  void clearRoute() {}
  @override
  void showVehicle(GeoPoint position, double bearing) =>
      shown.add((position, bearing));
  @override
  void hideVehicle() => hides++;
}

void main() {
  late FakeFixSource source;
  late FakeMap map;
  late NavigationSession session;
  EdgeInsets? lastPadding;

  /// Created inside each test body: the session's streams must live in the
  /// test's fake-async zone for `pump` to deliver their events.
  void newSession() {
    source = FakeFixSource();
    map = FakeMap();
    session = NavigationSession(fixes: source, map: map)
      ..start(route: sampleRoute);
    lastPadding = null;
    addTearDown(session.dispose);
  }

  NavFix fixAt(double s) => NavFix(
    position: sampleRoute.pointAt(s),
    accuracy: 5,
    speed: 10,
    heading: sampleRoute.bearingAt(s),
    time: DateTime.now(),
  );

  Widget frame({NavigationSession? withSession, FakeMap? markers}) =>
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: NavigationMapFrame(
            session: withSession ?? session,
            vehicleMarkers: markers ?? map,
            mapBuilder: (context, padding) {
              lastPadding = padding;
              return const ColoredBox(key: Key('map'), color: Colors.grey);
            },
          ),
        ),
      );

  test('focusPadding puts the centre at the focus point', () {
    const size = Size(400, 800);
    final low = focusPadding(size, 0.7);
    expect(low.top, closeTo(320, 1e-9));
    expect(low.bottom, 0);
    expect(focusPadding(size, 0.5), EdgeInsets.zero);
    final high = focusPadding(size, 0.25);
    expect(high.top, 0);
    expect(high.bottom, closeTo(400, 1e-9));
    expect(focusPadding(size, 2).top, closeTo(800, 1e-9));
  });

  testWidgets('ticks the session every frame and passes the padding', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(frame());
    source.add(fixAt(500));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(session.frame, isNotNull);
    expect(map.moves, isNotEmpty);
    expect(
      lastPadding,
      focusPadding(tester.getSize(find.byKey(const Key('map'))), 0.7),
    );
  });

  testWidgets('touching the map stops following; recenter resumes', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(frame());
    source.add(fixAt(500));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CarPuck), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsNothing);

    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.follow, isFalse);
    expect(find.byType(CarPuck), findsNothing);
    expect(find.byTooltip('Recenter'), findsOneWidget);

    await tester.tap(find.byTooltip('Recenter'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.follow, isTrue);
    expect(find.byType(CarPuck), findsOneWidget);
    expect(map.hides, 1);
  });

  testWidgets(
    'draws the vehicle marker ~10 times a second while not following',
    (tester) async {
      newSession();
      await tester.pumpWidget(frame());
      source.add(fixAt(500));
      await tester.pump(const Duration(milliseconds: 16));
      expect(map.shown, isEmpty);
      await tester.tap(find.byKey(const Key('map')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(map.shown.length, inInclusiveRange(9, 11));
      final moves = map.moves.length;
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        map.moves.length,
        moves,
        reason: 'camera stays put while not following',
      );
    },
  );

  testWidgets('pauses the session in the background and resumes it', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(frame());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(session.isPaused, isTrue);
    expect(source.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(session.isPaused, isFalse);
    expect(source.starts, 2);
  });

  testWidgets('does not resume a session the app paused itself', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(frame());
    session.pause();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(session.isPaused, isTrue);
  });

  testWidgets('CarPuck.toPngBytes renders a PNG of the requested size', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => CarPuck.toPngBytes(size: 20, pixelRatio: 2),
    );
    expect(bytes!.sublist(1, 4), 'PNG'.codeUnits);
    // IHDR width/height (big-endian) at bytes 16..23.
    expect(bytes[19], 40);
    expect(bytes[23], 40);
  });

  testWidgets('follows the session when the app changes session.follow', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(frame());
    source.add(fixAt(500));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CarPuck), findsOneWidget);

    session.follow = false;
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byTooltip('Recenter'), findsOneWidget);
    expect(find.byType(CarPuck), findsNothing);

    session.follow = true;
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CarPuck), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsNothing);
    expect(map.hides, 1);

    // The frame is back in sync: touching the map still turns follow off.
    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.follow, isFalse);
    expect(find.byTooltip('Recenter'), findsOneWidget);
  });

  testWidgets('a touch turns follow off after the app set it to true', (
    tester,
  ) async {
    newSession();
    session.follow = false;
    await tester.pumpWidget(frame());
    session.follow = true; // frame still believes "not following"
    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.follow, isFalse);
    expect(find.byTooltip('Recenter'), findsOneWidget);
  });

  testWidgets('swapping the session hides the old marker and resyncs follow', (
    tester,
  ) async {
    newSession();
    final markersA = map;
    await tester.pumpWidget(frame());
    source.add(fixAt(500));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CarPuck), findsNothing);
    expect(markersA.hides, 0);

    final source2 = FakeFixSource();
    final markersB = FakeMap();
    final session2 = NavigationSession(fixes: source2, map: markersB)
      ..start(route: sampleRoute);
    addTearDown(session2.dispose);
    await tester.pumpWidget(frame(withSession: session2, markers: markersB));
    expect(markersA.hides, 1);
    expect(find.byType(CarPuck), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsNothing);
  });

  testWidgets('swapping only the vehicle markers hides the old ones', (
    tester,
  ) async {
    newSession();
    final markersA = map;
    await tester.pumpWidget(frame());
    await tester.pumpWidget(frame(markers: FakeMap()));
    expect(markersA.hides, 1);
  });

  testWidgets('swapping the session resumes the one the frame paused', (
    tester,
  ) async {
    newSession();
    final session1 = session;
    final source1 = source;
    await tester.pumpWidget(frame());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(session1.isPaused, isTrue);

    final session2 = NavigationSession(fixes: FakeFixSource(), map: FakeMap())
      ..start(route: sampleRoute);
    addTearDown(session2.dispose);
    await tester.pumpWidget(frame(withSession: session2));
    expect(session1.isPaused, isFalse);
    expect(source1.starts, 2);
  });

  testWidgets('removing the frame resumes a session it paused', (tester) async {
    newSession();
    await tester.pumpWidget(frame());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(session.isPaused, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(session.isPaused, isFalse);
  });
  testWidgets('the recenter button does not clash with the app\'s own FAB', (
    tester,
  ) async {
    newSession();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          body: NavigationMapFrame(
            session: session,
            vehicleMarkers: map,
            mapBuilder: (context, padding) =>
                const ColoredBox(key: Key('map'), color: Colors.grey),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byTooltip('Recenter'), findsOneWidget);

    // Fixed pumps: the frame's ticker never lets pumpAndSettle settle.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Recenter'), findsOneWidget);
  });

  testWidgets('the recenter tooltip is configurable', (tester) async {
    newSession();
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapFrame(
          session: session,
          vehicleMarkers: map,
          recenterTooltip: 'Recentrer',
          mapBuilder: (context, padding) =>
              const ColoredBox(key: Key('map'), color: Colors.grey),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('map')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byTooltip('Recentrer'), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsNothing);
  });
}
