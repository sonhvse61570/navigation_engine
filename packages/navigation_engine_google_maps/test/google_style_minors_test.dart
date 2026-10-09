import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

const _centre = ValueKey('google_style_trip_sheet_centre');
const _pill = ValueKey('google_style_sound_pill');
const _gas = ValueKey('google_style_search_chip_gas');
const _header = ValueKey('google_style_header_card');
const _toast = ValueKey('google_style_toast');

const _fuel = AlongRoutePlace(
  id: 'fuel',
  name: 'Fuel Stop',
  position: GeoPoint(10.776, 106.701),
  detour: Duration(minutes: 3),
);

void main() {
  const strings = NavigationStrings();
  final alt = sampleRouteAlternatives.single;

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> report(WidgetTester tester) async {
    await tester.tap(find.byType(GoogleStyleReportButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GoogleStyleReportSheet), findsOneWidget);
  }

  dropInTest('M7: a touch on the map during a step preview ends it without '
      'following; the preview timer never re-follows mid-pan', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    await h.drive(tester);
    final next = h.session.guidanceState!.stepIndex + 1;
    h.flow.previewStep(next);
    await h.frames(tester);
    expect(h.flow.previewedStep.value, next);
    final pan = await tester.startGesture(const Offset(200, 450));
    await tester.pump();
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isFalse);
    await pan.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(seconds: 11));
    expect(h.session.follow, isFalse, reason: 'no re-follow mid-pan');
    await pan.up();
    await tester.pump();
    expect(h.session.follow, isFalse);
  });

  dropInTest('M8: embedded in a pane narrower than the screen, the drop-in '
      'lays out like the scaffold (no side panel)', (tester, h) async {
    tester.view
      ..physicalSize = const Size(915, 412)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A 400 dp list beside a 515 dp pane: landscape, but too narrow for a
    // side panel.
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const SizedBox(width: 400),
            Expanded(
              child: GoogleStyleNavigation(
                session: h.session,
                flow: h.flow,
                initialCenter: sampleRoute.points.first,
                onReportIncident: h.reports.add,
              ),
            ),
          ],
        ),
      ),
    );
    h.platform.createView();
    await tester.pump();
    await h.drive(tester);
    await h.frames(tester);
    final sheet = tester.widget<GoogleStyleTripSheet>(
      find.byType(GoogleStyleTripSheet),
    );
    expect(sheet.floating, isFalse, reason: 'a bottom sheet, as the scaffold');
    // The bottom layout's header card keeps its 8 dp margin in the pane.
    expect(tester.getRect(find.byKey(_header)).left, closeTo(408, 0.5));
    expect(tester.getRect(find.byType(GoogleStyleTripSheet)).width, 515);
  });

  dropInTest('M10: in the side panel layout the toast is centred in the map '
      'area, and it is a live region', (tester, h) async {
    await h.mount(tester, size: const Size(915, 412));
    await h.drive(tester);
    await report(tester);
    await tester.tap(
      find.byKey(
        ValueKey('google_style_report_tile_${IncidentType.values.first.name}'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(_toast), findsOneWidget);
    final panel =
        2 * NavigationFlowScaffold.sidePanelMargin +
        NavigationFlowScaffold.sidePanelWidth(const Size(915, 412));
    final toast = tester.getRect(find.byKey(_toast));
    expect(toast.left, greaterThan(panel));
    expect(toast.center.dx, closeTo((panel + 915) / 2, 1));
    expect(
      find.ancestor(
        of: find.byKey(_toast),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
  });

  dropInTest('M10: in portrait the toast stays centred on the screen', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    await h.drive(tester);
    await report(tester);
    await tester.tap(
      find.byKey(
        ValueKey('google_style_report_tile_${IncidentType.values.first.name}'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(find.byKey(_toast)).center.dx, closeTo(200, 1));
  });

  dropInTest('re-review 4: in portrait the map padding also clears the '
      'Re-center pill, so the logo shows above it', (tester, h) async {
    await h.mount(tester);
    await h.drive(tester);
    h.session.follow = false;
    await h.frames(tester);
    await h.frames(tester);
    final padding = h.platform.mapConfiguration.padding!;
    final recenter = tester.getRect(find.byType(GoogleStyleRecenterButton));
    expect(padding.bottom, greaterThanOrEqualTo(800 - recenter.top - 0.5));
    expect(padding.top - padding.bottom, closeTo(0.4 * 800, 0.5));
    // Following again: back to the speed's band.
    h.session.follow = true;
    await h.frames(tester);
    await h.frames(tester);
    final speed = tester.getRect(find.byType(GoogleStyleSpeedCluster));
    final following = h.platform.mapConfiguration.padding!;
    expect(following.bottom, greaterThanOrEqualTo(800 - speed.top - 0.5));
  });

  // The Google look fix round: the open menu hides the right stack, so an
  // open pill closes with it, and one back then closes the menu.
  dropInTest('re-review 6: opening the menu over the open pill closes the '
      'pill; one back closes the menu', (tester, h) async {
    await h.mount(tester, pushed: true);
    await h.drive(tester);
    await tester.tap(find.byType(GoogleStyleSoundButton));
    await tester.pump();
    expect(find.byKey(_pill), findsOneWidget);
    await tester.tap(find.byKey(_centre));
    await h.settle(tester);
    final directions = find.byKey(
      ValueKey('google_style_sheet_action_${strings.directions}'),
    );
    expect(find.byKey(_pill), findsNothing, reason: 'gone with the stack');
    expect(directions, findsOneWidget);
    await back(tester);
    expect(directions, findsNothing);
    expect(find.byType(GoogleStyleNavigation), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    await h.frames(tester);
    expect(find.byType(GoogleStyleSoundButton), findsOneWidget);
    expect(find.byKey(_pill), findsNothing, reason: 'back as a circle');
  });

  dropInTest('re-review 7: the open report sheet follows a night switch', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    await h.drive(tester);
    await report(tester);
    Color titleColor() =>
        tester.widget<Text>(find.text(strings.addReport)).style!.color!;
    expect(titleColor(), GoogleStyleColors.day.onSurface);
    h.flow.nightMode = NightMode.alwaysNight;
    await h.frames(tester);
    final sheet = tester.widget<GoogleStyleReportSheet>(
      find.byType(GoogleStyleReportSheet),
    );
    expect(sheet.colors, GoogleStyleColors.night);
    expect(titleColor(), GoogleStyleColors.night.onSurface);
    expect(
      find.ancestor(
        of: find.byType(GoogleStyleReportSheet),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == GoogleStyleColors.night.surface,
        ),
      ),
      findsOneWidget,
    );
  });

  dropInTest('re-review 10: after a switch to an alternate the search runs '
      'again from the car on the new route', (tester, h) async {
    h.places = const [_fuel];
    await h.mount(tester);
    await h.drive(tester, routes: [sampleRoute, alt], from: 100);
    final driven = h.session.frame!.routeDistance!;
    await tester.tap(find.byTooltip(strings.searchAlongRoute));
    await tester.pump();
    await tester.tap(find.byKey(_gas));
    await tester.pump();
    await tester.pump();
    final before = h.searches.length;
    h.flow.selectAlternate(0);
    await h.frames(tester);
    expect(h.searches, hasLength(before + 1));
    expect(h.searches.last.route, same(alt));
    expect(h.searches.last.fromDistance, closeTo(driven, 15));
  });
}
