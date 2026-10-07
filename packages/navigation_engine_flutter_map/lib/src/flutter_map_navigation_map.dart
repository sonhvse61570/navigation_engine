import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// The route line as flutter_map points.
typedef FlutterMapRouteLine = ({List<LatLng> driven, List<LatLng> ahead});

/// The vehicle marker as flutter_map values.
typedef FlutterMapVehicle = ({LatLng position, double bearing});

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// [NavigationMap] and [VehicleMarkerMap] on top of flutter_map.
///
/// flutter_map applies camera moves synchronously and has no tilt, so
/// [CameraTarget.tilt] is ignored. Its rotation is counter-clockwise, hence
/// the minus sign that puts the vehicle's heading up. The route line and the
/// vehicle marker are exposed as listenables for the map's layers.
class FlutterMapNavigationMap implements NavigationMap, VehicleMarkerMap {
  FlutterMapNavigationMap({MapController? controller})
    : controller = controller ?? MapController();

  final MapController controller;
  final route = ValueNotifier<FlutterMapRouteLine?>(null);
  final vehicle = ValueNotifier<FlutterMapVehicle?>(null);

  /// How far below the map centre the followed point sits, in logical
  /// pixels (set by the view from its focus padding).
  double focusOffset = 0;

  bool _ready = false;

  /// Call from `MapOptions.onMapReady`; camera updates before are dropped.
  void onMapReady() => _ready = true;

  @override
  Future<void> moveCamera(CameraTarget target) async {
    if (!_ready) return;
    controller.rotate(-target.bearing);
    controller.move(
      toLatLng(target.position),
      target.zoom,
      // The offset is in screen space, whatever the rotation.
      offset: Offset(0, focusOffset),
    );
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {
    route.value = (
      driven: driven.map(toLatLng).toList(),
      ahead: ahead.map(toLatLng).toList(),
    );
  }

  @override
  void clearRoute() => route.value = null;

  @override
  void showVehicle(GeoPoint position, double bearing) =>
      vehicle.value = (position: toLatLng(position), bearing: bearing);

  @override
  void hideVehicle() => vehicle.value = null;

  void dispose() {
    route.dispose();
    vehicle.dispose();
    controller.dispose();
  }
}
