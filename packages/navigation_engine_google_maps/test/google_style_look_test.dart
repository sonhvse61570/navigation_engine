// The Google look wave: the header, the right stack, the buttons and the
// trip sheet restyled after two screenshots of the Google Maps app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

const _card = ValueKey('google_style_header_card');
const _band = ValueKey('google_style_header_band');
const _distance = ValueKey('google_style_header_distance');
const _needle = ValueKey('google_style_compass_needle');
const _north = ValueKey('google_style_compass_north');
const _centre = ValueKey('google_style_trip_sheet_centre');

GuidanceState _state(
  RouteStep? step, {
  double distance = 300,
  RouteStep? then,
}) => GuidanceState(
  step: step,
  stepIndex: step == null ? -1 : 1,
  distanceToStep: distance,
  thenStep: then,
  remaining: 5000,
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

/// The sheet host: the map above, [child] at the bottom.
Widget _sheetHost(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  builder: (context, app) =>
      Directionality(textDirection: direction, child: app!),
  home: Scaffold(
    body: Column(
      children: [
        const Expanded(child: Center(child: Text('MAP'))),
        child,
      ],
    ),
  ),
);

RouteStep _step(
  ManeuverType type, {
  ManeuverModifier modifier = ManeuverModifier.none,
  String road = 'Dien Bien Phu',
  List<Lane> lanes = const [],
}) => RouteStep(
  distance: 400,
  type: type,
  modifier: modifier,
  roadName: road,
  lanes: lanes,
);

final _straight = _step(
  ManeuverType.continueOn,
  modifier: ManeuverModifier.straight,
);
final _right = _step(
  ManeuverType.turn,
  modifier: ManeuverModifier.right,
  road: 'Ly Tu Trong',
);
final _thenRight = _step(
  ManeuverType.turn,
  modifier: ManeuverModifier.right,
  road: 'Nguyen Huu Canh',
);
const _lanes = [
  Lane(directions: {LaneDirection.left}),
  Lane(
    directions: {LaneDirection.right},
    valid: true,
    active: LaneDirection.right,
  ),
];

/// The one [Text] whose plain text is [text].
Text _textOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text));

/// The spans of the [Text.rich] whose plain text is [text].
List<TextSpan> _spansOf(WidgetTester tester, String text) =>
    (_textOf(tester, text).textSpan! as TextSpan).children!
        .cast<TextSpan>()
        .toList();

/// The disc (the outermost [Material]) of the round button with [tooltip].
Material _discOf(WidgetTester tester, String tooltip) =>
    tester.widget<Material>(
      find
          .descendant(
            of: find.ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(GoogleStyleRoundButton),
            ),
            matching: find.byType(Material),
          )
          .first,
    );

BorderRadius _radiusOf(
  WidgetTester tester,
  Key key, [
  TextDirection direction = TextDirection.ltr,
]) => tester.widget<Material>(find.byKey(key)).borderRadius!.resolve(direction);

final _progress = TripProgress(
  remainingDistance: 6900,
  remainingDuration: const Duration(minutes: 21),
  eta: DateTime(2026, 10, 9, 9, 55),
  fraction: 0.2,
);

/// The classic switch of the menu row [label].
Finder _switchOf(String label) =>
    find.byKey(ValueKey('google_style_sheet_switch_$label'));

