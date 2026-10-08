// An app that imports only navigation_engine_flutter_map can build the
// drop-in with every option: the library re-exports the names of its
// signature. Each name below would fail to compile without that re-export.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter_map/navigation_engine_flutter_map.dart';

void main() {
  testWidgets('NeutralNavigation needs only this library', (tester) async {
    final NavigationSession session = NavigationSession(
      fixes: SimulatedFixSource(GpsSimulator(sampleRoute)),
    );
    final NavigationFlowController flow = NavigationFlowController(
      session: session,
    );
    final GeoPoint center = sampleRoute.points.first;

    await tester.pumpWidget(
      MaterialApp(
        home: NeutralNavigation(
          session: session,
          flow: flow,
          initialCenter: center,
          userAgentPackageName: 'com.example.app',
          strings: const NavigationStrings.vietnamese(),
          dayColors: MapboxStyleColors.day,
          nightColors: MapboxStyleColors.night,
          speedLimitSign: SpeedLimitSign.rectangular,
          dayRouteColors: const RouteColors(),
          nightRouteColors: const RouteColors(),
          puck: const CarPuck(size: 40),
          idleBuilder: (_) => const Text('IDLE'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IDLE'), findsOneWidget);
    expect(session.map, isA<FlutterMapNavigationMap>());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  });
}
