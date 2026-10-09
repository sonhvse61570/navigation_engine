// The Google look wave, fix round 2 (look-review.md): the straight-on rule
// (I1), the bottom-end column (M6), and the minors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/drop_in_harness.dart';

const _card = ValueKey('google_style_header_card');
const _distance = ValueKey('google_style_header_distance');
const _centre = ValueKey('google_style_trip_sheet_centre');
const _pill = ValueKey('google_style_sound_pill');
const _report = ValueKey('google_style_report_button');

GuidanceState _state(RouteStep step, {double distance = 1500}) => GuidanceState(
  step: step,
  stepIndex: 1,
  distanceToStep: distance,
  thenStep: null,
  remaining: 5000,
  arrived: false,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topCenter, child: child),
  ),
);

RouteStep _step(ManeuverType type, ManeuverModifier modifier) => RouteStep(
  distance: 400,
  type: type,
  modifier: modifier,
  roadName: 'Dien Bien Phu',
);

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

void main() {
  const strings = NavigationStrings();
  const formatter = EnglishGuidanceFormatter();

  group('I1: straight on means straight or none', () {
    for (final modifier in [
      ManeuverModifier.left,
      ManeuverModifier.sharpRight,
      ManeuverModifier.slightLeft,
    ]) {
      testWidgets('continue ${modifier.name} at 1500 m: the distance, no '
          '"toward"', (tester) async {
        final step = _step(ManeuverType.continueOn, modifier);
        await tester.pumpWidget(
          _host(GoogleStyleManeuverHeader(state: _state(step))),
        );
        expect(find.byKey(_distance), findsOneWidget);
        expect(find.text(formatter.distance(1500)), findsOneWidget);
        expect(find.text('Dien Bien Phu'), findsOneWidget);
        expect(find.textContaining(strings.toward), findsNothing);
      });
    }

    for (final modifier in [ManeuverModifier.straight, ManeuverModifier.none]) {
      testWidgets('new name ${modifier.name} at 1500 m follows the straight '
          'rule: "toward", no distance', (tester) async {
        final step = _step(ManeuverType.newName, modifier);
        await tester.pumpWidget(
          _host(GoogleStyleManeuverHeader(state: _state(step))),
        );
        expect(find.text('toward Dien Bien Phu'), findsOneWidget);
        expect(find.byKey(_distance), findsNothing);
      });
    }

    testWidgets('new name slight right at 1500 m: a turn, its distance, no '
        '"toward"', (tester) async {
      final step = _step(ManeuverType.newName, ManeuverModifier.slightRight);
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(step))),
      );
      expect(find.text('Dien Bien Phu'), findsOneWidget);
      expect(find.byKey(_distance), findsOneWidget);
    });

    testWidgets('a depart still reads "toward"', (tester) async {
      final step = _step(ManeuverType.depart, ManeuverModifier.right);
      await tester.pumpWidget(
        _host(GoogleStyleManeuverHeader(state: _state(step, distance: 300))),
      );
      expect(find.text('toward Dien Bien Phu'), findsOneWidget);
    });
  });

  group('M6: the bottom-end column', () {
    final column = find.byType(GoogleStyleControlStack);
    Finder inColumn(Finder f) => find.descendant(of: column, matching: f);

    Future<void> settle(WidgetTester tester, DropInHarness h) =>
        h.run(tester, 2, fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s));

    dropInTest('portrait: report, compass, search, sound, route options, '
        'anchored 16 above the sheet at the end', (tester, h) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(
        tester,
        routes: [sampleRoute, sampleRouteAlternatives.single],
      );
      await settle(tester, h);
      final members = [
        inColumn(find.byType(GoogleStyleReportButton)),
        inColumn(find.byType(GoogleStyleCompassButton)),
        inColumn(find.byTooltip(strings.searchAlongRoute)),
        inColumn(find.byType(GoogleStyleSoundButton)),
        inColumn(find.byTooltip(strings.routeOptions)),
      ];
      for (final m in members) {
        expect(m, findsOneWidget);
      }
      final rects = [for (final m in members) tester.getRect(m)];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, greaterThan(rects[i - 1].top), reason: '$i');
      }
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(rects.last.bottom, closeTo(sheet.top - 16, 1));
      for (final r in rects) {
        expect(r.right, closeTo(412 - 16, 1));
      }
      final header = tester.getRect(find.byKey(_card));
      expect(rects.first.top, greaterThan(header.bottom + 16));
      // The speed cluster stays at the bottom start.
      final speed = tester.getRect(find.byType(GoogleStyleSpeedCluster));
      expect(speed.left, closeTo(16, 1));
      expect(speed.bottom, closeTo(sheet.top - 16, 1));
      // No separate bottom-end piece any more.
      expect(find.byType(GoogleStyleReportButton), findsOneWidget);
    });

    dropInTest('the report pill (first 5 s) heads the column and overlaps '
        'nothing', (tester, h) async {
      await h.mount(tester, size: const Size(360, 640), scale: 2);
      await h.drive(tester);
      final report = tester.getRect(find.byKey(_report));
      expect(inColumn(find.byKey(_report)), findsOneWidget);
      expect(report.width, greaterThan(52), reason: 'still a pill');
      for (final other in [
        find.byKey(_card),
        find.byType(GoogleStyleSpeedCluster),
        find.byType(GoogleStyleTripSheet),
      ]) {
        expect(
          report.overlaps(tester.getRect(other)),
          isFalse,
          reason: '$other',
        );
      }
      expect(inColumn(find.byTooltip(strings.routeOptions)), findsOneWidget);
    });

    dropInTest('short screen: route options and the report stay; search '
        'goes first', (tester, h) async {
      await h.mount(tester, size: const Size(360, 640), scale: 2);
      await h.drive(tester);
      await settle(tester, h);
      expect(inColumn(find.byTooltip(strings.routeOptions)), findsOneWidget);
      expect(inColumn(find.byType(GoogleStyleReportButton)), findsOneWidget);
      final search = inColumn(find.byTooltip(strings.searchAlongRoute));
      final sound = inColumn(find.byType(GoogleStyleSoundButton));
      final compass = inColumn(find.byType(GoogleStyleCompassButton));
      if (search.evaluate().isNotEmpty) expect(sound, findsOneWidget);
      if (sound.evaluate().isNotEmpty) expect(compass, findsOneWidget);
    });

    dropInTest('the empty room above the column lets touches through to '
        'the map', (tester, h) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      await settle(tester, h);
      expect(h.session.follow, isTrue);
      final top = tester.getRect(column).top;
      final header = tester.getRect(find.byKey(_card));
      // In the slot (between the header and the column), at the end.
      await tester.dragFrom(
        Offset(412 - 30, (header.bottom + top) / 2),
        const Offset(-60, 40),
      );
      await h.frames(tester);
      expect(h.session.follow, isFalse, reason: 'the map got the drag');
    });

    dropInTest('landscape side panel: at the bottom end of the map area', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(915, 412));
      await h.drive(tester);
      await settle(tester, h);
      final options = tester.getRect(
        inColumn(find.byTooltip(strings.routeOptions)),
      );
      expect(options.bottom, closeTo(412 - 16, 1));
      expect(options.right, closeTo(915 - 16, 1));
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(options.left, greaterThan(sheet.right));
    });
  });

  group('minors', () {
    testWidgets('M6: time 24 w500; "distance • arrival" 16 w400', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sheetHost(GoogleStyleTripSheet(progress: _progress, onClose: () {})),
      );
      final time = tester.widget<Text>(find.text('21 min'));
      expect(time.style!.fontSize, 24);
      expect(time.style!.fontWeight, FontWeight.w500);
      final second = tester.widget<Text>(
        find.text('${formatter.distance(6900)} • 09:55'),
      );
      expect(second.style!.fontSize, 16);
      expect(second.style!.fontWeight, FontWeight.w400);
    });

    testWidgets('M6: the X ring is the darker close outline', (tester) async {
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
        expect(
          _discOf(tester, strings.exitNavigation).shape,
          CircleBorder(side: BorderSide(color: colors.closeOutline)),
        );
      }
      expect(GoogleStyleColors.day.closeOutline, const Color(0xFFC4C7C5));
    });

    testWidgets('round button: an outline override', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: GoogleStyleRoundButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () {},
              outline: const Color(0xFF123456),
            ),
          ),
        ),
      );
      expect(
        _discOf(tester, 'Close').shape,
        const CircleBorder(side: BorderSide(color: Color(0xFF123456))),
      );
    });

    testWidgets('M7: the open sound pill matches the round buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: GoogleStyleSoundButton(
                value: AudioGuidance.sound,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump();
      final pill = tester.widget<Material>(find.byKey(_pill));
      expect(pill.elevation, lessThanOrEqualTo(1));
      expect(
        pill.shape,
        StadiumBorder(side: BorderSide(color: GoogleStyleColors.day.outline)),
      );
      expect(tester.getSize(find.byKey(_pill)).height, 52);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the report button matches the round buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: GoogleStyleReportButton(onPressed: () {})),
        ),
      );
      final button = tester.widget<Material>(find.byKey(_report));
      expect(button.elevation, lessThanOrEqualTo(1));
      expect(
        button.shape,
        StadiumBorder(side: BorderSide(color: GoogleStyleColors.day.outline)),
      );
      expect(tester.getSize(find.byKey(_report)).height, 52);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_report)), const Size(52, 52));
    });

    testWidgets('M8: rerouting in the header text style', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleManeuverHeader(
            state: _state(
              _step(ManeuverType.turn, ManeuverModifier.right),
              distance: 300,
            ),
            rerouting: true,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text(strings.rerouting));
      expect(text.style!.fontSize, 28);
      expect(text.style!.fontWeight, FontWeight.w500);
    });

    for (final (name, colors) in [
      ('day', GoogleStyleColors.day),
      ('night', GoogleStyleColors.night),
    ]) {
      testWidgets('M5: our own classic switch, no theme override ($name)', (
        tester,
      ) async {
        var on = false;
        await tester.pumpWidget(
          _sheetHost(
            StatefulBuilder(
              builder: (context, setState) => GoogleStyleTripSheet(
                progress: _progress,
                colors: colors,
                actions: [
                  GoogleStyleSheetAction(
                    icon: Icons.traffic,
                    label: strings.showTraffic,
                    selected: on,
                    onPressed: () => setState(() => on = !on),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(_centre));
        await tester.pumpAndSettle();
        final sw = find.byKey(
          ValueKey('google_style_sheet_switch_${strings.showTraffic}'),
        );
        expect(sw, findsOneWidget);
        expect(
          find.ancestor(of: sw, matching: find.byType(Theme)).evaluate().length,
          find
              .ancestor(of: find.byKey(_centre), matching: find.byType(Theme))
              .evaluate()
              .length,
          reason: 'no Theme of its own',
        );
        BoxDecoration deco(String part) {
          final w = tester.widget(
            find.descendant(
              of: sw,
              matching: find.byKey(ValueKey('google_style_sheet_switch_$part')),
            ),
          );
          return (w is AnimatedContainer
                  ? w.decoration
                  : (w as Container).decoration)!
              as BoxDecoration;
        }

        Rect rect(String part) => tester.getRect(
          find.descendant(
            of: sw,
            matching: find.byKey(ValueKey('google_style_sheet_switch_$part')),
          ),
        );
        // Off: a large white thumb with a soft shadow at the start, on a
        // light grey track, no outline.
        expect(deco('track').color, colors.switchTrackOff);
        expect(deco('track').border, isNull);
        expect(deco('thumb').color, colors.switchThumb);
        expect(deco('thumb').boxShadow, isNotEmpty);
        expect(rect('thumb').height, greaterThan(rect('track').height));
        expect(rect('thumb').center.dx, lessThan(rect('track').center.dx));
        await tester.tap(sw);
        await tester.pumpAndSettle();
        expect(on, isTrue);
        expect(deco('track').color, colors.accent);
        expect(deco('thumb').color, colors.switchThumb);
        expect(rect('thumb').center.dx, greaterThan(rect('track').center.dx));
      });
    }
  });
}
