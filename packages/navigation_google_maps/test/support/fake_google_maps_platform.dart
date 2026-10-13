import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;

/// A platform implementation without platform channels: builds a plain
/// widget, creates the map view only when the test says so, and records the
/// camera moves and the map objects of the last build.
class FakeGoogleMapsPlatform extends gmp.GoogleMapsFlutterPlatform {
  final cameraMoves = <gmp.CameraUpdate>[];

  /// The updates passed to `animateCamera`, in order.
  final cameraAnimations = <gmp.CameraUpdate>[];
  gmp.MapObjects? lastObjects;

  /// When set, `animateCamera` and `moveCamera` fail with it.
  Object? cameraError;

  /// The map configuration of the last build, with every later update
  /// applied (the platform gets updates as diffs).
  gmp.MapConfiguration mapConfiguration = const gmp.MapConfiguration();

  /// How many times `buildViewWithConfiguration` was called: every build of
  /// a `GoogleMap` widget calls it, so this counts rebuilds, not remounts.
  int buildCount = 0;

  /// The creation ids seen by `buildViewWithConfiguration`; a map view that
  /// was created anew adds an id.
  final creationIds = <int>{};
  void Function(int)? _onCreated;
  int? _mapId;

  /// What the native view does once it exists.
  void createView() => _onCreated!(_mapId!);

  // The gestures a test sends, delivered at once to the map's listeners
  // (the `GoogleMap` listens once the view is created and its controller
  // initialised: pump after [createView]).
  final _taps = StreamController<gmp.MapTapEvent>.broadcast(sync: true);
  final _longPresses = StreamController<gmp.MapLongPressEvent>.broadcast(
    sync: true,
  );
  final _markerTaps = StreamController<gmp.MarkerTapEvent>.broadcast(
    sync: true,
  );
  final _polylineTaps = StreamController<gmp.PolylineTapEvent>.broadcast(
    sync: true,
  );

  /// A tap on the map itself at [position], as the SDK reports one that
  /// no map object took.
  void tapMap(gmp.LatLng position) =>
      _taps.add(gmp.MapTapEvent(_mapId!, position));

  /// A long press on the map at [position].
  void longPressMap(gmp.LatLng position) =>
      _longPresses.add(gmp.MapLongPressEvent(_mapId!, position));

  /// A tap on the marker [id] of the last build.
  void tapMarker(String id) =>
      _markerTaps.add(gmp.MarkerTapEvent(_mapId!, gmp.MarkerId(id)));

  /// A tap on the polyline [id] of the last build.
  void tapPolyline(String id) =>
      _polylineTaps.add(gmp.PolylineTapEvent(_mapId!, gmp.PolylineId(id)));

  Set<gmp.Marker> get markers => lastObjects!.markers;

  /// The polylines of the last build.
  Set<gmp.Polyline> get polylines => lastObjects!.polylines;

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
    this.mapConfiguration = mapConfiguration;
    buildCount++;
    creationIds.add(creationId);
    // Opaque to pointers, like a native view.
    return const ColoredBox(color: Color(0x00000000));
  }

  @override
  Future<void> updateMapConfiguration(
    gmp.MapConfiguration configuration, {
    required int mapId,
  }) async => mapConfiguration = mapConfiguration.applyDiff(configuration);

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
  Future<void> animateCamera(
    gmp.CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    if (cameraError != null) throw cameraError!;
    cameraAnimations.add(cameraUpdate);
  }

  @override
  Future<void> moveCamera(
    gmp.CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    if (cameraError != null) throw cameraError!;
    cameraMoves.add(cameraUpdate);
  }

  @override
  void dispose({required int mapId}) {}

  // The other map events: none happen in these tests.
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
      _markerTaps.stream.where((e) => e.mapId == mapId);

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
      _polylineTaps.stream.where((e) => e.mapId == mapId);

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
  Stream<gmp.MapTapEvent> onTap({required int mapId}) =>
      _taps.stream.where((e) => e.mapId == mapId);

  @override
  Stream<gmp.MapLongPressEvent> onLongPress({required int mapId}) =>
      _longPresses.stream.where((e) => e.mapId == mapId);

  @override
  Stream<gmp.ClusterTapEvent> onClusterTap({required int mapId}) =>
      const Stream.empty();

  @override
  Stream<gmp.GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      const Stream.empty();
}

/// Makes `GoogleMap` use [platform] until the end of the test.
void installFakeGoogleMapsPlatform(FakeGoogleMapsPlatform platform) {
  final previous = gmp.GoogleMapsFlutterPlatform.instance;
  gmp.GoogleMapsFlutterPlatform.instance = platform;
  addTearDown(() => gmp.GoogleMapsFlutterPlatform.instance = previous);
}