/// Whether the menu row [label] is a toggle that is on (its semantics).
bool? _toggled(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(ValueKey('google_style_sheet_action_$label')),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .toggled;

void main() {
  const strings = NavigationStrings();
  const formatter = EnglishGuidanceFormatter();

  group('colours', () {
    test('the teal guidance and band, day and night', () {
      expect(GoogleStyleColors.day.guidance, const Color(0xFF015F61));
      expect(GoogleStyleColors.day.guidanceSecondary, const Color(0xFF015053));
      expect(GoogleStyleColors.night.guidance, const Color(0xFF014446));
      expect(
        GoogleStyleColors.night.guidanceSecondary,
        const Color(0xFF013436),
      );
      for (final c in [GoogleStyleColors.day, GoogleStyleColors.night]) {
        expect(c.onGuidance, const Color(0xFFFFFFFF));
      }
      // Unchanged: the preview and rerouting greys.
      expect(GoogleStyleColors.day.guidancePreview, const Color(0xFF5F6368));
      expect(GoogleStyleColors.night.guidancePreview, const Color(0xFF3C4043));
    });

    test('the compass north is red', () {
      expect(GoogleStyleColors.day.compassNorth, const Color(0xFFEA4335));
      expect(GoogleStyleColors.night.compassNorth, const Color(0xFFEA4335));
    });
  });

  group('header card', () {
    testWidgets('radius 20 all round, flat, 8 dp margin', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(_right))),
      );
      expect(_radiusOf(tester, _card), BorderRadius.circular(20));
      expect(
        tester.widget<Material>(find.byKey(_card)).elevation,
        lessThanOrEqualTo(1),
      );
      final card = tester.getRect(find.byKey(_card));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(card.left - screen.left, closeTo(8, 0.5));
      expect(screen.right - card.right, closeTo(8, 0.5));
    });

    testWidgets('a turn: a 48 dp icon, the road alone in 28 w500, no '
        'secondary line', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(_right))),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(_card),
          matching: find.byIcon(maneuverIcon(_right)),
        ),
      );
      expect(icon.size, 48);
      final road = _textOf(tester, 'Ly Tu Trong');
      expect(road.maxLines, 2);
      expect(road.overflow, TextOverflow.ellipsis);
      final spans = _spansOf(tester, 'Ly Tu Trong');
      expect(spans, hasLength(1));
      expect(spans.single.style!.fontSize, 28);
      expect(spans.single.style!.fontWeight, FontWeight.w500);
      expect(find.textContaining(strings.toward), findsNothing);
      // The secondary instruction line is gone.
      final bare = RouteStep(
        distance: _right.distance,
        type: _right.type,
        modifier: _right.modifier,
      );
      expect(find.text(formatter.instruction(bare)), findsNothing);
    });

    testWidgets('the text block is vertically centred in the card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(_right))),
      );
      final card = tester.getRect(find.byKey(_card));
      final text = tester.getRect(find.text('Ly Tu Trong'));
      expect(text.center.dy, closeTo(card.center.dy, 1));
    });

    for (final (name, step) in [
      ('continue', _straight),
      (
        'straight',
        _step(ManeuverType.turn, modifier: ManeuverModifier.straight),
      ),
      ('depart', _step(ManeuverType.depart, modifier: ManeuverModifier.right)),
      (
        'new name',
        _step(ManeuverType.newName, modifier: ManeuverModifier.straight),
      ),
    ]) {
      testWidgets('$name: a small "toward" before the road, one Text.rich', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(GoogleStyleManeuverHeader(state: _state(step))),
        );
        const plain = 'toward Dien Bien Phu';
        final text = _textOf(tester, plain);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        final spans = _spansOf(tester, plain);
        expect(spans, hasLength(2));
        expect(spans.first.text!.trim(), 'toward');
        expect(spans.first.style!.fontSize, 16);
        expect(spans.first.style!.fontWeight, FontWeight.w400);
        expect(spans.last.text, 'Dien Bien Phu');
        expect(spans.last.style!.fontSize, 28);
        expect(spans.last.style!.fontWeight, FontWeight.w500);
      });
    }

    testWidgets('a roundabout or fork straight on shows the road only', (
      tester,
    ) async {
      for (final type in [ManeuverType.roundabout, ManeuverType.fork]) {
        final step = _step(type, modifier: ManeuverModifier.straight);
        await tester.pumpWidget(
          _host(GoogleStyleManeuverHeader(state: _state(step, distance: 1500))),
        );
        expect(find.text('Dien Bien Phu'), findsOneWidget, reason: '$type');
        expect(find.byKey(_distance), findsOneWidget, reason: '$type');
      }
    });

    testWidgets('a U-turn shows the road only', (tester) async {
      final uturn = _step(
        ManeuverType.continueOn,
        modifier: ManeuverModifier.uturn,
      );
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(uturn))),
      );
      expect(find.text('Dien Bien Phu'), findsOneWidget);
      expect(find.textContaining(strings.toward), findsNothing);
    });

    testWidgets('"toward" in Vietnamese', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(
            state: _state(_straight),
            strings: const NavigationStrings.vietnamese(),
            formatter: const VietnameseGuidanceFormatter(),
          ),
        ),
      );
      expect(find.text('hướng về Dien Bien Phu'), findsOneWidget);
    });

    testWidgets('an empty road falls back to the instruction, with no '
        '"toward"', (tester) async {
      final unnamed = _step(
        ManeuverType.continueOn,
        modifier: ManeuverModifier.straight,
        road: '',
      );
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(unnamed))),
      );
      expect(find.text(formatter.instruction(unnamed)), findsOneWidget);
      expect(find.textContaining(strings.toward), findsNothing);
    });

    testWidgets('the distance sits under the icon: value 18 w600, unit 13', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(_right, distance: 180))),
      );
      final spans = _spansOf(tester, formatter.distance(180));
      expect(spans.first.text, '200');
      expect(spans.first.style!.fontSize, 18);
      expect(spans.first.style!.fontWeight, FontWeight.w600);
      expect(spans.last.text, ' m');
      expect(spans.last.style!.fontSize, 13);
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(_card),
          matching: find.byIcon(maneuverIcon(_right)),
        ),
      );
      final distance = tester.getRect(find.byKey(_distance));
      expect(distance.top, greaterThanOrEqualTo(icon.bottom - 0.5));
      expect(distance.center.dx, closeTo(icon.center.dx, 1));
    });

    testWidgets('no distance over 1 km on a continue or straight step', (
      tester,
    ) async {
      final straightTurn = _step(
        ManeuverType.turn,
        modifier: ManeuverModifier.straight,
      );
      for (final (step, distance, shown) in [
        (_straight, 1500.0, false),
        (straightTurn, 1500.0, false),
        (_straight, 900.0, true),
        (_right, 1500.0, true),
      ]) {
        await tester.pumpWidget(
          _host(
            GoogleStyleManeuverHeader(state: _state(step, distance: distance)),
          ),
        );
        expect(
          find.byKey(_distance),
          shown ? findsOneWidget : findsNothing,
          reason: '${step.type} ${step.modifier} at $distance m',
        );
      }
    });
  });

  group('"Then" tab', () {
    for (final direction in TextDirection.values) {
      testWidgets('hangs under the card\'s bottom-start corner '
          '(${direction.name})', (tester) async {
        await tester.pumpWidget(
          _host(
            GoogleStyleManeuverHeader(
              state: _state(_straight, then: _thenRight),
            ),
            direction: direction,
          ),
        );
        final card = tester.getRect(find.byKey(_card));
        final tab = tester.getRect(find.byKey(_band));
        expect(tab.top, closeTo(card.bottom, 0.5));
        expect(tab.width, lessThan(card.width / 2));
        if (direction == TextDirection.ltr) {
          expect(tab.left, closeTo(card.left, 0.5));
        } else {
          expect(tab.right, closeTo(card.right, 0.5));
        }
        // Square where it meets the card, round below.
        final cardRadius = _radiusOf(tester, _card, direction);
        final tabRadius = _radiusOf(tester, _band, direction);
        final ltr = direction == TextDirection.ltr;
        expect(
          ltr ? cardRadius.bottomLeft : cardRadius.bottomRight,
          Radius.zero,
        );
        expect(
          ltr ? cardRadius.bottomRight : cardRadius.bottomLeft,
          const Radius.circular(20),
        );
        expect(tabRadius.topLeft, Radius.zero);
        expect(tabRadius.topRight, Radius.zero);
        expect(tabRadius.bottomLeft, const Radius.circular(16));
        expect(tabRadius.bottomRight, const Radius.circular(16));
      });
    }

    testWidgets('"Then" in 24 w400 and the next icon at 40 dp, in the tab '
        'colour, flat like the card', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(state: _state(_straight, then: _thenRight)),
        ),
      );
      final then = _textOf(tester, strings.then);
      expect(then.style!.fontSize, 24);
      expect(then.style!.fontWeight, FontWeight.w400);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(_band),
          matching: find.byIcon(maneuverIcon(_thenRight)),
        ),
      );
      // A 40 dp icon box draws the arrow about 26 dp across.
      expect(icon.size, 40);
      final tab = tester.widget<Material>(find.byKey(_band));
      final card = tester.widget<Material>(find.byKey(_card));
      expect(tab.color, GoogleStyleColors.day.guidanceSecondary);
      expect(tab.elevation, card.elevation);
    });
  });

  group('lanes band', () {
    testWidgets('full card width, the tab colour, bottom radius 16; no Then', (
      tester,
    ) async {
      final withLanes = _step(
        ManeuverType.turn,
        modifier: ManeuverModifier.right,
        lanes: _lanes,
      );
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(
            state: _state(withLanes, then: _thenRight),
            colors: GoogleStyleColors.night,
          ),
        ),
      );
      final card = tester.getRect(find.byKey(_card));
      final band = tester.getRect(find.byKey(_band));
      expect(band.width, closeTo(card.width, 0.5));
      expect(band.top, closeTo(card.bottom, 0.5));
      expect(find.text(strings.then), findsNothing);
      expect(
        tester.widget<Material>(find.byKey(_band)).color,
        GoogleStyleColors.night.guidanceSecondary,
      );
      final cardRadius = _radiusOf(tester, _card);
      expect(cardRadius.bottomLeft, Radius.zero);
      expect(cardRadius.bottomRight, Radius.zero);
      expect(
        _radiusOf(tester, _band),
        const BorderRadius.vertical(bottom: Radius.circular(16)),
      );
    });
  });

  testWidgets('arrival: the same card style with the flag', (tester) async {
    await tester.pumpWidget(
      _host(
        const GoogleStyleManeuverHeader.arrival(
          destination: PlaceLabel(name: 'Landmark 81'),
        ),
      ),
    );
    expect(_radiusOf(tester, _card), BorderRadius.circular(20));
    expect(
      tester.widget<Material>(find.byKey(_card)).elevation,
      lessThanOrEqualTo(1),
    );
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.text('Landmark 81'), findsOneWidget);
  });

  group('round buttons', () {
    for (final (name, colors) in [
      ('day', GoogleStyleColors.day),
      ('night', GoogleStyleColors.night),
    ]) {
      testWidgets('a 52 dp outlined circle, nearly flat ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: GoogleStyleRoundButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () {},
                colors: colors,
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(GoogleStyleRoundButton)),
          const Size(52, 52),
        );
        final disc = _discOf(tester, 'Search');
        expect(disc.color, colors.buttonSurface);
        expect(disc.elevation, lessThanOrEqualTo(1));
        expect(
          disc.shape,
          CircleBorder(side: BorderSide(color: colors.outline)),
        );
        expect(
          colors.outline,
          name == 'day' ? const Color(0xFFDADCE0) : const Color(0xFF5F6368),
        );
      });
    }
  });

  group('compass', () {
    for (final (name, colors) in [
      ('day', GoogleStyleColors.day),
      ('night', GoogleStyleColors.night),
    ]) {
      testWidgets('a red triangle over a bold N, turning together ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: GoogleStyleCompassButton(
                bearing: 0,
                headingUp: true,
                onPressed: () {},
                colors: colors,
              ),
            ),
          ),
        );
        final n = find.descendant(
          of: find.byKey(_needle),
          matching: find.text('N'),
        );
        expect(n, findsOneWidget);
        final style = tester.widget<Text>(n).style!;
        expect(style.fontWeight!.value, greaterThanOrEqualTo(700));
        expect(style.color, colors.buttonIcon);
        final triangle = find.descendant(
          of: find.byKey(_needle),
          matching: find.byKey(_north),
        );
        expect(triangle, findsOneWidget);
        expect(triangle, paints..path(color: colors.compassNorth));
        // The triangle sits above the N.
        expect(
          tester.getRect(triangle).center.dy,
          lessThan(tester.getRect(n).center.dy),
        );
      });
    }
  });

  group('right stack (drop-in)', () {
    dropInTest('compass, search, sound, then route options', (tester, h) async {
      await h.mount(tester);
      await h.drive(
        tester,
        routes: [sampleRoute, sampleRouteAlternatives.single],
      );
      final stack = find.byType(GoogleStyleControlStack);
      double topOf(Finder f) => tester.getRect(f).top;
      final compass = find.byType(GoogleStyleCompassButton);
      final search = find.byTooltip(strings.searchAlongRoute);
      final sound = find.byTooltip(strings.sound);
      final options = find.byTooltip(strings.routeOptions);
      for (final f in [compass, search, sound, options]) {
        expect(find.descendant(of: stack, matching: f), findsOneWidget);
      }
      expect(topOf(compass), lessThan(topOf(search)));
      expect(topOf(search), lessThan(topOf(sound)));
      expect(topOf(sound), lessThan(topOf(options)));
      expect(
        find.descendant(
          of: find.byTooltip(strings.routeOptions),
          matching: find.byIcon(Icons.alt_route),
        ),
        findsOneWidget,
      );
      // No longer in the sheet.
      expect(
        find.descendant(
          of: find.byType(GoogleStyleTripSheet),
          matching: options,
        ),
        findsNothing,
      );
      await tester.tap(options);
      await tester.pump();
      expect(h.flow.state.value, isA<FlowOverview>());
    });

    dropInTest('routeOverviewButtonEnabled false hides the stack button', (
      tester,
      h,
    ) async {
      await h.mount(tester, routeOverviewButtonEnabled: false);
      await h.drive(tester);
      expect(find.byTooltip(strings.routeOptions), findsNothing);
      expect(find.byType(GoogleStyleCompassButton), findsOneWidget);
    });
  });

  group('trip sheet', () {
    testWidgets('the X is an outlined white circle with a dark cross', (
      tester,
    ) async {
      for (final colors in [GoogleStyleColors.day, GoogleStyleColors.night]) {
        await tester.pumpWidget(
          _sheetHost(
            GoogleStyleTripSheet(
              progress: _progress,
              colors: colors,
              onClose: () {},
            ),
          ),
        );
        final disc = _discOf(tester, strings.exitNavigation);
        expect(disc.color, colors.buttonSurface);
        expect(disc.elevation, 0);
        expect(
          disc.shape,
          // The darker close ring (fix round 2, M6).
          CircleBorder(side: BorderSide(color: colors.closeOutline)),
        );
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(strings.exitNavigation),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.color, colors.buttonIcon);
      }
    });

    dropInTest('the drop-in sheet has no fork; the time stays centred', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      final sheet = find.byType(GoogleStyleTripSheet);
      expect(
        find.descendant(of: sheet, matching: find.byIcon(Icons.alt_route)),
        findsNothing,
      );
      final time = find
          .descendant(of: find.byKey(_centre), matching: find.byType(Text))
          .first;
      expect(tester.getCenter(time).dx, closeTo(tester.getCenter(sheet).dx, 1));
    });

    dropInTest('the menu order: share, search, directions, traffic, '
        'satellite, settings', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      final labels = [
        strings.shareTrip,
        strings.searchAlongRoute,
        strings.directions,
        strings.showTraffic,
        strings.satellite,
        strings.settings,
      ];
      final tops = [
        for (final label in labels)
          tester
              .getRect(find.byKey(ValueKey('google_style_sheet_action_$label')))
              .top,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: labels[i]);
      }
      expect(find.text('Show traffic on map'), findsOneWidget);
      expect(find.text('Show satellite map'), findsOneWidget);
    });

    dropInTest('traffic and satellite: a switch shows the state; a tap on '
        'the row flips it in place, the menu staying open', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      for (final label in [strings.showTraffic, strings.satellite]) {
        expect(_switchOf(label), findsOneWidget);
        expect(_toggled(tester, label), isFalse);
      }
      expect(_switchOf(strings.directions), findsNothing);
      await tester.tap(find.text(strings.showTraffic));
      await h.frames(tester);
      expect(h.platform.mapConfiguration.trafficEnabled, isTrue);
      // Still open, the switch already on.
      expect(find.text(strings.directions), findsOneWidget);
      expect(_toggled(tester, strings.showTraffic), isTrue);
      expect(_toggled(tester, strings.satellite), isFalse);
    });

    testWidgets('a tap on the switch itself toggles once', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _sheetHost(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: [
              GoogleStyleSheetAction(
                icon: Icons.traffic,
                label: strings.showTraffic,
                selected: false,
                onPressed: () => log.add('traffic'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      await tester.tap(_switchOf(strings.showTraffic));
      await tester.pump();
      expect(log, ['traffic']);
    });

    for (final direction in TextDirection.values) {
      testWidgets('inset dividers between rows, from the label on '
          '(${direction.name})', (tester) async {
        final labels = [
          strings.shareTrip,
          strings.directions,
          strings.settings,
        ];
        await tester.pumpWidget(
          _sheetHost(
            GoogleStyleTripSheet(
              progress: _progress,
              actions: [
                for (final label in labels)
                  GoogleStyleSheetAction(
                    icon: Icons.settings,
                    label: label,
                    onPressed: () {},
                  ),
              ],
            ),
            direction: direction,
          ),
        );
        await tester.tap(find.byKey(_centre));
        await tester.pumpAndSettle();
        final dividers = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'google_style_sheet_divider_',
              ),
        );
        expect(dividers, findsNWidgets(labels.length - 1));
        final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
        final label = tester.getRect(find.text(strings.shareTrip));
        for (var i = 0; i < labels.length - 1; i++) {
          final rect = tester.getRect(dividers.at(i));
          if (direction == TextDirection.ltr) {
            expect(rect.left, closeTo(label.left, 1));
            expect(rect.right, closeTo(sheet.right, 0.5));
          } else {
            expect(rect.right, closeTo(label.right, 1));
            expect(rect.left, closeTo(sheet.left, 0.5));
          }
        }
      });
    }

    testWidgets('labels grey 18, icons dark', (tester) async {
      for (final colors in [GoogleStyleColors.day, GoogleStyleColors.night]) {
        await tester.pumpWidget(
          _sheetHost(
            GoogleStyleTripSheet(
              progress: _progress,
              colors: colors,
              actions: [
                GoogleStyleSheetAction(
                  icon: Icons.settings,
                  label: strings.settings,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        );
        await tester.tap(find.byKey(_centre));
        await tester.pumpAndSettle();
        final label = _textOf(tester, strings.settings);
        expect(label.style!.fontSize, 18);
        expect(label.style!.color, colors.onSurfaceVariant);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.settings)).color,
          colors.onSurface,
        );
        await tester.tap(find.byKey(_centre));
        await tester.pumpAndSettle();
      }
    });
  });
}
