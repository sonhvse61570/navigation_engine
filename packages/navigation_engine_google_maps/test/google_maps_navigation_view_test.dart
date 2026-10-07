// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

/// A platform implementation without platform channels: builds a plain
/// widget, creates the map view only when the test says so, and records the
/// camera moves and the map objects of the last build.
class FakeGoogleMapsPlatform extends gmp.GoogleMapsFlutterPlatform {
  final cameraMoves = <gmp.CameraUpdate>[];
  gmp.MapObjects? lastObjects;
  void Function(int)? _onCreated;
  int? _mapId;

  /// What the native view does once it exists.
  void createView() => _onCreated!(_mapId!);

  Set<gmp.Marker> get markers => lastObjects!.markers;

  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    void Function(int) onPlatformViewCreated, {
    required gmp.MapWidgetConfiguration widgetConfiguration,
    gmp.MapConfiguration mapConfiguration = const gmp.MapConfiguration(),
    gmp.MapObjects mapObjects = const gmp.MapObjects(),
  }) {
    _mapId = creationId;
    _onCreated = onPlatformViewCreated;
    lastObjects = mapObjects;
    return const SizedBox.expand();
  }

  @override
  Future<void> updateMapConfiguration(
    gmp.MapConfiguration configuration, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateMarkers(
    gmp.MarkerUpdates markerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolylines(
    gmp.PolylineUpdates polylineUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolygons(
    gmp.PolygonUpdates polygonUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateCircles(
    gmp.CircleUpdates circleUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateHeatmaps(
    gmp.HeatmapUpdates heatmapUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateTileOverlays({
    required Set<gmp.TileOverlay> newTileOverlays,
    required int mapId,
  }) async {}

  @override
  Future<void> updateClusterManagers(
    gmp.ClusterManagerUpdates clusterManagerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateGroundOverlays(
    gmp.GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> moveCamera(
    gmp.CameraUpdate cameraUpdate, {
    required int mapId,
  }) async => cameraMoves.add(cameraUpdate);

  @override
  void dispose({required int mapId}) {}

  // The map events: none happen in these tests.
  @override
  Stream<gmp.CameraMoveStartedEvent> onCameraMoveStarted({
    required int mapId,
  }) => const Stream.empty();

  @override
  Stream<gmp.CameraMoveEvent> onCameraMove({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.CameraIdleEvent> onCameraIdle({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.MarkerTapEvent> onMarkerTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.MarkerDragEvent> onMarkerDrag({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.PolylineTapEvent> onPolylineTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.PolygonTapEvent> onPolygonTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.CircleTapEvent> onCircleTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.PointOfInterestTapEvent> onPointOfInterestTap({
    required int mapId,
  }) => const Stream.empty();

  @override
  Stream<gmp.MapTapEvent> onTap({required int mapId}) => const Stream.empty();

  @override
  Stream<gmp.MapLongPressEvent> onLongPress({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.ClusterTapEvent> onClusterTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      const Stream.empty();
}

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
  Set<gm.Marker> markers = const {},
  Widget puck = const CarPuck(),
  VehicleImageBuilder? vehicleImage,
  RouteColors routeColors = const RouteColors(),
}) => MaterialApp(
  home: GoogleMapsNavigationView(
    session: session,
    initialCenter: sampleRoute.points.first,
    markers: markers,
    puck: puck,
    vehicleImage: vehicleImage,
    routeColors: routeColors,
  ),
);

/// The width of a PNG, from its IHDR chunk.
int pngWidth(Uint8List png) => ByteData.sublistView(png).getUint32(16);

/// Lets the real (non fake-async) PNG rendering finish.
Future<void> renderDone(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pump();
}

/// Shows the vehicle marker and returns its icon.
Future<gm.BitmapDescriptor> vehicleIcon(
  WidgetTester tester,
  NavigationSession session,
  FakeFixSource source,
  FakeGoogleMapsPlatform platform,
) async {
  source.add(fixAt(300));
  session.follow = false;
  await tester.pump(const Duration(milliseconds: 200));
  await frames(tester, 3);
  return platform.markers
      .singleWhere((m) => m.markerId.value == 'navigation_engine_vehicle')
      .icon;
}

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late FakeGoogleMapsPlatform platform;
  late FakeFixSource source;

  setUp(() {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    source = FakeFixSource();
  });

  testWidgets('the view attaches to the session and leaves it running when '
      'removed', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);

    await tester.pumpWidget(app(session));
    expect(session.map, isA<GoogleMapsNavigationMap>());
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.polylines.value, hasLength(2), reason: 'route drawn on attach');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(session.map, isNull);
    expect(session.isRunning, isTrue);

    final before = session.frame;
    source.add(fixAt(500));
    await frames(tester, 3);
    session.tick(0.016);
    expect(session.frame, isNotNull);
    expect(session.frame, isNot(same(before)));
  });

  testWidgets('a new session without a route clears the map', (tester) async {
    final first = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(first.dispose);
    await tester.pumpWidget(app(first));
    final map = first.map! as GoogleMapsNavigationMap;
    source.add(fixAt(300));
    first.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    expect(map.polylines.value, isNotEmpty);
    expect(map.vehicleMarker.value, isNotNull);

    final second = NavigationSession(fixes: FakeFixSource());
    addTearDown(second.dispose);
    await tester.pumpWidget(app(second));

    expect(first.map, isNull);
    expect(second.map, same(map));
    expect(map.polylines.value, isEmpty);
    expect(map.vehicleMarker.value, isNull);
  });

  testWidgets('the app markers and the vehicle marker are both drawn', (
    tester,
  ) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    const mine = gm.Marker(markerId: gm.MarkerId('mine'));
    await tester.pumpWidget(app(session, markers: {mine}));
    expect(platform.markers.map((m) => m.markerId.value), ['mine']);

    source.add(fixAt(300));
    session.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    expect(
      platform.markers.map((m) => m.markerId.value),
      containsAll(['mine', 'navigation_engine_vehicle']),
    );
  });

  testWidgets('camera updates start once the map exists', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;

    source.add(fixAt(200));
    await frames(tester, 5);
    expect(map.hasController, isFalse);
    expect(platform.cameraMoves, isEmpty);

    platform.createView();
    await tester.pump();
    expect(map.hasController, isTrue);

    source.add(fixAt(220));
    await frames(tester, 5);
    expect(platform.cameraMoves, isNotEmpty);
  });

  group('vehicle icon', () {
    testWidgets('a CarPuck is rendered at its size x the device ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const CarPuck(size: 30)));
      await renderDone(tester);

      final icon = await vehicleIcon(tester, session, source, platform);
      expect(icon, isA<gm.BytesMapBitmap>());
      final bytes = icon as gm.BytesMapBitmap;
      expect(bytes.imagePixelRatio, 2);
      expect(pngWidth(bytes.byteData), 60);
    });

    testWidgets('a ratio change re-renders the icon, a shown marker too', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const CarPuck(size: 30)));
      await renderDone(tester);
      await vehicleIcon(tester, session, source, platform);

      tester.view.devicePixelRatio = 3;
      await tester.pump();
      await renderDone(tester);
      await frames(tester, 2);

      final icon =
          platform.markers
                  .singleWhere(
                    (m) => m.markerId.value == 'navigation_engine_vehicle',
                  )
                  .icon
              as gm.BytesMapBitmap;
      expect(icon.imagePixelRatio, 3);
      expect(pngWidth(icon.byteData), 90);
    });

    testWidgets('a custom image builder gets the device ratio', (tester) async {
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final ratios = <double>[];
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        app(
          session,
          vehicleImage: (ratio) async {
            ratios.add(ratio);
            return Uint8List.fromList([1, 2, 3]);
          },
        ),
      );
      await tester.pump();
      expect(ratios, [2.5]);
    });

    testWidgets('a failing image builder keeps the default marker', (
      tester,
    ) async {
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        app(session, vehicleImage: (_) async => throw StateError('no image')),
      );
      await renderDone(tester);
      final icon = await vehicleIcon(tester, session, source, platform);
      expect(icon, gm.BitmapDescriptor.defaultMarker);
    });
  });

  testWidgets('routeColors changes restyle the drawn route', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    source.add(fixAt(300));
    session.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    Color colorOf(String id) =>
        map.polylines.value.singleWhere((p) => p.polylineId.value == id).color;
    expect(colorOf('navigation_engine_ahead'), const RouteColors().ahead);

    const red = Color(0xFFFF0000);
    await tester.pumpWidget(
      app(session, routeColors: const RouteColors(ahead: red)),
    );
    await tester.pump();

    expect(colorOf('navigation_engine_ahead'), red);
    expect(platform.lastObjects!.polylines.map((p) => p.color), contains(red));
  });
}
