// An app that imports only navigation_engine_maplibre can build the drop-in
// with every option: the library re-exports the names of its signature.
// Each name below would fail to compile without that re-export.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';

import 'support/recording_platform.dart';

void main() {
  testWidgets('MapLibreStyleNavigation needs only this library', (
    tester,
  ) async {
    installRecordingPlatform(RecordingPlatform());
    final NavigationSession session = NavigationSession(
      fixes: SimulatedFixSource(GpsSimulator(sampleRoute)),
    );
    final NavigationFlowController flow = NavigationFlowController(
      session: session,
    );
    final GeoPoint center = sampleRoute.points.first;
    VehicleImageBuilder vehicleImage() =>
        (ratio) async => Uint8List(4);

    await tester.pumpWidget(
      MaterialApp(
        home: MapLibreStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: center,
          styleString: 'https://example.com/style.json',
          strings: const NavigationStrings.vietnamese(),
          dayColors: MapboxStyleColors.day,
          nightColors: MapboxStyleColors.night,
          speedLimitSign: SpeedLimitSign.rectangular,
          dayRouteColors: const RouteColors(),
          nightRouteColors: const RouteColors(),
          puck: const CarPuck(size: 40),
          vehicleImage: vehicleImage(),
          idleBuilder: (_) => const Text('IDLE'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IDLE'), findsOneWidget);
    expect(session.map, isA<MapLibreNavigationMap>());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  });

  test('the map interfaces and their types need only this library', () {
    // Each type annotation and name fails to compile without its re-export.
    final map = MapLibreNavigationMap();
    final SearchPinsMap pins = map;
    final DestinationPinMap destination = map;
    final AlternateRoutesMap alternates = map;
    const AlongRoutePlace place = AlongRoutePlace(
      id: 'a',
      name: 'Fuel',
      position: GeoPoint(10.78, 106.7),
    );
    final AlternateRoute alternate = AlternateRoute(
      route: sampleRoute,
      timeDelta: Duration.zero,
      divergence: 0,
    );
    final Future<Uint8List> Function({
      required bool focused,
      required double pixelRatio,
      required Color color,
    })
    searchPin = paintSearchPin;
    final Future<Uint8List> Function({required double pixelRatio, Color color})
    destinationPin = paintDestinationPin;
    // The type of the view's labelColors, fasterLabelColors and
    // slowerLabelColors.
    const RouteLabelColors labelColors = RouteLabelColors();
    expect([
      pins,
      destination,
      alternates,
      place,
      alternate,
      searchPin,
      labelColors,
    ], hasLength(7));
    expect(destinationPin, isNotNull);
    map.dispose();
  });
}
