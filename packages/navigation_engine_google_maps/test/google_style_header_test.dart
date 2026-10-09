import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
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

Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: direction, child: app!),
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topCenter, child: child),
  ),
);

const _card = ValueKey('google_style_header_card');
const _band = ValueKey('google_style_header_band');
const _distance = ValueKey('google_style_header_distance');
const _spinner = ValueKey('google_style_header_spinner');
const _actions = ValueKey('google_style_header_actions');

Color _colorOf(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Material m => m.color!,
      final DecoratedBox b => (b.decoration as BoxDecoration).color!,
      _ => throw StateError('no colour on $key'),
    };

/// [step] without its road: what the secondary line reads.
RouteStep _bare(RouteStep step) => RouteStep(
  distance: step.distance,
  type: step.type,
  modifier: step.modifier,
);

void main() {
  const formatter = EnglishGuidanceFormatter();
  const strings = NavigationStrings();
  final lyTuTrong = sampleRoute.steps[3]; // a right turn with lanes
  final noLanes = sampleRoute.steps[2];
  final afterLanes = sampleRoute.steps[4];

  testWidgets('the icon, the split distance and the road; no manoeuvre '
      'line', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(lyTuTrong))),
    );
    // One text: "180" in 18 w600 and " m" in 13.
    expect(find.text(formatter.distance(180)), findsOneWidget);
    final distance = tester.widget<Text>(find.byKey(_distance));
    final spans = (distance.textSpan! as TextSpan).children!.cast<TextSpan>();
    // 180 m is said as the nearest 50 m.
    expect(spans.first.text, '200');
    expect(spans.first.style!.fontSize, 18);
    expect(spans.first.style!.fontWeight, FontWeight.w600);
    expect(spans.last.text, ' m');
    expect(spans.last.style!.fontSize, 13);
    final road = tester.widget<Text>(find.text('Ly Tu Trong'));
    final roadSpan = (road.textSpan! as TextSpan).children!.single;
    expect(roadSpan.style!.fontSize, 28);
    expect(roadSpan.style!.fontWeight, FontWeight.w500);
    expect(road.maxLines, 2);
    // The secondary instruction line is gone (Google look wave).
    expect(find.text(formatter.instruction(_bare(lyTuTrong))), findsNothing);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(_card),
        matching: find.byIcon(maneuverIcon(lyTuTrong)),
      ),
    );
    expect(icon.size, 48);
  });

  testWidgets('an unnamed road shows the instruction once', (tester) async {
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

  testWidgets('with lanes, the band is the lane row, as wide as the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(state: _state(lyTuTrong, then: afterLanes)),
      ),
    );
    expect(find.byType(GoogleStyleLaneGuidance), findsOneWidget);
    expect(
      find.byKey(const ValueKey('navigation_engine_lane_cell')),
      findsNWidgets(3),
    );
    expect(find.text('Then'), findsNothing, reason: 'the lanes take the band');
    final card = tester.getRect(find.byKey(_card));
    final band = tester.getRect(find.byKey(_band));
    expect(band.width, closeTo(card.width, 0.5));
    expect(band.top, closeTo(card.bottom, 0.5));
  });

  testWidgets('without lanes the band shows Then, hugging it at the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(GoogleStyleManeuverHeader(state: _state(noLanes))),
    );
    expect(find.byKey(_band), findsNothing, reason: 'no then step');
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(state: _state(noLanes, then: afterLanes)),
      ),
    );
    expect(find.text('Then'), findsOneWidget);
    final card = tester.getRect(find.byKey(_card));
    final band = tester.getRect(find.byKey(_band));
    expect(band.width, lessThan(card.width / 2));
    expect(band.left, closeTo(card.left, 0.5));
  });

  testWidgets('a straight-on step shows Then for a turn 1.2 km on, from '
      'NavGuidance', (tester) async {
    const a = GeoPoint(10.77, 106.69);
    final route = NavRoute.fromPoints(
      [
        a,
        offsetPoint(a, 90, 300),
        offsetPoint(a, 90, 1500),
        offsetPoint(a, 90, 2000),
      ],
      steps: const [
        RouteStepSeed.atVertex(0, type: ManeuverType.depart, roadName: 'A'),
        RouteStepSeed.atVertex(
          1,
          type: ManeuverType.continueOn,
          modifier: ManeuverModifier.straight,
          roadName: 'Dien Bien Phu',
        ),
        RouteStepSeed.atVertex(
          2,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.right,
          roadName: 'Nguyen Huu Canh',
        ),
        RouteStepSeed.atVertex(3, type: ManeuverType.arrive),
      ],
    );
    final state = NavGuidance(route).update(100).state;
    await tester.pumpWidget(_host(GoogleStyleManeuverHeader(state: state)));
    expect(find.textContaining('Dien Bien Phu'), findsOneWidget);
    expect(find.text('Then'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_band),
        matching: find.byIcon(maneuverIcon(route.steps[2])),
      ),
      findsOneWidget,
    );
  });

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('$name colours: the card and the band', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(
            state: _state(noLanes, then: afterLanes),
            colors: colors,
          ),
        ),
      );
      expect(_colorOf(tester, _card), colors.guidance);
      expect(_colorOf(tester, _band), colors.guidanceSecondary);
    });
  }

  testWidgets('rerouting: a 24 dp spinner and the text on grey, no band', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong, then: afterLanes),
          rerouting: true,
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_spinner)), const Size(24, 24));
    expect(find.text(strings.rerouting), findsOneWidget);
    expect(find.text('Ly Tu Trong'), findsNothing);
    expect(find.byKey(_band), findsNothing);
    expect(_colorOf(tester, _card), GoogleStyleColors.day.guidancePreview);
  });

  testWidgets('previewing: grey, the previewed step, its distance and '
      'chevrons', (tester) async {
    var next = 0;
    var previous = 0;
    final previewed = sampleRoute.steps[6];
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong),
          previewStep: previewed,
          previewDistance: 900,
          onNextStep: () => next++,
          onPreviousStep: () => previous++,
          colors: GoogleStyleColors.night,
        ),
      ),
    );
    expect(_colorOf(tester, _card), GoogleStyleColors.night.guidancePreview);
    expect(find.text(formatter.distance(900)), findsOneWidget);
    expect(
      find.text(
        previewed.roadName.isEmpty
            ? formatter.instruction(previewed)
            : previewed.roadName,
      ),
      findsOneWidget,
    );
    expect(find.text('Ly Tu Trong'), findsNothing);
    await tester.tap(find.byTooltip(strings.nextStep));
    await tester.tap(find.byTooltip(strings.previousStep));
    expect((next, previous), (1, 1));
    expect(
      tester.getSize(find.byTooltip(strings.nextStep)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(state: _state(noLanes), onTap: () => taps++),
      ),
    );
    await tester.tap(find.byKey(_card));
    expect(taps, 1);
  });

  testWidgets('a tap on the band, lanes or Then, calls onTap too (T5)', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong, then: afterLanes),
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.byType(GoogleStyleLaneGuidance), findsOneWidget);
    await tester.tap(find.byKey(_band));
    expect(taps, 1, reason: 'the lanes band');
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes, then: afterLanes),
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.text('Then'));
    expect(taps, 2, reason: 'the Then band');
  });

  testWidgets('previewing, the band\'s chevrons preview, not onTap', (
    tester,
  ) async {
    var taps = 0;
    var next = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes, then: afterLanes),
          previewStep: afterLanes,
          previewDistance: 300,
          onTap: () => taps++,
          onNextStep: () => next++,
          onPreviousStep: () {},
        ),
      ),
    );
    await tester.tap(find.byTooltip(strings.nextStep));
    expect((taps, next), (0, 1));
  });

  for (final direction in TextDirection.values) {
    testWidgets('a swipe towards the start previews the next step '
        '(${direction.name})', (tester) async {
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(
            state: _state(noLanes),
            onNextStep: () => next++,
            onPreviousStep: () => previous++,
          ),
          direction: direction,
        ),
      );
      final towardsStart = direction == TextDirection.ltr
          ? const Offset(-200, 0)
          : const Offset(200, 0);
      await tester.fling(find.byKey(_card), towardsStart, 1000);
      await tester.pumpAndSettle();
      expect((next, previous), (1, 0));
      await tester.fling(find.byKey(_card), -towardsStart, 1000);
      await tester.pumpAndSettle();
      expect((next, previous), (1, 1));
    });
  }

  testWidgets('screen readers get the next and previous step actions', (
    tester,
  ) async {
    var next = 0;
    var previous = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes),
          onNextStep: () => next++,
          onPreviousStep: () => previous++,
        ),
      ),
    );
    final actions = tester
        .widget<Semantics>(find.byKey(_actions))
        .properties
        .customSemanticsActions!;
    expect(actions.keys.map((a) => a.label).toSet(), {
      strings.nextStep,
      strings.previousStep,
    });
    for (final run in actions.values) {
      run();
    }
    expect((next, previous), (1, 1));
  });

  testWidgets('the semantics tree: a tap and the two step actions, no '
      'scroll actions', (tester) async {
    final handle = tester.ensureSemantics();
    var next = 0;
    var previous = 0;
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes, then: afterLanes),
          onTap: () => taps++,
          onNextStep: () => next++,
          onPreviousStep: () => previous++,
        ),
      ),
    );
    final node = tester.getSemantics(find.byKey(_actions));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.scrollLeft), isFalse);
    expect(data.hasAction(SemanticsAction.scrollRight), isFalse);
    final owner = node.owner!;
    final ids = {
      for (final id in data.customSemanticsActionIds!)
        CustomSemanticsAction.getAction(id)!.label: id,
    };
    expect(ids.keys.toSet(), {strings.nextStep, strings.previousStep});
    owner.performAction(
      node.id,
      SemanticsAction.customAction,
      ids[strings.nextStep],
    );
    owner.performAction(
      node.id,
      SemanticsAction.customAction,
      ids[strings.previousStep],
    );
    expect((next, previous), (1, 1));
    final card = tester.getSemantics(find.byKey(_card));
    expect(card.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    owner.performAction(card.id, SemanticsAction.tap);
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a slow drag does not preview a step', (tester) async {
    var next = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes),
          onNextStep: () => next++,
          onPreviousStep: () {},
        ),
      ),
    );
    // 200 px over 4 s: 50 px/s, under the swipe speed.
    await tester.timedDrag(
      find.byKey(_card),
      const Offset(-200, 0),
      const Duration(seconds: 4),
    );
    await tester.pumpAndSettle();
    expect(next, 0);
  });

  testWidgets('previewing, the band is grey like the card', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes, then: afterLanes),
          previewStep: afterLanes,
          previewDistance: 300,
          onNextStep: () {},
          onPreviousStep: () {},
        ),
      ),
    );
    expect(_colorOf(tester, _band), GoogleStyleColors.day.guidancePreview);
    expect(_colorOf(tester, _card), GoogleStyleColors.day.guidancePreview);
  });

  testWidgets('the band has the card\'s corner radius and elevation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(state: _state(noLanes, then: afterLanes)),
      ),
    );
    final card = tester.widget<Material>(find.byKey(_card));
    final band = tester.widget<Material>(find.byKey(_band));
    expect(band.elevation, card.elevation);
    expect(
      band.borderRadius,
      const BorderRadius.vertical(bottom: Radius.circular(16)),
    );
  });

  testWidgets('arrival: a flag, arrived, the destination and its address', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const GoogleStyleManeuverHeader.arrival(
          destination: PlaceLabel(
            name: 'Landmark 81',
            address: '720A Dien Bien Phu',
          ),
          lastRoad: 'Nguyen Huu Canh',
        ),
      ),
    );
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.text(strings.arrived), findsOneWidget);
    expect(find.text('Landmark 81'), findsOneWidget);
    expect(find.text('720A Dien Bien Phu'), findsOneWidget);
    expect(find.text('Nguyen Huu Canh'), findsNothing);
    expect(_colorOf(tester, _card), GoogleStyleColors.day.guidance);
    expect(find.byKey(_band), findsNothing);
  });

  testWidgets('arrival without a label shows the last road', (tester) async {
    await tester.pumpWidget(
      _host(
        const GoogleStyleManeuverHeader.arrival(lastRoad: 'Nguyen Huu Canh'),
      ),
    );
    expect(find.text('Nguyen Huu Canh'), findsOneWidget);
  });

  for (final blank in ['', '   ']) {
    testWidgets('arrival with a blank name "$blank" shows the last road '
        '(T9-3)', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader.arrival(
            destination: PlaceLabel(name: blank, address: '720A Dien Bien Phu'),
            lastRoad: 'Nguyen Huu Canh',
          ),
        ),
      );
      expect(find.text('Nguyen Huu Canh'), findsOneWidget);
      expect(find.text('720A Dien Bien Phu'), findsOneWidget);
    });
  }

  testWidgets('Vietnamese formatter and strings', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleManeuverHeader(
          state: _state(noLanes, then: afterLanes),
          formatter: const VietnameseGuidanceFormatter(),
          strings: const NavigationStrings.vietnamese(),
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

  for (final direction in TextDirection.values) {
    testWidgets('2x text at 320 dp, ${direction.name}: every mode fits', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final long = List.filled(12, 'Đường Nguyễn').join(' ');
      for (final header in [
        GoogleStyleManeuverHeader(
          state: _state(lyTuTrong, distance: 12345, then: afterLanes),
        ),
        GoogleStyleManeuverHeader(state: _state(noLanes), rerouting: true),
        GoogleStyleManeuverHeader(
          state: _state(noLanes),
          previewStep: noLanes,
          previewDistance: 98765,
          onNextStep: () {},
          onPreviousStep: () {},
        ),
        GoogleStyleManeuverHeader.arrival(
          destination: PlaceLabel(name: long, address: long),
          strings: const NavigationStrings.vietnamese(),
        ),
      ]) {
        await tester.pumpWidget(_host(header, direction: direction, scale: 2));
        expect(tester.takeException(), isNull, reason: '$header');
      }
    });
  }

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
}
