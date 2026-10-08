// An app that imports only navigation_engine_mapbox can build the drop-in
// with every option: the library re-exports the names of its signature.
// Each name below would fail to compile without that re-export.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';

import 'support/fake_mapbox_view.dart';

void main() {
  testWidgets('MapboxStyleNavigation needs only this library', (tester) async {
    final NavigationSession session = NavigationSession(
      fixes: SimulatedFixSource(GpsSimulator(sampleRoute)),
    );
    final NavigationFlowController flow = NavigationFlowController(
      session: session,
    );
    final GeoPoint center = sampleRoute.points.first;
    VehicleImageBuilder vehicleImage() =>
        (ratio) async => Uint8List(4);
    final views = FakeMapboxViews();

    await tester.pumpWidget(
      MaterialApp(
        home: MapboxStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: center,
          strings: const NavigationStrings.vietnamese(),
          dayColors: MapboxStyleColors.day,
          nightColors: MapboxStyleColors.night,
          speedLimitSign: SpeedLimitSign.rectangular,
          dayRouteColors: const RouteColors(),
          nightRouteColors: const RouteColors(),
          puck: const CarPuck(size: 40),
          vehicleImage: vehicleImage(),
          idleBuilder: (_) => const Text('IDLE'),
          mapViewBuilder: views.build,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IDLE'), findsOneWidget);
    expect(views.view.session, same(session));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  });
}
