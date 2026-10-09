// The Google look wave, fix round 3 (look-rereview.md): the end column
// keeps clear of the bottom-start group (I-1), the search keeps the
// column's state (m-1), and the menu rows' semantics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

const _report = ValueKey('google_style_report_button');
const _centre = ValueKey('google_style_trip_sheet_centre');

void main() {
  const strings = NavigationStrings();
  final column = find.byType(GoogleStyleControlStack);

  Future<void> collapseReport(WidgetTester tester, DropInHarness h) =>
      h.run(tester, 2, fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s));

  group('I-1: the column keeps clear of the bottom-start group', () {
    dropInTest('a wide bottom row lifts the column 16 above the group', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        size: const Size(360, 640),
        routeOverviewButtonEnabled: false,
      );
      await h.drive(tester);
      await collapseReport(tester, h);
      h.session.follow = false;
      await h.frames(tester);
      final recenter = find.byType(GoogleStyleRecenterButton);
      expect(recenter, findsOneWidget);
      // The sound button is the bottom row: its pill opens towards the
      // Re-center pill.
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await h.frames(tester);
      await h.frames(tester);
      final group = tester.getRect(recenter);
      final pill = tester.getRect(
        find.byKey(const ValueKey('google_style_sound_pill')),
      );
      expect(pill.overlaps(group), isFalse, reason: '$pill / $group');
      expect(
        tester.getRect(column).bottom,
        lessThanOrEqualTo(group.top - 16 + 0.5),
        reason: 'lifted above the group',
      );
      // Closed again, a 52 dp circle fits beside the group: no lift.
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await h.frames(tester);
      await h.frames(tester);
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(tester.getRect(column).bottom, closeTo(sheet.top - 16, 1));
    });

    dropInTest('a 52 dp bottom row beside a narrow group stays down', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      await collapseReport(tester, h);
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(tester.getRect(column).bottom, closeTo(sheet.top - 16, 1));
    });
  });

  group('m-1: the search keeps the column\'s state', () {
    dropInTest('opening and closing the search does not bring the report '
        'pill back', (tester, h) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      await collapseReport(tester, h);
      expect(tester.getSize(find.byKey(_report)), const Size(52, 52));
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await h.frames(tester);
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(find.byKey(_report)), const Size(52, 52));
      await tester.tap(find.byTooltip(strings.cancel));
      await h.frames(tester);
      await h.frames(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(tester.getSize(find.byKey(_report)), const Size(52, 52));
    });
  });

  group('menu row semantics', () {
    dropInTest('a toggle row is one button node with its label and state', (
      tester,
      h,
    ) async {
      final handle = tester.ensureSemantics();
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      final row = find.byKey(
        ValueKey('google_style_sheet_action_${strings.showTraffic}'),
      );
      expect(
        tester.getSemantics(row),
        matchesSemantics(
          label: strings.showTraffic,
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      // The drawn switch adds no node of its own.
      expect(
        tester.getSemantics(
          find.byKey(
            ValueKey('google_style_sheet_switch_${strings.showTraffic}'),
          ),
        ),
        same(tester.getSemantics(row)),
      );
      handle.dispose();
    });
  });
}
