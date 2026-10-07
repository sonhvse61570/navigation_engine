import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// The camera position a [CameraTarget] stands for.
CameraPosition toCameraPosition(CameraTarget t) => CameraPosition(
  target: toLatLng(t.position),
  zoom: t.zoom,
  bearing: t.bearing,
  tilt: t.tilt,
);

/// The two route polylines (driven, ahead) for [driven] / [ahead].
Set<Polyline> routePolylines(
  List<GeoPoint> driven,
  List<GeoPoint> ahead,
  RouteColors colors,
) => {
  if (driven.length >= 2)
    Polyline(
      polylineId: const PolylineId('navigation_engine_driven'),
      points: driven.map(toLatLng).toList(),
      color: colors.driven,
      width: colors.drivenWidth.round(),
      zIndex: 1,
    ),
  if (ahead.length >= 2)
    Polyline(
      polylineId: const PolylineId('navigation_engine_ahead'),
      points: ahead.map(toLatLng).toList(),
      color: colors.ahead,
      width: colors.aheadWidth.round(),
      zIndex: 2,
    ),
};

/// [NavigationMap] and [VehicleMarkerMap] on top of google_maps_flutter.
///
/// Wire [onMapCreated] to `GoogleMap.onMapCreated`; camera updates before
/// are dropped. Polylines and markers are widget properties in
/// google_maps_flutter, so the route line and the vehicle marker are
/// exposed as listenables for the view (or an app's own `GoogleMap`) to
/// build from.
class GoogleMapsNavigationMap implements NavigationMap, VehicleMarkerMap {
  GoogleMapsNavigationMap({RouteColors routeColors = const RouteColors()})
    // A named parameter cannot be a private initializing formal.
    // ignore: prefer_initializing_formals
    : _routeColors = routeColors;

  RouteColors _routeColors;
  List<GeoPoint> _driven = const [];
  List<GeoPoint> _ahead = const [];

  RouteColors get routeColors => _routeColors;

  /// Rebuilds the drawn route polylines with the new colours and widths.
  set routeColors(RouteColors value) {
    final old = _routeColors;
    if (value.driven == old.driven &&
        value.ahead == old.ahead &&
        value.drivenWidth == old.drivenWidth &&
        value.aheadWidth == old.aheadWidth) {
      return;
    }
    _routeColors = value;
    if (polylines.value.isNotEmpty) {
      polylines.value = routePolylines(_driven, _ahead, value);
    }
  }

  final polylines = ValueNotifier<Set<Polyline>>(const {});
  final vehicleMarker = ValueNotifier<Marker?>(null);

  BitmapDescriptor _vehicleIcon = BitmapDescriptor.defaultMarker;

  /// The vehicle icon for [vehicleMarker]; set it with
  /// `BitmapDescriptor.bytes(png, imagePixelRatio: ratio)`. A marker already
  /// shown gets the new icon.
  BitmapDescriptor get vehicleIcon => _vehicleIcon;
  set vehicleIcon(BitmapDescriptor value) {
    _vehicleIcon = value;
    final shown = vehicleMarker.value;
    if (shown != null) vehicleMarker.value = shown.copyWith(iconParam: value);
  }

  GoogleMapController? _controller;

  void onMapCreated(GoogleMapController controller) => _controller = controller;

  @override
  Future<void> moveCamera(CameraTarget target) async {
    final c = _controller;
    if (c == null) return;
    await c.moveCamera(
      CameraUpdate.newCameraPosition(toCameraPosition(target)),
    );
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {
    _driven = driven;
    _ahead = ahead;
    polylines.value = routePolylines(driven, ahead, _routeColors);
  }

  @override
  void clearRoute() {
    _driven = _ahead = const [];
    polylines.value = const {};
  }

  @override
  void showVehicle(GeoPoint position, double bearing) {
    vehicleMarker.value = Marker(
      markerId: const MarkerId('navigation_engine_vehicle'),
      position: toLatLng(position),
      rotation: bearing,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon: vehicleIcon,
      zIndexInt: 10,
    );
  }

  @override
  void hideVehicle() => vehicleMarker.value = null;

  void dispose() {
    polylines.dispose();
    vehicleMarker.dispose();
    _controller = null;
  }

  @visibleForTesting
  bool get hasController => _controller != null;
}

/// PNG bytes → marker icon at the given pixel ratio.
BitmapDescriptor vehicleIconFrom(Uint8List png, {double pixelRatio = 3}) =>
    BitmapDescriptor.bytes(png, imagePixelRatio: pixelRatio);
