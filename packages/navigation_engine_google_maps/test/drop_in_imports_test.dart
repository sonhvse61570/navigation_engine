// An app that imports only navigation_engine_google_maps can build the
// drop-in with every option: the library re-exports the names of its
// signature. Each name below would fail to compile without that re-export.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/fake_google_maps_platform.dart';

void main() {
  testWidgets('GoogleStyleNavigation needs only this library', (tester) async {
    installFakeGoogleMapsPlatform(FakeGoogleMapsPlatform());
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
        home: GoogleStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: center,
          strings: const NavigationStrings.vietnamese(),
          dayColors: GoogleStyleColors.day,
          nightColors: GoogleStyleColors.night,
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
    expect(session.map, isA<GoogleMapsNavigationMap>());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  });
}
