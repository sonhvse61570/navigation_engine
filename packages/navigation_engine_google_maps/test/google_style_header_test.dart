import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

GuidanceState _state(
  RouteStep? step, {
  double distance = 180,
  RouteStep? then,
}) => GuidanceState(
  step: step,
  stepIndex: step == null ? -1 : 3,
  distanceToStep: distance,
  thenStep: then,
  remaining: 2000,
  arrived: false,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topCenter, child: child),
  ),
);

void main() {
  const formatter = EnglishGuidanceFormatter();
  final lyTuTrong = sampleRoute.steps[3];

  testWidgets('shows icon, distance and road name', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(lyTuTrong))),
    );
    expect(find.text(formatter.distance(180)), findsOneWidget);
    expect(find.text('Ly Tu Trong'), findsOneWidget);
    expect(find.byIcon(Icons.turn_right), findsWidgets);
  });

  testWidgets('unnamed road shows the instruction', (tester) async {
    final unnamed = sampleRoute.steps.firstWhere((s) => s.roadName == '');
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(unnamed))),
    );
    expect(find.text(formatter.instruction(unnamed)), findsOneWidget);
  });

  testWidgets('a null step shows the arrived text', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(null, distance: 0))),
    );
    expect(find.text('You have arrived'), findsOneWidget);
  });

  testWidgets('then strip only with a then step', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(lyTuTrong))),
    );
    expect(find.text('Then'), findsNothing);

    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong, then: sampleRoute.steps[4]),
        ),
      ),
    );
    expect(find.text('Then'), findsOneWidget);
  });

  testWidgets('lanes shown when the step has lanes', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(lyTuTrong))),
    );
    expect(find.byType(GoogleStyleLaneGuidance), findsOneWidget);
    expect(
      find.byKey(const ValueKey('google_style_lane_cell')),
      findsNWidgets(3),
    );

    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(sampleRoute.steps[2]))),
    );
    expect(find.byType(GoogleStyleLaneGuidance), findsNothing);
  });

  testWidgets('Vietnamese formatter and strings', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong, then: sampleRoute.steps[4]),
          formatter: const VietnameseGuidanceFormatter(),
          strings: const GoogleStyleStrings.vietnamese(),
        ),
      ),
    );
    expect(find.text('Sau đó'), findsOneWidget);
    expect(
      find.text(const VietnameseGuidanceFormatter().distance(180)),
      findsOneWidget,
    );
  });

  testWidgets('no overflow at 320 dp with a 120-character road name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longName = List.filled(120, 'x').join();
    final route = NavRoute.fromPoints(
      const [
        GeoPoint(10.0, 106.0),
        GeoPoint(10.001, 106.0),
        GeoPoint(10.002, 106.0),
        GeoPoint(10.003, 106.0),
      ],
      steps: [
        RouteStepSeed.atVertex(
          1,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.right,
          roadName: longName,
          lanes: lyTuTrong.lanes,
        ),
        const RouteStepSeed.atVertex(
          2,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.left,
          roadName: 'Next',
        ),
      ],
    );
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(route.steps[0], then: route.steps[1]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(longName), findsOneWidget);
  });

  testWidgets('lane cells: valid opaque active arrow, invalid dimmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const GoogleStyleLaneGuidance(
          lanes: [
            Lane(directions: {LaneDirection.left}),
            Lane(
              directions: {LaneDirection.straight, LaneDirection.right},
              valid: true,
              active: LaneDirection.right,
            ),
          ],
        ),
      ),
    );
    final right = tester.widget<Icon>(find.byIcon(Icons.turn_right));
    expect(right.color!.a, 1.0);
    expect(find.byIcon(Icons.straight), findsNothing);
    final left = tester.widget<Icon>(find.byIcon(Icons.turn_left));
    expect(left.color!.a * 255, closeTo(102, 1));
  });

  test('laneDirectionIcon maps all 8 directions', () {
    expect(laneDirectionIcon(LaneDirection.straight), Icons.straight);
    expect(laneDirectionIcon(LaneDirection.slightLeft), Icons.turn_slight_left);
    expect(laneDirectionIcon(LaneDirection.left), Icons.turn_left);
    expect(laneDirectionIcon(LaneDirection.sharpLeft), Icons.turn_sharp_left);
    expect(laneDirectionIcon(LaneDirection.uturn), Icons.u_turn_left);
    expect(
      laneDirectionIcon(LaneDirection.slightRight),
      Icons.turn_slight_right,
    );
    expect(laneDirectionIcon(LaneDirection.right), Icons.turn_right);
    expect(laneDirectionIcon(LaneDirection.sharpRight), Icons.turn_sharp_right);
  });
}
