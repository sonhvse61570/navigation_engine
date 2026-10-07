// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart'
    as gma;
import 'package:navigation_engine_google_maps/src/google_maps_navigation_map.dart'
    as src;

const _target = CameraTarget(
  position: GeoPoint(10.77, 106.69),
  bearing: 42,
  zoom: 17.5,
  tilt: 50,
);

void main() {
  group('google_maps', () {
    test('camera position', () {
      final p = src.toCameraPosition(_target);
      expect(p.target, const gm.LatLng(10.77, 106.69));
      expect((p.bearing, p.zoom, p.tilt), (42, 17.5, 50));
    });

    test('route polylines: two lines, skips parts under two points', () {
      const colors = RouteColors();
      final lines = src.routePolylines(
        const [GeoPoint(10, 106), GeoPoint(10.001, 106)],
        const [GeoPoint(10.001, 106)],
        colors,
      );
      expect(lines, hasLength(1));
      expect(lines.single.color, colors.driven);
      expect(lines.single.width, 7);
    });

    test('vehicle marker and camera before the map exists', () async {
      final map = gma.GoogleMapsNavigationMap();
      expect(map.hasController, isFalse);
      await map.moveCamera(_target); // dropped, no controller yet: no throw
      map.showVehicle(const GeoPoint(10, 106), 90);
      final m = map.vehicleMarker.value!;
      expect(m.position, const gm.LatLng(10, 106));
      expect((m.rotation, m.flat), (90, true));
      map.hideVehicle();
      expect(map.vehicleMarker.value, isNull);
      map.showRoute(
        const [GeoPoint(10, 106), GeoPoint(10.001, 106)],
        const [GeoPoint(10.001, 106), GeoPoint(10.002, 106)],
      );
      expect(map.polylines.value, hasLength(2));
      map.clearRoute();
      expect(map.polylines.value, isEmpty);
      map.dispose();
    });
  });
}
