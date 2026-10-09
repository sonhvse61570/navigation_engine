// The Google look wave, fix round: route options always reachable, the
// floating controls hidden under the open menu, toggles flipping in place,
// the switch and the lone speedometer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

const _centre = ValueKey('google_style_trip_sheet_centre');
const _cluster = ValueKey('google_style_speed_cluster');
const _speedometer = ValueKey('google_style_speedometer');

final _progress = TripProgress(
  remainingDistance: 6900,
  remainingDuration: const Duration(minutes: 21),
  eta: DateTime(2026, 10, 9, 9, 55),
  fraction: 0.2,
);

Widget _sheetHost(Widget child) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        const Expanded(child: Center(child: Text('MAP'))),
        child,
      ],
    ),
  ),
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

  group('stack priorities', () {
    List<Widget> boxes() => [
      for (var i = 0; i < 4; i++)
        SizedBox(key: ValueKey('b$i'), width: 48, height: 48),
    ];

    // b0 compass, b1 search, b2 sound, b3 route options: search goes first,
    // then sound, then the compass; route options stay.
    for (final (height, shown) in [
      (228.0, [0, 1, 2, 3]),
      (227.0, [0, 2, 3]),
      (168.0, [0, 2, 3]),
      (167.0, [0, 3]),
      (108.0, [0, 3]),
      (107.0, [3]),
      (48.0, [3]),
    ]) {
      testWidgets('$height high: $shown, in their order', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: GoogleStyleControlStack(
                  priorities: const [2, 0, 1, 3],
                  children: boxes(),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          expect(
            find.byKey(ValueKey('b$i')),
            shown.contains(i) ? findsOneWidget : findsNothing,
            reason: 'b$i',
          );
        }
        for (var k = 1; k < shown.length; k++) {
          expect(
            tester.getRect(find.byKey(ValueKey('b${shown[k]}'))).top,
            greaterThan(
              tester.getRect(find.byKey(ValueKey('b${shown[k - 1]}'))).top,
            ),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('priorities must match the children', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GoogleStyleControlStack(
            priorities: [1],
            children: [SizedBox(), SizedBox()],
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('route options always reachable (drop-in)', () {
    for (final (name, size, scale, short) in [
      ('360x640 at 2x', const Size(360, 640), 2.0, true),
      ('844x390 at 2x', const Size(844, 390), 2.0, false),
    ]) {
      dropInTest('$name: route options kept; search and sound go first', (
        tester,
        h,
      ) async {
        await h.mount(tester, size: size, scale: scale);
        await h.drive(
          tester,
          routes: [sampleRoute, sampleRouteAlternatives.single],
        );
        // After the report pill becomes a circle.
        await h.run(
          tester,
          2,
          fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
        );
        final stack = find.byType(GoogleStyleControlStack);
        final options = find.descendant(
          of: stack,
          matching: find.byTooltip(strings.routeOptions),
        );
        expect(options, findsOneWidget);
        final search = find.byTooltip(strings.searchAlongRoute);
        final sound = find.byTooltip(strings.sound);
        // Search goes before sound, and sound before the compass.
        if (search.evaluate().isNotEmpty) expect(sound, findsOneWidget);
        if (sound.evaluate().isNotEmpty) {
          expect(find.byType(GoogleStyleCompassButton), findsOneWidget);
        }
        if (short) expect(search, findsNothing, reason: 'too short for all');
        await tester.tap(options);
        await tester.pump();
        expect(h.flow.state.value, isA<FlowOverview>());
      });
    }

    dropInTest('the search hides route options', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      expect(find.byTooltip(strings.routeOptions), findsOneWidget);
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      expect(find.byTooltip(strings.routeOptions), findsNothing);
    });
  });

  group('the open menu hides the floating controls', () {
    dropInTest('the stack, the speed cluster and Report go; they come back '
        'on collapse', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      final floating = [
        find.byType(GoogleStyleControlStack),
        find.byType(GoogleStyleSpeedCluster),
        find.byType(GoogleStyleReportButton),
      ];
      for (final f in floating) {
        expect(f, findsOneWidget);
      }
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      for (final f in floating) {
        expect(f, findsNothing, reason: '$f while open');
      }
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      for (final f in floating) {
        expect(f, findsOneWidget, reason: '$f after collapse');
      }
    });

    dropInTest('Re-center goes too, and comes back', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      h.session.follow = false;
      await h.frames(tester);
      final recenter = find.byType(GoogleStyleRecenterButton);
      expect(recenter, findsOneWidget);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(recenter, findsNothing);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(recenter, findsOneWidget);
    });

    dropInTest('in the landscape side panel too', (tester, h) async {
      await h.mount(tester, size: const Size(915, 412));
      await h.drive(tester);
      expect(find.byType(GoogleStyleReportButton), findsOneWidget);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(find.byType(GoogleStyleReportButton), findsNothing);
      expect(find.byType(GoogleStyleControlStack), findsNothing);
    });
  });

  group('toggles flip in place', () {
    testWidgets('a toggle row or its switch keeps the menu open; another '
        'row closes it', (tester) async {
      final log = <String>[];
      final changes = <bool>[];
      var traffic = false;
      await tester.pumpWidget(
        _sheetHost(
          StatefulBuilder(
            builder: (context, setState) => GoogleStyleTripSheet(
              progress: _progress,
              onExpandedChanged: changes.add,
              actions: [
                GoogleStyleSheetAction(
                  icon: Icons.traffic,
                  label: strings.showTraffic,
                  selected: traffic,
                  onPressed: () {
                    log.add('traffic');
                    setState(() => traffic = !traffic);
                  },
                ),
                GoogleStyleSheetAction(
                  icon: Icons.format_list_bulleted,
                  label: strings.directions,
                  onPressed: () => log.add('directions'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_centre));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.showTraffic));
      await tester.pump();
      expect(log, ['traffic']);
      expect(find.text(strings.directions), findsOneWidget, reason: 'open');
      expect(_toggled(tester, strings.showTraffic), isTrue);
      await tester.tap(_switchOf(strings.showTraffic));
      await tester.pump();
      expect(log, ['traffic', 'traffic']);
      expect(find.text(strings.directions), findsOneWidget, reason: 'open');
      expect(_toggled(tester, strings.showTraffic), isFalse);
      expect(changes, [true]);
      await tester.tap(find.text(strings.directions));
      await tester.pump();
      expect(log.last, 'directions');
      expect(find.text(strings.directions), findsNothing, reason: 'closed');
      expect(changes, [true, false]);
    });
  });

  // The switch's look (colours, thumb, shadow, no theme of its own) is
  // tested in google_style_look_fix2_test.dart (fix round 2, M5).
  group('switch look', () {
    test('the switch tokens', () {
      expect(GoogleStyleColors.day.accent, const Color(0xFF1A73E8));
      expect(GoogleStyleColors.day.switchThumb, const Color(0xFFFFFFFF));
      expect(GoogleStyleColors.day.switchTrackOff, const Color(0xFFDADCE0));
      expect(GoogleStyleColors.night.switchThumb, const Color(0xFFE8EAED));
      expect(GoogleStyleColors.night.switchTrackOff, const Color(0xFF5F6368));
    });
  });

  group('lone speedometer', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('without a limit: a white circle with the speed and unit', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(GoogleStyleSpeedCluster(info: SpeedInfo(speed: 36 / 3.6))),
      );
      final cluster = tester.widget<Material>(find.byKey(_cluster));
      expect(cluster.shape, isA<CircleBorder>());
      expect(cluster.color, GoogleStyleColors.day.speedometerSurface);
      final size = tester.getSize(find.byKey(_cluster));
      expect(size.width, size.height);
      expect(size.width, inInclusiveRange(56, 60));
      expect(find.text('36'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
      expect(find.byKey(_speedometer), findsOneWidget);
    });

    testWidgets('with a limit: the joined, rounded cluster', (tester) async {
      await tester.pumpWidget(
        host(
          GoogleStyleSpeedCluster(
            info: SpeedInfo(speed: 36 / 3.6, limit: 50 / 3.6),
          ),
        ),
      );
      final cluster = tester.widget<Material>(find.byKey(_cluster));
      expect(cluster.borderRadius, BorderRadius.circular(16));
      expect(cluster.shape, isNot(isA<CircleBorder>()));
    });

    testWidgets('no overflow at 2x text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: app!,
          ),
          home: Scaffold(
            body: Center(
              child: GoogleStyleSpeedCluster(info: SpeedInfo(speed: 135 / 3.6)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('135'), findsOneWidget);
    });
  });
}
