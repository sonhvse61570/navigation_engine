// The review screenshots, written only when NAV_SCREENSHOTS names a
// directory:
//   NAV_SCREENSHOTS=/tmp/shots flutter test test/screenshots_test.dart
// The fake map platform draws no tiles, lines or markers: the map area is
// blank, and alternates and pins show only in the cards and the overlays.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';
import 'support/screenshots.dart';

void main() {
  final skip = screenshotDir == null;
  final alt = sampleRouteAlternatives.single;
  const label = PlaceLabel(name: 'Landmark 81', address: '720A Dien Bien Phu');
  const portrait = Size(412, 915);

  setUpAll(() async {
    if (!skip) await loadScreenshotFonts();
  });

  Widget chips(BuildContext context) => const SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.all(8),
        // The drop-in has no Scaffold: the app's idle overlay brings its
        // own Material.
        child: Material(
          type: MaterialType.transparency,
          child: Chip(avatar: Icon(Icons.place), label: Text('Landmark 81')),
        ),
      ),
    ),
  );

  void shot(
    String name,
    Future<void> Function(WidgetTester tester, DropInHarness h) body, {
    NightMode nightMode = NightMode.alwaysDay,
  }) => dropInTest(
    name,
    (tester, h) async {
      // Real shadows: under test they are drawn as black outlines.
      debugDisableShadows = false;
      try {
        await body(tester, h);
        expect(tester.takeException(), isNull);
        await saveScreenshot(tester, name);
      } finally {
        debugDisableShadows = true;
      }
    },
    nightMode: nightMode,
    skip: skip,
  );

  shot('01_idle', (tester, h) async {
    await h.mount(tester, size: portrait, idleBuilder: chips);
  });

  shot('02_route_overview', (tester, h) async {
    await h.mount(tester, size: portrait);
    h.flow.previewRoutes([sampleRoute, alt], destination: label);
    await h.frames(tester);
  });

  shot('03_navigating_following', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester, destination: label);
  });

  // The Google look wave's reference screenshot: "toward" a road over
  // 1 km ahead (no distance), with a right turn just after it ("Then").
  shot('13_navigating_toward_then', (tester, h) async {
    final route = NavRoute.fromPoints(
      const [
        GeoPoint(10.7700, 106.7000),
        GeoPoint(10.7810, 106.7000),
        GeoPoint(10.7815, 106.7000),
        GeoPoint(10.7815, 106.7020),
      ],
      steps: const [
        RouteStepSeed.atVertex(
          1,
          type: ManeuverType.continueOn,
          modifier: ManeuverModifier.straight,
          roadName: 'Điện Biên Phủ',
        ),
        RouteStepSeed.atVertex(
          2,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.right,
          roadName: 'Nguyễn Hữu Cảnh',
        ),
        RouteStepSeed.atVertex(3, type: ManeuverType.arrive),
      ],
    );
    await h.mount(tester, size: portrait);
    await h.drive(tester, routes: [route], from: 0);
  });

  shot('04_navigating_panned_recenter', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester);
    h.session.follow = false;
    await h.frames(tester);
  });

  shot('05_step_list', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester);
    await tester.tap(find.byKey(const ValueKey('google_style_header_card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  shot('06_arrival', (tester, h) async {
    await h.mount(tester, size: portrait);
    h.flow.previewRoutes([sampleRoute], destination: label);
    await tester.pump();
    h.flow.start();
    await h.run(
      tester,
      8,
      fixAt: (s) =>
          h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
    );
  });

  shot('07_navigating_night', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester);
  }, nightMode: NightMode.alwaysNight);

  shot('08_navigating_landscape', (tester, h) async {
    await h.mount(tester, size: const Size(915, 412));
    await h.drive(tester);
  });

  shot('09_sheet_expanded', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester);
    await tester.tap(
      find.byKey(const ValueKey('google_style_trip_sheet_centre')),
    );
    await tester.pump();
    // The open menu hides the floating controls; let the tap's ink fade
    // before the capture (M9).
    await h.frames(tester);
    await tester.pump(const Duration(seconds: 1));
  });

  // The trip sheet held half way up: its height between the two states,
  // the menu fading in and the floating controls fading out. The capture
  // is taken before the finger lifts.
  dropInTest('14_sheet_half_dragged', (tester, h) async {
    debugDisableShadows = false;
    try {
      await h.mount(tester, size: portrait);
      await h.drive(tester);
      const centre = ValueKey('google_style_trip_sheet_centre');
      double height() =>
          tester.getSize(find.byType(GoogleStyleTripSheet)).height;
      final collapsed = height();
      await tester.tap(find.byKey(centre));
      await h.settle(tester);
      final expanded = height();
      await tester.tap(find.byKey(centre));
      await h.settle(tester);
      await tester.pump(const Duration(seconds: 1));
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('google_style_trip_sheet_handle')),
        ),
      );
      await gesture.moveBy(Offset(0, -(expanded - collapsed) / 2));
      await h.frames(tester);
      expect(tester.takeException(), isNull);
      await saveScreenshot(tester, '14_sheet_half_dragged');
      await gesture.up();
      await h.settle(tester);
    } finally {
      debugDisableShadows = true;
    }
  }, skip: skip);

  shot('10_report_sheet', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester);
    await tester.tap(find.byType(GoogleStyleReportButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  shot('11_search', (tester, h) async {
    h.places = [
      for (var i = 1; i <= 3; i++)
        AlongRoutePlace(
          id: '$i',
          name: 'Gas station $i',
          position: offsetPoint(sampleRoute.pointAt(600.0 + i * 700), 90, 40),
          detour: Duration(minutes: i),
          subtitle: '${(i * 0.7).toStringAsFixed(1)} km ahead',
        ),
    ];
    await h.mount(tester, size: portrait);
    await h.drive(tester);
    await tester.tap(find.byTooltip(h.strings.searchAlongRoute));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('google_style_search_chip_gas')),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Gas station 1'));
    await h.frames(tester);
  });

  shot('12_alternates', (tester, h) async {
    await h.mount(tester, size: portrait);
    await h.drive(tester, routes: [sampleRoute, alt], from: 100);
    await tester.tap(find.byTooltip(h.strings.routeOptions));
    await h.frames(tester);
  });
}
