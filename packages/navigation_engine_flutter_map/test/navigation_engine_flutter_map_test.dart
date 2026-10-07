// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
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
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => true;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
  void add(NavFix fix) => _controller.add(fix);
}

NavFix fixAt(double meters) => NavFix(
  position: sampleRoute.pointAt(meters),
  accuracy: 5,
  speed: 10,
  heading: sampleRoute.bearingAt(meters),
  time: DateTime.now(),
);

Widget app(
  NavigationSession session, {
  Widget puck = const CarPuck(),
  double markerSize = 44,
  void Function(fm.MapController controller)? onMapReady,
}) => MaterialApp(
  home: FlutterMapNavigationView(
    session: session,
    initialCenter: sampleRoute.points.first,
    userAgentPackageName: 'dev.navigationengine.test',
    tileUrlTemplate: '',
    puck: puck,
    markerSize: markerSize,
    onMapReady: onMapReady,
  ),
);

/// Pans so the view shows the vehicle marker, and returns that marker.
Future<fm.Marker> pannedMarker(
  WidgetTester tester,
  NavigationSession session,
  FakeFixSource source,
) async {
  source.add(fixAt(1000));
  await frames(tester, 5);
  await tester.tap(find.byType(fm.FlutterMap));
  await tester.pump(const Duration(milliseconds: 200));
  await frames(tester, 12);
  return tester
      .widget<fm.MarkerLayer>(find.byType(fm.MarkerLayer))
      .markers
      .single;
}

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  group('flutter_map', () {
    testWidgets('the view follows the vehicle heading-up and draws the route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMapNavigationView(
            session: session,
            initialCenter: sampleRoute.points.first,
            userAgentPackageName: 'dev.navigationengine.test',
            tileUrlTemplate: '',
          ),
        ),
      );
      expect(session.map, isA<FlutterMapNavigationMap>());
      final adapter = session.map! as FlutterMapNavigationMap;
      expect(adapter.route.value, isNotNull, reason: 'drawn on attach');

      source.add(
        NavFix(
          position: sampleRoute.pointAt(1000),
          accuracy: 5,
          speed: 10,
          heading: sampleRoute.bearingAt(1000),
          time: DateTime.now(),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final camera = adapter.controller.camera;
      final frame = session.frame!;
      expect(camera.rotation, closeTo(-frame.bearing, 1e-6));
      // The vehicle sits at the focus point, below the centre.
      final atVehicle = camera.latLngToScreenOffset(toLatLng(frame.position));
      expect(atVehicle.dy, closeTo(800 * 0.7, 2));
      expect(atVehicle.dx, closeTo(200, 2));
      expect(find.byType(fm.PolylineLayer), findsOneWidget);
      final layer = tester.widget<fm.PolylineLayer>(
        find.byType(fm.PolylineLayer),
      );
      expect(layer.polylines, hasLength(2), reason: 'driven and ahead');

      await tester.pumpWidget(const SizedBox());
      expect(session.map, isNull, reason: 'detached on dispose');
    });

    testWidgets('the session keeps running after the view is removed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session));
      await tester.pumpWidget(const SizedBox());
      expect(session.map, isNull);

      source.add(fixAt(1500));
      session.tick(1 / 60);
      expect(session.frame, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new session without a route clears the line and marker', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session1 = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session1.dispose);
      await tester.pumpWidget(app(session1));
      final adapter = session1.map! as FlutterMapNavigationMap;
      source.add(fixAt(1000));
      await tester.tap(find.byType(fm.FlutterMap));
      await frames(tester, 20);
      expect(adapter.route.value, isNotNull);
      expect(adapter.vehicle.value, isNotNull, reason: 'marker while panned');

      final session2 = NavigationSession(fixes: FakeFixSource())..start();
      addTearDown(session2.dispose);
      await tester.pumpWidget(app(session2));
      expect(session1.map, isNull);
      expect(session2.map, same(adapter));
      expect(adapter.route.value, isNull);
      expect(adapter.vehicle.value, isNull);
    });

    testWidgets('panning stops following and shows the vehicle marker', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session));
      final adapter = session.map! as FlutterMapNavigationMap;
      source.add(fixAt(1000));
      await frames(tester, 5);
      expect(session.follow, isTrue);
      expect(adapter.vehicle.value, isNull, reason: 'the fixed puck is used');

      await tester.tap(find.byType(fm.FlutterMap));
      expect(session.follow, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      await frames(tester, 12);
      expect(adapter.vehicle.value, isNotNull);
      final markers = tester.widget<fm.MarkerLayer>(
        find.byType(fm.MarkerLayer),
      );
      expect(markers.markers, hasLength(1));
    });

    testWidgets('the marker size follows a CarPuck puck', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const CarPuck(size: 60)));
      final marker = await pannedMarker(tester, session, source);
      expect(marker.width, 60);
      expect(marker.height, 60);
    });

    testWidgets('markerSize sizes the marker of a custom puck', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        app(session, puck: const Icon(Icons.navigation), markerSize: 30),
      );
      final marker = await pannedMarker(tester, session, source);
      expect(marker.width, 30);
      expect(marker.height, 30);
    });

    testWidgets('the default marker size is 44', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeFixSource();
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const Icon(Icons.navigation)));
      final marker = await pannedMarker(tester, session, source);
      expect(marker.width, 44);
    });

    testWidgets('onMapReady hands the app the map controller', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = NavigationSession(fixes: FakeFixSource())
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      fm.MapController? got;
      await tester.pumpWidget(app(session, onMapReady: (c) => got = c));
      await frames(tester, 3);
      final adapter = session.map! as FlutterMapNavigationMap;
      expect(got, isNotNull);
      expect(got, same(adapter.controller));
    });
  });
}
