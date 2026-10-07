import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

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

void main() {
  late FakeFixSource source;
  late NavigationSession session;

  /// Created inside each test body: the session's streams must live in the
  /// test's fake-async zone for `pump` to deliver their events.
  void newSession() {
    source = FakeFixSource();
    session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
  }

  NavFix fixAt(double s) => NavFix(
    position: sampleRoute.pointAt(s),
    accuracy: 5,
    speed: 10,
    heading: sampleRoute.bearingAt(s),
    time: DateTime.now(),
  );

  /// Lets the session's async stream events reach the banner and rebuild:
  /// the first pump delivers them, the second renders the new state.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Delivers a fix at [s] and ticks once.
  Future<void> driveTo(WidgetTester tester, double s) async {
    source.add(fixAt(s));
    session.tick(1 / 60);
    await settle(tester);
  }

  /// The first spoken manoeuvre at least 300 m from the start.
  RouteStep spokenStep() => sampleRoute.steps.firstWhere(
    (s) => s.distance > 300 && !isSilentStep(s) && !s.isArrival,
  );

  Widget banner({bool showLast = false}) => MaterialApp(
    home: Scaffold(
      body: NavigationBanner(session: session, showLastAnnouncement: showLast),
    ),
  );

  testWidgets('hidden until there is guidance', (tester) async {
    newSession();
    await tester.pumpWidget(banner());
    expect(find.byType(Material), findsOneWidget); // only the Scaffold's
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('shows distance, instruction and icon of the next step', (
    tester,
  ) async {
    newSession();
    await tester.pumpWidget(banner());
    final step = spokenStep();
    await driveTo(tester, step.distance - 150);
    final state = session.guidanceState!;
    expect(state.step, same(step));
    const f = EnglishGuidanceFormatter();
    expect(find.text(f.instruction(step)), findsOneWidget);
    expect(find.text(f.distance(state.distanceToStep)), findsOneWidget);
    expect(find.byIcon(maneuverIcon(step)), findsOneWidget);
  });

  testWidgets('hides again when the route is removed', (tester) async {
    newSession();
    await tester.pumpWidget(banner());
    await driveTo(tester, 500);
    expect(find.byType(Icon), findsWidgets);
    session.setRoute(null);
    await settle(tester);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('shows the last prompt when asked to', (tester) async {
    newSession();
    await tester.pumpWidget(banner(showLast: true));
    final step = spokenStep();
    await driveTo(tester, step.distance - 150);
    const f = EnglishGuidanceFormatter();
    expect(find.textContaining('In '), findsOneWidget);
    expect(find.textContaining(f.instruction(step).substring(1)), findsWidgets);
  });

  testWidgets('does not show the last prompt by default', (tester) async {
    newSession();
    await tester.pumpWidget(banner());
    final step = spokenStep();
    await driveTo(tester, step.distance - 150);
    expect(find.textContaining('In '), findsNothing);
  });

  testWidgets('arrival', (tester) async {
    newSession();
    await tester.pumpWidget(banner());
    await driveTo(tester, sampleRoute.length);
    expect(find.text('You have arrived at your destination'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  test('maneuverIcon covers every type and modifier', () {
    for (final t in ManeuverType.values) {
      for (final m in ManeuverModifier.values) {
        expect(
          maneuverIcon(RouteStep(distance: 0, type: t, modifier: m)),
          isA<IconData>(),
        );
      }
    }
    expect(maneuverIcon(null), Icons.navigation);
    IconData icon(
      ManeuverType t, [
      ManeuverModifier m = ManeuverModifier.none,
    ]) => maneuverIcon(RouteStep(distance: 0, type: t, modifier: m));
    expect(icon(ManeuverType.arrive), Icons.flag);
    expect(
      icon(ManeuverType.roundabout, ManeuverModifier.left),
      Icons.roundabout_left,
    );
    expect(
      icon(ManeuverType.exitRoundabout, ManeuverModifier.right),
      Icons.roundabout_right,
    );
    expect(
      icon(ManeuverType.fork, ManeuverModifier.slightLeft),
      Icons.fork_left,
    );
    expect(icon(ManeuverType.merge), Icons.merge);
    expect(icon(ManeuverType.onRamp, ManeuverModifier.right), Icons.ramp_right);
    expect(icon(ManeuverType.turn, ManeuverModifier.uturn), Icons.u_turn_left);
    expect(icon(ManeuverType.turn, ManeuverModifier.straight), Icons.straight);
    expect(
      icon(ManeuverType.turn, ManeuverModifier.sharpRight),
      Icons.turn_sharp_right,
    );
    expect(icon(ManeuverType.turn, ManeuverModifier.left), Icons.turn_left);
  });
}
