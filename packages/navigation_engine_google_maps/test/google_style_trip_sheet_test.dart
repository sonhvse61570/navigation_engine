import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

final _progress = TripProgress(
  remainingDistance: 4900,
  remainingDuration: const Duration(minutes: 7),
  eta: DateTime(2026, 10, 8, 13, 7),
  fraction: 0.3,
);

Widget _host(
  Widget child, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  double bottomInset = 0,
}) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      padding: EdgeInsets.only(bottom: bottomInset),
    ),
    child: Directionality(textDirection: direction, child: app!),
  ),
  home: Scaffold(
    body: Column(
      children: [
        const Expanded(child: Center(child: Text('MAP'))),
        child,
      ],
    ),
  ),
);

const _handle = ValueKey('google_style_trip_sheet_handle');
const _centre = ValueKey('google_style_trip_sheet_centre');

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
  const formatter = EnglishGuidanceFormatter();
  const strings = NavigationStrings();

  List<GoogleStyleSheetAction> actions(
    List<String> log, {
    bool traffic = false,
  }) => [
    GoogleStyleSheetAction(
      icon: Icons.format_list_bulleted,
      label: strings.directions,
      onPressed: () => log.add('directions'),
    ),
    GoogleStyleSheetAction(
      icon: Icons.traffic,
      label: strings.showTraffic,
      selected: traffic,
      onPressed: () => log.add('traffic'),
    ),
  ];

  group('GoogleStyleTripSheet collapsed', () {
    testWidgets('the handle, the time, distance · ETA and the two circles', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            onClose: () => log.add('close'),
            onRouteOptions: () => log.add('options'),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(_handle)), const Size(32, 4));
      final time = tester.widget<Text>(find.text('7 min'));
      expect(time.style!.fontSize, 24);
      expect(time.style!.fontWeight, FontWeight.w500);
      expect(time.style!.color, GoogleStyleColors.day.etaText);
      final second = tester.widget<Text>(
        find.text('${formatter.distance(4900)} • 13:07'),
      );
      expect(second.style!.fontSize, 16);
      expect(second.style!.color, GoogleStyleColors.day.onSurfaceVariant);
      for (final tooltip in [strings.exitNavigation, strings.routeOptions]) {
        expect(tester.getSize(find.byTooltip(tooltip)), const Size(52, 52));
      }
      final close = _discOf(tester, strings.exitNavigation);
      expect(close.color, GoogleStyleColors.day.buttonSurface);
      await tester.tap(find.byTooltip(strings.exitNavigation));
      await tester.tap(find.byTooltip(strings.routeOptions));
      expect(log, ['close', 'options']);
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(sheet.height, greaterThanOrEqualTo(76 + 20));
    });

    testWidgets('the route-options circle has the fork icon, the close '
        'circle a cross', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            onClose: () {},
            onRouteOptions: () {},
          ),
        ),
      );
      for (final (tooltip, icon) in [
        (strings.routeOptions, Icons.alt_route),
        (strings.exitNavigation, Icons.close),
      ]) {
        expect(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the time stops growing at 1.6x text', (tester) async {
      Future<Size> time(double scale) async {
        await tester.pumpWidget(
          _host(GoogleStyleTripSheet(progress: _progress), scale: scale),
        );
        return tester.getSize(find.text('7 min'));
      }

      final at16 = await time(1.6);
      expect(at16.height, greaterThan((await time(1)).height));
      expect(await time(2), at16);
    });

    testWidgets('the circles show only with their callbacks', (tester) async {
      await tester.pumpWidget(_host(GoogleStyleTripSheet(progress: _progress)));
      expect(find.byTooltip(strings.exitNavigation), findsNothing);
      expect(find.byTooltip(strings.routeOptions), findsNothing);
      // The time stays centred.
      expect(
        tester.getCenter(find.text('7 min')).dx,
        closeTo(tester.getCenter(find.byType(GoogleStyleTripSheet)).dx, 1),
      );
    });

    testWidgets('rerouting replaces distance · ETA', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, rerouting: true)),
      );
      expect(find.text(strings.rerouting), findsOneWidget);
      expect(find.textContaining('13:07'), findsNothing);
    });

    testWidgets('night colours', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            colors: GoogleStyleColors.night,
            onClose: () {},
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('7 min')).style!.color,
        GoogleStyleColors.night.etaText,
      );
      final close = _discOf(tester, strings.exitNavigation);
      expect(close.color, GoogleStyleColors.night.buttonSurface);
    });
  });

  group('GoogleStyleTripSheet expanded', () {
    testWidgets('a tap on the centre opens the menu; an action runs and '
        'closes it', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, actions: actions(log))),
      );
      expect(find.text(strings.directions), findsNothing);
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(find.text(strings.directions), findsOneWidget);
      final row = find.byKey(
        ValueKey('google_style_sheet_action_${strings.directions}'),
      );
      expect(tester.getSize(row).height, 64);
      await tester.tap(row);
      await tester.pump();
      expect(log, ['directions']);
      expect(find.text(strings.directions), findsNothing);
    });

    testWidgets('a drag up opens it, a drag down closes it', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, actions: actions([]))),
      );
      await tester.fling(find.byKey(_handle), const Offset(0, -150), 800);
      await tester.pumpAndSettle();
      expect(find.text(strings.directions), findsOneWidget);
      await tester.fling(find.byKey(_handle), const Offset(0, 150), 800);
      await tester.pumpAndSettle();
      expect(find.text(strings.directions), findsNothing);
    });

    testWidgets('a tap outside closes it', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, actions: actions([]))),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MAP'));
      await tester.pump();
      expect(find.text(strings.directions), findsNothing);
    });

    testWidgets('a toggle row shows a switch, on when on', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([], traffic: true),
          ),
        ),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(_switchOf(strings.showTraffic), findsOneWidget);
      expect(_toggled(tester, strings.showTraffic), isTrue);
    });

    testWidgets('without actions the centre does not open anything', (
      tester,
    ) async {
      await tester.pumpWidget(_host(GoogleStyleTripSheet(progress: _progress)));
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(find.byType(Divider), findsNothing);
    });

    for (final direction in TextDirection.values) {
      testWidgets('2x text at 320 dp (${direction.name}), collapsed and '
          'expanded: no overflow', (tester) async {
        tester.view
          ..physicalSize = const Size(320, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const vi = NavigationStrings.vietnamese();
        await tester.pumpWidget(
          _host(
            GoogleStyleTripSheet(
              progress: _progress,
              formatter: const VietnameseGuidanceFormatter(),
              strings: vi,
              onClose: () {},
              onRouteOptions: () {},
              actions: [
                for (final label in [
                  vi.directions,
                  vi.searchAlongRoute,
                  vi.shareTrip,
                  vi.showTraffic,
                  vi.satellite,
                  vi.settings,
                ])
                  GoogleStyleSheetAction(
                    icon: Icons.settings,
                    label: label,
                    onPressed: () {},
                  ),
              ],
            ),
            scale: 2,
            direction: direction,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'collapsed');
        await tester.tap(find.byKey(_centre));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'expanded');
      });
    }
  });

  group('safe area', () {
    testWidgets('the trip sheet keeps its content above a 34 dp inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(progress: _progress, actions: actions([])),
          bottomInset: 34,
        ),
      );
      final screen = tester.getRect(find.byType(Scaffold));
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(sheet.bottom, closeTo(screen.bottom, 0.01));
      expect(
        tester.getRect(find.text('7 min')).bottom,
        lessThanOrEqualTo(screen.bottom - 34),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      final row = find.byKey(
        ValueKey('google_style_sheet_action_${strings.showTraffic}'),
      );
      expect(
        tester.getRect(row).bottom,
        lessThanOrEqualTo(screen.bottom - 34 + 0.01),
      );
    });

    testWidgets('the arrival sheet keeps its button above a 34 dp inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleArrivalSheet(route: sampleRoute), bottomInset: 34),
      );
      final screen = tester.getRect(find.byType(Scaffold));
      expect(
        tester.getRect(find.byType(GoogleStyleArrivalSheet)).bottom,
        closeTo(screen.bottom, 0.01),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('google_style_arrival_done')))
            .bottom,
        lessThanOrEqualTo(screen.bottom - 34 + 0.01),
      );
    });
  });

  group('GoogleStyleArrivalSheet', () {
    testWidgets('the destination, its address and a full-width Done', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleArrivalSheet(
            route: sampleRoute,
            destination: const PlaceLabel(
              name: 'Landmark 81',
              address: '720A Dien Bien Phu',
            ),
            onDone: () => done++,
          ),
        ),
      );
      expect(find.text('Landmark 81'), findsOneWidget);
      expect(find.text('720A Dien Bien Phu'), findsOneWidget);
      final button = tester.getRect(
        find.byKey(const ValueKey('google_style_arrival_done')),
      );
      final sheet = tester.getRect(find.byType(GoogleStyleArrivalSheet));
      expect(button.width, closeTo(sheet.width - 32, 0.5));
      expect(button.height, greaterThanOrEqualTo(48));
      await tester.tap(find.text(strings.done));
      expect(done, 1);
    });

    testWidgets('without a label: the last road, else "arrived"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleArrivalSheet(route: sampleRoute)),
      );
      final lastRoad = sampleRoute.steps
          .map((s) => s.roadName)
          .where((n) => n.isNotEmpty)
          .last;
      expect(find.text(lastRoad), findsOneWidget);
      await tester.pumpWidget(
        _host(
          GoogleStyleArrivalSheet(
            route: NavRoute.fromPoints(sampleRoute.points),
          ),
        ),
      );
      expect(find.text(strings.arrived), findsOneWidget);
    });

    testWidgets('a blank name falls back to the last road, then to "arrived"', (
      tester,
    ) async {
      final lastRoad = sampleRoute.steps
          .map((s) => s.roadName)
          .where((n) => n.isNotEmpty)
          .last;
      for (final name in ['', '   ']) {
        await tester.pumpWidget(
          _host(
            GoogleStyleArrivalSheet(
              route: sampleRoute,
              destination: PlaceLabel(name: name),
            ),
          ),
        );
        expect(find.text(lastRoad), findsOneWidget, reason: 'name "$name"');
      }
      await tester.pumpWidget(
        _host(
          GoogleStyleArrivalSheet(
            route: NavRoute.fromPoints(sampleRoute.points),
            destination: const PlaceLabel(name: ' '),
          ),
        ),
      );
      expect(find.text(strings.arrived), findsOneWidget);
    });

    testWidgets('2x text at 320 dp with a long name: no overflow', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final long = List.filled(10, 'Trung tâm thương mại').join(' ');
      await tester.pumpWidget(
        _host(
          GoogleStyleArrivalSheet(
            route: sampleRoute,
            destination: PlaceLabel(name: long, address: long),
            strings: const NavigationStrings.vietnamese(),
            onDone: () {},
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('floating', () {
    Material material(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GoogleStyleTripSheet),
            matching: find.byType(Material),
          )
          .first,
    );

    testWidgets('a bottom sheet by default: the top corners rounded 24', (
      tester,
    ) async {
      await tester.pumpWidget(_host(GoogleStyleTripSheet(progress: _progress)));
      expect(
        material(tester).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    });

    testWidgets('floating: a card with all four corners rounded 24', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, floating: true)),
      );
      expect(material(tester).borderRadius, BorderRadius.circular(24));
      expect(material(tester).elevation, 8);
    });
  });

  group('GoogleStyleArrivalSheet floating', () {
    Material material(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GoogleStyleArrivalSheet),
            matching: find.byType(Material),
          )
          .first,
    );

    testWidgets('a bottom sheet by default: the top corners rounded 24', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleArrivalSheet(route: sampleRoute)),
      );
      expect(
        material(tester).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    });

    testWidgets('floating: a card with all four corners rounded 24', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleArrivalSheet(route: sampleRoute, floating: true)),
      );
      expect(material(tester).borderRadius, BorderRadius.circular(24));
      expect(material(tester).elevation, 8);
    });
  });

  group('GoogleStyleTripSheet drag and animation', () {
    const row = 'google_style_sheet_action_';

    /// The sheet's height (on screen).
    double height(WidgetTester tester) =>
        tester.getSize(find.byType(GoogleStyleTripSheet)).height;

    /// The collapsed and the expanded heights of [sheet], read by opening
    /// and closing it.
    Future<(double, double)> extremes(WidgetTester tester) async {
      final collapsed = height(tester);
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      final expanded = height(tester);
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(height(tester), collapsed);
      return (collapsed, expanded);
    }

    testWidgets('a partial drag leaves the height in between and reports '
        'the fraction; it follows the finger', (tester) async {
      final fractions = <double>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([]),
            onFractionChanged: fractions.add,
          ),
        ),
      );
      final (collapsed, expanded) = await extremes(tester);
      expect(expanded - collapsed, greaterThan(100));
      fractions.clear();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      final quarter = (expanded - collapsed) / 4;
      await gesture.moveBy(Offset(0, -quarter));
      await tester.pump();
      await gesture.moveBy(Offset(0, -quarter));
      await tester.pump();
      expect(height(tester), closeTo((collapsed + expanded) / 2, 1));
      expect(fractions.last, closeTo(0.5, 0.01));
      expect(find.text(strings.directions), findsOneWidget, reason: 'fading');
      await gesture.moveBy(Offset(0, quarter));
      await tester.pump();
      expect(height(tester), closeTo(collapsed + quarter, 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(height(tester), collapsed, reason: 'short of halfway');
      expect(fractions.last, 0);
    });

    for (final direction in TextDirection.values) {
      testWidgets('2x text at 320 dp (${direction.name}): no overflow at '
          't = 0.5', (tester) async {
        tester.view
          ..physicalSize = const Size(320, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const vi = NavigationStrings.vietnamese();
        await tester.pumpWidget(
          _host(
            GoogleStyleTripSheet(
              progress: _progress,
              formatter: const VietnameseGuidanceFormatter(),
              strings: vi,
              onClose: () {},
              onRouteOptions: () {},
              actions: [
                for (final label in [
                  vi.directions,
                  vi.searchAlongRoute,
                  vi.shareTrip,
                  vi.showTraffic,
                  vi.satellite,
                  vi.settings,
                ])
                  GoogleStyleSheetAction(
                    icon: Icons.settings,
                    label: label,
                    onPressed: () {},
                  ),
              ],
            ),
            scale: 2,
            direction: direction,
          ),
        );
        final (collapsed, expanded) = await extremes(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_handle)),
        );
        await gesture.moveBy(Offset(0, -(expanded - collapsed) / 2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(height(tester), closeTo((collapsed + expanded) / 2, 1));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a fling opens it with a spring and another closes it; '
        'onExpandedChanged fires when it settles', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([]),
            onExpandedChanged: changes.add,
          ),
        ),
      );
      final (collapsed, expanded) = await extremes(tester);
      changes.clear();
      // A fast flick short of halfway (60 of 130 dp): its speed decides,
      // not its length.
      await tester.fling(find.byKey(_handle), const Offset(0, -60), 1000);
      await tester.pump(const Duration(milliseconds: 50));
      expect(height(tester), inExclusiveRange(collapsed, expanded));
      expect(changes, isEmpty, reason: 'not settled yet');
      await tester.pumpAndSettle();
      expect(height(tester), expanded);
      expect(changes, [true]);
      await tester.fling(find.byKey(_handle), const Offset(0, 60), 1000);
      await tester.pump(const Duration(milliseconds: 50));
      expect(height(tester), inExclusiveRange(collapsed, expanded));
      expect(changes, [true]);
      await tester.pumpAndSettle();
      expect(height(tester), collapsed);
      expect(changes, [true, false]);
    });

    testWidgets('a slow drag past halfway opens, short of halfway returns', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, actions: actions([]))),
      );
      final (collapsed, expanded) = await extremes(tester);
      final span = expanded - collapsed;
      // tester.drag is slow: it lifts without speed.
      await tester.drag(find.byKey(_handle), Offset(0, -span * 0.4));
      await tester.pumpAndSettle();
      expect(height(tester), collapsed, reason: 'short of halfway');
      await tester.drag(find.byKey(_handle), Offset(0, -span * 0.6));
      await tester.pumpAndSettle();
      expect(height(tester), expanded, reason: 'past halfway');
      await tester.drag(find.byKey(_handle), Offset(0, span * 0.4));
      await tester.pumpAndSettle();
      expect(height(tester), expanded, reason: 'short of halfway down');
      await tester.drag(find.byKey(_handle), Offset(0, span * 0.6));
      await tester.pumpAndSettle();
      expect(height(tester), collapsed, reason: 'past halfway down');
    });

    testWidgets('grabbed mid-animation, a slow release under 32 dp keeps '
        'the heading, wherever halfway is', (tester) async {
      final fractions = <double>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([]),
            onFractionChanged: fractions.add,
          ),
        ),
      );
      final (collapsed, expanded) = await extremes(tester);
      final span = expanded - collapsed;

      // Opening: grabbed short of halfway, pulled 25 dp down (further
      // from open), released slowly: it still opens.
      await tester.tap(find.byKey(_centre));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final t0 = fractions.last;
      expect(t0, inExclusiveRange(0.2, 0.6), reason: 'mid-animation');
      var gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      expect(fractions.last, closeTo(t0 - 25 / span, 0.02));
      expect(fractions.last, lessThan(0.5), reason: 'halfway would close');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(height(tester), expanded, reason: 'the open tap wins');

      // Closing: grabbed past halfway, pushed 20 dp up (past the touch
      // slop, under 32 dp), released: closes.
      await tester.tap(find.byKey(_centre));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final t1 = fractions.last;
      expect(t1, inExclusiveRange(0.4, 0.8), reason: 'mid-animation');
      gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(fractions.last, greaterThan(0.5), reason: 'halfway would open');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(height(tester), collapsed, reason: 'the close tap wins');
    });

    testWidgets('the release spring takes the release velocity: a fling '
        'from t = 0.6 gets further in 40 ms than a slow release', (
      tester,
    ) async {
      Future<double> after40ms(bool fling) async {
        final fractions = <double>[];
        await tester.pumpWidget(
          _host(
            GoogleStyleTripSheet(
              key: ValueKey(fling),
              progress: _progress,
              actions: actions([]),
              onFractionChanged: fractions.add,
            ),
          ),
        );
        final (collapsed, expanded) = await extremes(tester);
        final up = Offset(0, -(expanded - collapsed) * 0.6);
        if (fling) {
          await tester.fling(find.byKey(_handle), up, 1500);
        } else {
          await tester.drag(find.byKey(_handle), up);
        }
        expect(fractions.last, closeTo(0.6, 0.02), reason: 'released at');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final t = fractions.last;
        await tester.pumpAndSettle();
        expect(height(tester), expanded);
        return t;
      }

      final slow = await after40ms(false);
      final fast = await after40ms(true);
      expect(slow, inExclusiveRange(0.6, 1));
      expect(fast, greaterThan(slow + 0.1));
    });

    testWidgets('actions emptied while open: when they come back, one tap '
        'opens it', (tester) async {
      Widget sheet(List<GoogleStyleSheetAction> rows) =>
          _host(GoogleStyleTripSheet(progress: _progress, actions: rows));
      await tester.pumpWidget(sheet(actions([])));
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(find.text(strings.directions), findsOneWidget);
      await tester.pumpWidget(sheet(const []));
      await tester.pumpAndSettle();
      await tester.pumpWidget(sheet(actions([])));
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(find.text(strings.directions), findsOneWidget);
    });

    testWidgets('a tap on the centre or the handle animates open and closed '
        '(between the states after 100 ms)', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([]),
            onExpandedChanged: changes.add,
          ),
        ),
      );
      final collapsed = height(tester);
      for (final key in [_centre, _handle]) {
        await tester.tap(find.byKey(key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          height(tester),
          greaterThan(collapsed + 1),
          reason: '$key opening',
        );
        final mid = height(tester);
        await tester.pump(const Duration(milliseconds: 250));
        final expanded = height(tester);
        expect(mid, lessThan(expanded - 1), reason: '$key opening');
        expect(changes.last, isTrue);
        await tester.tap(find.byKey(key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          height(tester),
          inExclusiveRange(collapsed + 1, expanded - 1),
          reason: '$key closing',
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(height(tester), collapsed);
        expect(changes.last, isFalse);
      }
      expect(changes, [true, false, true, false]);
    });

    testWidgets('rows ignore taps until the menu is fully open', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _host(GoogleStyleTripSheet(progress: _progress, actions: actions(log))),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final directions = find.byKey(ValueKey('$row${strings.directions}'));
      expect(directions, findsOneWidget);
      await tester.tap(directions, warnIfMissed: false);
      await tester.pump();
      expect(log, isEmpty, reason: 'still opening');
      await tester.pumpAndSettle();
      await tester.tap(directions);
      await tester.pump();
      expect(log, ['directions']);
    });

    testWidgets('the system back closes it, animated; onExpandedChanged '
        'fires when it settles', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleTripSheet(
            progress: _progress,
            actions: actions([]),
            onExpandedChanged: changes.add,
          ),
        ),
      );
      final (collapsed, expanded) = await extremes(tester);
      changes.clear();
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(height(tester), inExclusiveRange(collapsed, expanded));
      expect(changes, [true]);
      await tester.pumpAndSettle();
      expect(height(tester), collapsed);
      expect(changes, [true, false]);
      expect(find.text('MAP'), findsOneWidget, reason: 'the screen stays');
    });

    testWidgets('floating (side panel): it grows upwards, its bottom fixed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 300,
                child: GoogleStyleTripSheet(
                  progress: _progress,
                  floating: true,
                  actions: actions([]),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byType(GoogleStyleTripSheet));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      final during = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(during.bottom, before.bottom);
      expect(during.top, closeTo(before.top - 60, 1));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
