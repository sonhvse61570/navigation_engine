import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

/// A provider whose reroutes return one fresh route, the same instance
/// every time (so the alternates request after a reroute finds none).
class _FreshReroutes extends RouteProvider {
  NavRoute? fresh;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      fresh ??= NavRoute.fromPoints([from, to]);

  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) async => [await route(from, to, heading: heading)];
}

const _header = ValueKey('google_style_header_card');
const _centre = ValueKey('google_style_trip_sheet_centre');

Color _cardColor(WidgetTester tester) =>
    tester.widget<Material>(find.byKey(_header)).color!;

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
  final alt = sampleRouteAlternatives.single;

  group('header (D1, D9)', () {
    dropInTest('a tap opens the step list', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byKey(_header));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleStepList), findsOneWidget);
    });

    dropInTest('a swipe previews the next step in grey; Re-center ends it', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      final current = h.session.guidanceState!.stepIndex;
      await tester.fling(find.byKey(_header), const Offset(-200, 0), 1000);
      await h.frames(tester);
      expect(h.flow.previewedStep.value, current + 1);
      expect(h.session.follow, isFalse);
      expect(_cardColor(tester), GoogleStyleColors.day.guidancePreview);
      expect(find.byType(GoogleStyleSpeedCluster), findsNothing);
      await tester.tap(find.byType(GoogleStyleRecenterButton));
      await h.frames(tester);
      expect(h.flow.previewedStep.value, isNull);
      expect(h.session.follow, isTrue);
      expect(_cardColor(tester), GoogleStyleColors.day.guidance);
    });

    dropInTest('swiping past the last step or back past the current step', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, from: sampleRoute.length - 700);
      final current = h.session.guidanceState!.stepIndex;
      final last = sampleRoute.steps.length - 1;
      Future<void> swipe(Offset towards) async {
        await tester.fling(find.byKey(_header), towards, 1000);
        await h.frames(tester);
      }

      await swipe(const Offset(200, 0)); // back, before any preview
      expect(h.flow.previewedStep.value, isNull);
      expect(h.session.follow, isTrue);
      for (var i = current + 1; i <= last; i++) {
        await swipe(const Offset(-200, 0));
        expect(h.flow.previewedStep.value, i);
      }
      await swipe(const Offset(-200, 0)); // past the last
      expect(h.flow.previewedStep.value, last);
      expect(tester.takeException(), isNull);
      for (var i = last; i > current; i--) {
        await swipe(const Offset(200, 0));
      }
      expect(h.flow.previewedStep.value, isNull);
      expect(h.session.follow, isTrue);
    });

    dropInTest('rerouting: the header shows the spinner on grey', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      await h.run(
        tester,
        7,
        fixAt: (s) => NavFix(
          position: offsetPoint(
            sampleRoute.pointAt(560.0 + 5 * s),
            sampleRoute.bearingAt(560) + 90,
            60,
          ),
          accuracy: 5,
          speed: 5,
          time: h.now,
        ),
      );
      expect(h.flow.rerouting.value, isTrue);
      expect(
        find.byKey(const ValueKey('google_style_header_spinner')),
        findsOneWidget,
      );
      expect(find.text(strings.rerouting), findsWidgets);
      expect(_cardColor(tester), GoogleStyleColors.day.guidancePreview);
    }, provider: PendingReroutes.new);

    dropInTest(
      'arrival: the header with the destination, the sheet with Done',
      (tester, h) async {
        await h.mount(tester);
        h.flow.previewRoutes([
          sampleRoute,
        ], destination: const PlaceLabel(name: 'Landmark 81', address: '720A'));
        await tester.pump();
        h.flow.start();
        await tester.pump();
        await h.run(
          tester,
          8,
          fixAt: (s) =>
              h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
        );
        expect(h.flow.state.value, isA<FlowArrived>());
        expect(find.byIcon(Icons.flag), findsOneWidget);
        expect(find.text(strings.arrived), findsOneWidget);
        expect(find.text('Landmark 81'), findsNWidgets(2));
        expect(find.byType(GoogleStyleArrivalSheet), findsOneWidget);
        await tester.tap(find.text(strings.done));
        await tester.pump();
        expect(h.flow.state.value, isA<FlowIdle>());
      },
    );
  });

  group('right stack (D2)', () {
    dropInTest('compass, search, sound and route options, 16 apart, at the end '
        'under the header', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      final header = tester.getRect(find.byKey(_header));
      final compass = tester.getRect(find.byType(GoogleStyleCompassButton));
      final search = tester.getRect(find.byTooltip(strings.searchAlongRoute));
      final sound = tester.getRect(find.byTooltip(strings.sound));
      final options = tester.getRect(find.byTooltip(strings.routeOptions));
      expect(compass.top, greaterThanOrEqualTo(header.bottom));
      expect(compass.right, closeTo(400 - 16, 1));
      expect(search.top, closeTo(compass.bottom + 16, 1));
      expect(sound.top, closeTo(search.bottom + 16, 1));
      expect(options.top, closeTo(sound.bottom + 16, 1));
      expect(compass.size, const Size(52, 52));
    });

    // The Google look fix round 2: the column is anchored above the sheet
    // and drops by priority (search, sound, compass, then the report);
    // route options stay. No lift beside the speed (B4) any more.
    dropInTest('a short screen drops by priority, keeping route options '
        'and the report, above the sheet', (tester, h) async {
      await h.mount(tester, size: const Size(360, 640), scale: 2);
      await h.drive(tester);
      expect(tester.takeException(), isNull);
      final column = find.byType(GoogleStyleControlStack);
      Finder inColumn(Finder f) => find.descendant(of: column, matching: f);
      expect(inColumn(find.byTooltip(strings.routeOptions)), findsOneWidget);
      expect(inColumn(find.byType(GoogleStyleReportButton)), findsOneWidget);
      await h.run(
        tester,
        2,
        fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
      );
      expect(tester.takeException(), isNull);
      expect(inColumn(find.byTooltip(strings.routeOptions)), findsOneWidget);
      expect(inColumn(find.byType(GoogleStyleCompassButton)), findsOneWidget);
      expect(inColumn(find.byTooltip(strings.searchAlongRoute)), findsNothing);
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(tester.getRect(column).bottom, closeTo(sheet.top - 16, 1));
    });

    dropInTest(
      'the sound pill calls onAudioGuidanceChanged; the icon follows',
      (tester, h) async {
        await h.mount(tester);
        await h.drive(tester);
        await tester.tap(find.byTooltip(strings.sound));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('google_style_sound_option_alertsOnly')),
        );
        await h.frames(tester);
        expect(h.audioChanges, [AudioGuidance.alertsOnly]);
        expect(find.byTooltip(strings.alertsOnly), findsOneWidget);
      },
    );
  });

  group('report (D3)', () {
    dropInTest(
      'a pill, then a circle; the sheet, the callback and a 3 s toast',
      (tester, h) async {
        await h.mount(tester);
        await h.drive(tester);
        final report = find.byType(GoogleStyleReportButton);
        // It heads the end column, above the compass (fix round 2).
        expect(tester.getRect(report).right, closeTo(400 - 16, 1));
        expect(
          tester.getRect(report).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(GoogleStyleCompassButton)).top -
                16 +
                0.5,
          ),
        );
        await h.run(
          tester,
          2,
          fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
        );
        expect(
          find.descendant(of: report, matching: find.text(strings.report)),
          findsNothing,
          reason: 'a circle after 5 s',
        );
        await tester.tap(report);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(
          find.byKey(const ValueKey('google_style_report_tile_police')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(h.reports, [IncidentType.police]);
        expect(find.text(strings.reportSent), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(strings.reportSent), findsNothing);
      },
    );
  });

  group('toggles rule (D12)', () {
    dropInTest('a control shows only with its toggle on and its callback', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        reportButtonEnabled: false,
        searchButtonEnabled: false,
        routeOverviewButtonEnabled: false,
      );
      await h.drive(tester);
      expect(find.byType(GoogleStyleReportButton), findsNothing);
      expect(find.byTooltip(strings.searchAlongRoute), findsNothing);
      expect(find.byTooltip(strings.routeOptions), findsNothing);
      expect(find.byTooltip(strings.sound), findsOneWidget);
      // The sheet's menu keeps Search along route: only the button is off.
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(find.text(strings.searchAlongRoute), findsOneWidget);
    });

    dropInTest(
      'without callbacks: no sound, search, report, share or settings',
      (tester, h) async {
        await h.mount(tester, callbacks: false);
        await h.drive(tester);
        expect(find.byType(GoogleStyleSoundButton), findsNothing);
        expect(find.byTooltip(strings.searchAlongRoute), findsNothing);
        expect(find.byType(GoogleStyleReportButton), findsNothing);
        await tester.tap(find.byKey(_centre));
        await h.settle(tester);
        expect(find.text(strings.directions), findsOneWidget);
        expect(find.text(strings.showTraffic), findsOneWidget);
        expect(find.text(strings.satellite), findsOneWidget);
        expect(find.text(strings.shareTrip), findsNothing);
        expect(find.text(strings.settings), findsNothing);
        expect(find.text(strings.searchAlongRoute), findsNothing);
      },
    );

    dropInTest(
      'the progress bar is off by default; on, it hides under 552 dp',
      (tester, h) async {
        await h.mount(tester);
        await h.drive(tester);
        expect(find.byType(GoogleStyleTripProgressBar), findsNothing);
        await tester.pumpWidget(h.app(tripProgressBarEnabled: true));
        await h.frames(tester);
        expect(find.byType(GoogleStyleTripProgressBar), findsOneWidget);
        tester.view.physicalSize = const Size(400, 540);
        await h.frames(tester);
        expect(find.byType(GoogleStyleTripProgressBar), findsNothing);
      },
    );
  });

  group('speed (D4)', () {
    dropInTest('the cluster hides while Re-center shows; a tap on the sign '
        'toggles the speedometer, kept across Re-center', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      final cluster = find.byType(GoogleStyleSpeedCluster);
      final speedometer = find.byKey(
        const ValueKey('google_style_speedometer'),
      );
      expect(speedometer, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('google_style_speed_limit')));
      await h.frames(tester);
      expect(speedometer, findsNothing);
      h.session.follow = false;
      await h.frames(tester);
      expect(cluster, findsNothing);
      final recenter = tester.getRect(find.byType(GoogleStyleRecenterButton));
      expect(recenter.left, closeTo(16, 1));
      await tester.tap(find.byType(GoogleStyleRecenterButton));
      await h.frames(tester);
      expect(cluster, findsOneWidget);
      expect(speedometer, findsNothing, reason: 'the choice is kept');
    });
  });

  group('trip sheet (D5)', () {
    dropInTest('X ends; the fork opens the trip overview with the alternates', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, routes: [sampleRoute, alt], from: 100);
      expect(h.flow.alternates.value, hasLength(1));
      await tester.tap(find.byTooltip(strings.routeOptions));
      await tester.pump();
      final overview = h.flow.state.value as FlowOverview;
      expect(overview.routes, [same(sampleRoute), same(alt)]);
      expect(find.byKey(const ValueKey('route_card_1')), findsOneWidget);
      await tester.tap(find.text(strings.resume));
      await tester.pump();
      expect(h.flow.state.value, isA<FlowNavigating>());
      await tester.tap(find.byTooltip(strings.exitNavigation));
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
    });

    dropInTest('the menu: directions, share, traffic, satellite and settings', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      Future<void> run(String label) async {
        await tester.tap(find.byKey(_centre));
        await h.settle(tester);
        await tester.tap(find.text(label));
        await h.frames(tester);
      }

      await run(strings.shareTrip);
      expect(h.shares, 1);
      await run(strings.settings);
      expect(h.settings, 1);
      // The toggles flip in place: the menu stays open.
      await run(strings.showTraffic);
      expect(h.platform.mapConfiguration.trafficEnabled, isTrue);
      await tester.tap(find.text(strings.satellite));
      await h.frames(tester);
      expect(h.platform.mapConfiguration.mapType, gm.MapType.hybrid);
      // Both toggles on: their switches show it.
      expect(
        [
          _toggled(tester, strings.showTraffic),
          _toggled(tester, strings.satellite),
        ],
        [true, true],
      );
      await tester.tap(find.text(strings.directions));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleStepList), findsOneWidget);
    });

    dropInTest('toggling traffic and satellite, the sound pill, the report '
        'sheet and the search keep the same map view and the follow', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      expect(h.platform.creationIds, hasLength(1));
      // The toggles flip in place; the menu is closed after them.
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      for (final label in [strings.showTraffic, strings.satellite]) {
        await tester.tap(find.text(label));
        await h.frames(tester);
      }
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump();
      await tester.tap(find.byTooltip(strings.sound));
      await h.frames(tester);
      // The report sheet, opened and dismissed with back.
      await tester.tap(find.bySemanticsLabel(strings.report));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleReportSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleReportSheet), findsNothing);
      // The search, opened and closed with its back arrow.
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      await tester.tap(find.byTooltip(strings.cancel));
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(h.platform.creationIds, hasLength(1));
      expect(h.session.follow, isTrue);
      expect(find.byType(GoogleStyleCompassButton), findsOneWidget);
    });
  });

  group('alternates (D6)', () {
    dropInTest('drawn under the route with labelled bubbles; a tap switches', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      final painted = <String>[];
      h.map.labelPainter =
          (
            text, {
            required selected,
            required pixelRatio,
            required colors,
          }) async {
            painted.add(text);
            return onePixelPng;
          };
      await h.drive(tester, routes: [sampleRoute, alt], from: 100);
      final a = h.flow.alternates.value.single;
      final m = a.minutesDelta;
      expect(
        painted,
        contains(
          m < 0
              ? strings.minFaster(-m)
              : m > 0
              ? strings.minSlower(m)
              : strings.similarEta,
        ),
      );
      final line = h.platform.polylines.singleWhere(
        (p) => p.polylineId.value == 'navigation_engine_alternate_0',
      );
      line.onTap!();
      await tester.pump();
      expect(h.session.route, same(alt));
    });
  });

  group('search along the route (D8)', () {
    const fuel = AlongRoutePlace(
      id: 'fuel',
      name: 'Fuel Stop',
      position: GeoPoint(10.776, 106.701),
      detour: Duration(minutes: 3),
    );

    dropInTest(
      'from the stack: pins, a focus that moves the camera, and a close '
      'that clears and follows',
      (tester, h) async {
        h.places = const [fuel];
        await h.mount(tester);
        await h.drive(tester);
        await tester.tap(find.byTooltip(strings.searchAlongRoute));
        await tester.pump();
        expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('google_style_search_chip_gas')),
        );
        await tester.pump();
        await tester.pump();
        final q = h.searches.single;
        expect(q.route, same(sampleRoute));
        expect(q.fromDistance, greaterThan(500));
        expect(
          h.platform.markers.map((m) => m.markerId.value),
          contains('navigation_engine_search_fuel'),
        );
        await tester.tap(find.text('Fuel Stop'));
        await h.frames(tester);
        expect(h.session.follow, isFalse);
        final move =
            h.platform.cameraMoves.last as gmp.CameraUpdateNewCameraPosition;
        expect(
          move.cameraPosition.target.latitude,
          closeTo(fuel.position.lat, 1e-9),
        );
        await tester.tap(
          find.byKey(const ValueKey('google_style_search_add_stop')),
        );
        expect(h.added, [fuel]);
        await tester.tap(find.byTooltip(strings.cancel));
        await h.frames(tester);
        expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
        expect(
          h.platform.markers.where(
            (m) => m.markerId.value.startsWith('navigation_engine_search_'),
          ),
          isEmpty,
        );
        expect(h.session.follow, isTrue);
      },
    );

    dropInTest('leaving navigation closes the search', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await tester.pump();
      h.flow.stop();
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
    });
  });

  group('landscape (D7)', () {
    for (final direction in TextDirection.values) {
      dropInTest('${direction.name}: the follow focus moves beside the panel', (
        tester,
        h,
      ) async {
        await h.mount(tester, size: const Size(915, 412), direction: direction);
        await h.drive(tester);
        await h.frames(tester);
        const overlay = 8 + 915 * 0.42 + 8;
        final padding = h.platform.mapConfiguration.padding!;
        if (direction == TextDirection.ltr) {
          expect(padding.left, closeTo(overlay, 1));
          expect(padding.right, 0);
        } else {
          expect(padding.right, closeTo(overlay, 1));
          expect(padding.left, 0);
        }
      });
    }
  });

  dropInTest('night: the drop-in passes the night tokens', (tester, h) async {
    await h.mount(tester);
    await h.drive(tester);
    expect(_cardColor(tester), GoogleStyleColors.night.guidance);
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(GoogleStyleTripSheet),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color,
      GoogleStyleColors.night.surface,
    );
  }, nightMode: NightMode.alwaysNight);

  group('carry-forwards', () {
    const fuel = AlongRoutePlace(
      id: 'fuel',
      name: 'Fuel Stop',
      position: GeoPoint(10.776, 106.701),
      detour: Duration(minutes: 3),
    );

    dropInTest('the column holds the report, the compass, search and sound', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      final stack = find.byType(GoogleStyleControlStack);
      Finder inStack(Finder f) => find.descendant(of: stack, matching: f);
      expect(inStack(find.byType(GoogleStyleCompassButton)), findsOneWidget);
      expect(inStack(find.byTooltip(strings.searchAlongRoute)), findsOneWidget);
      expect(inStack(find.byType(GoogleStyleSoundButton)), findsOneWidget);
      expect(inStack(find.byType(GoogleStyleReportButton)), findsOneWidget);
      expect(
        find
            .byType(SingleChildScrollView)
            .evaluate()
            .where(
              (e) => find
                  .ancestor(of: stack, matching: find.byWidget(e.widget))
                  .evaluate()
                  .isNotEmpty,
            ),
        isEmpty,
        reason: 'no scroll wrapper around the stack',
      );
    });

    dropInTest('a pointer-down on the map stops following; switching to an '
        'alternate follows again', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester, routes: [sampleRoute, alt], from: 100);
      expect(h.session.follow, isTrue);
      await tester.tapAt(const Offset(200, 400));
      await h.frames(tester);
      expect(h.session.follow, isFalse);
      final line = h.platform.polylines.singleWhere(
        (p) => p.polylineId.value == 'navigation_engine_alternate_0',
      );
      line.onTap!();
      await h.frames(tester);
      expect(h.session.route, same(alt));
      expect(h.session.follow, isTrue, reason: 'Google re-centres');
    });

    late _FreshReroutes reroutes;
    dropInTest('a real reroute does not turn following back on', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      h.session.follow = false;
      await h.frames(tester);
      await h.run(
        tester,
        7,
        fixAt: (s) => NavFix(
          position: offsetPoint(
            sampleRoute.pointAt(560.0 + 5 * s),
            sampleRoute.bearingAt(560) + 90,
            60,
          ),
          accuracy: 5,
          speed: 5,
          time: h.now,
        ),
      );
      final fresh = reroutes.fresh;
      expect(fresh, isNotNull, reason: 'the session rerouted');
      expect(h.flow.rerouting.value, isFalse);
      final state = h.flow.state.value as FlowNavigating;
      expect(state.route, same(fresh), reason: 'the flow took the reroute');
      expect(h.session.route, same(fresh));
      expect(h.session.follow, isFalse);
    }, provider: () => reroutes = _FreshReroutes());

    dropInTest('a tap on a search pin focuses its place', (tester, h) async {
      h.places = const [fuel];
      await h.mount(tester);
      await h.drive(tester);
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('google_style_search_chip_gas')),
      );
      await tester.pump();
      await tester.pump();
      expect(h.session.follow, isTrue);
      final pin = h.platform.markers.singleWhere(
        (m) => m.markerId.value == 'navigation_engine_search_fuel',
      );
      expect(pin.onTap, isNotNull);
      pin.onTap!();
      await h.frames(tester);
      expect(h.session.follow, isFalse);
      final move =
          h.platform.cameraMoves.last as gmp.CameraUpdateNewCameraPosition;
      expect(
        move.cameraPosition.target.latitude,
        closeTo(fuel.position.lat, 1e-9),
      );
      expect(move.cameraPosition.zoom, 16);
      expect(move.cameraPosition.bearing, 0);
      // The pin's place is selected in the list too, with Add stop (D8).
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('google_style_search_result_fuel')),
            )
            .selected,
        isTrue,
      );
      final addStop = find.byKey(
        const ValueKey('google_style_search_add_stop'),
      );
      expect(addStop, findsOneWidget);
      await tester.tap(addStop);
      expect(h.added, [fuel]);
    });

    for (final scale in [1.0, 2.0]) {
      dropInTest('${scale}x text, keyboard open: the search sits above it, '
          'without a Scaffold', (tester, h) async {
        h.places = [
          for (var i = 0; i < 8; i++)
            AlongRoutePlace(
              id: '$i',
              name: 'Place $i',
              position: const GeoPoint(10.78, 106.70),
              detour: Duration(minutes: i),
              subtitle: 'Some street',
            ),
        ];
        await h.mount(tester, size: const Size(360, 640), scale: scale);
        await h.drive(tester);
        expect(find.byType(Scaffold), findsNothing);
        // From the sheet's menu: the stack may drop the search button here.
        await tester.tap(find.byKey(_centre));
        await h.settle(tester);
        await tester.tap(find.text(strings.searchAlongRoute));
        await tester.pump();
        expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('google_style_search_chip_gas')),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Place 0'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final addStop = find.byKey(
          const ValueKey('google_style_search_add_stop'),
        );
        expect(addStop, findsOneWidget);
        expect(
          tester.getRect(addStop).bottom,
          lessThanOrEqualTo(640 - 300 + 0.5),
        );
        expect(
          find.ancestor(
            of: find.byType(GoogleStyleSearchAlongRoute),
            matching: find.byType(Material),
          ),
          findsWidgets,
        );
      });
    }

    dropInTest('the report toast needs no Scaffold', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(ScaffoldMessenger), findsOneWidget);
      await tester.tap(find.byType(GoogleStyleReportButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.byKey(const ValueKey('google_style_report_tile_crash')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('google_style_toast')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('search mode (Task 13 fix round)', () {
    const field = ValueKey('google_style_search_field');
    const gas = ValueKey('google_style_search_chip_gas');
    final stack = find.byType(GoogleStyleControlStack);
    Finder inStack(Finder f) => find.descendant(of: stack, matching: f);

    /// Opens the search from the stack, or from the sheet's menu where the
    /// stack dropped its button; then lets the stack settle under the bar
    /// (the bar's height is known after a frame, the slot's after another).
    Future<void> openSearch(WidgetTester tester, DropInHarness h) async {
      final button = inStack(find.byTooltip(strings.searchAlongRoute));
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button);
      } else {
        await tester.tap(find.byKey(_centre));
        await h.settle(tester);
        final row = find.text(strings.searchAlongRoute);
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(row);
      }
      await h.frames(tester);
      await h.frames(tester);
    }

    /// The search bar: the field's card and the chip row under it.
    Rect bar(WidgetTester tester) {
      final card = tester.getRect(
        find
            .ancestor(of: find.byKey(field), matching: find.byType(Material))
            .first,
      );
      final chips = tester.getRect(find.byKey(gas));
      return Rect.fromLTRB(card.left, card.top, card.right, chips.bottom);
    }

    dropInTest('the search takes the header\'s place and ends a step '
        'preview; the stack keeps the compass and sound, without search; '
        'closing restores them', (tester, h) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      h.flow.previewStep(h.session.guidanceState!.stepIndex + 1);
      await h.frames(tester);
      expect(h.flow.previewedStep.value, isNotNull);
      expect(find.byType(GoogleStyleManeuverHeader), findsOneWidget);

      await openSearch(tester, h);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      expect(h.flow.previewedStep.value, isNull);
      expect(h.session.follow, isTrue);
      expect(find.byType(GoogleStyleManeuverHeader), findsNothing);
      expect(find.byType(GoogleStyleLaneGuidance), findsNothing);
      expect(inStack(find.byType(GoogleStyleCompassButton)), findsOneWidget);
      expect(inStack(find.byType(GoogleStyleSoundButton)), findsOneWidget);
      expect(inStack(find.byTooltip(strings.searchAlongRoute)), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip(strings.cancel));
      await h.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(find.byType(GoogleStyleManeuverHeader), findsOneWidget);
      expect(inStack(find.byTooltip(strings.searchAlongRoute)), findsOneWidget);
      expect(inStack(find.byType(GoogleStyleCompassButton)), findsOneWidget);
    });

    for (final (size, scale, insets, direction) in const [
      (Size(412, 915), 1.0, null, TextDirection.ltr),
      (Size(360, 640), 2.0, null, TextDirection.ltr),
      (Size(915, 412), 1.0, null, TextDirection.ltr),
      (Size(844, 390), 2.0, null, TextDirection.ltr),
      (
        Size(412, 915),
        1.0,
        FakeViewPadding(top: 24, bottom: 34),
        TextDirection.ltr,
      ),
      (
        Size(915, 412),
        1.3,
        FakeViewPadding(left: 47, right: 47, bottom: 21),
        TextDirection.rtl,
      ),
    ]) {
      dropInTest('${size.width.toInt()}x${size.height.toInt()} at ${scale}x'
          '${insets == null ? '' : ' with insets'} ${direction.name}: '
          'the search bar overlaps nothing but the map', (tester, h) async {
        await h.mount(
          tester,
          size: size,
          scale: scale,
          insets: insets,
          direction: direction,
        );
        await h.drive(tester);
        // The report pill has collapsed, as it would by the time one
        // searches.
        await h.run(
          tester,
          2,
          fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
        );
        await openSearch(tester, h);
        expect(tester.takeException(), isNull);
        final b = bar(tester);
        expect(b.isEmpty, isFalse);
        final others = <String, Finder>{
          'header': find.byKey(_header),
          'stack': stack,
          'report': find.byType(GoogleStyleReportButton),
          'speed': find.byType(GoogleStyleSpeedCluster),
          'sheet': find.byType(GoogleStyleTripSheet),
          'recenter': find.byType(GoogleStyleRecenterButton),
        };
        for (final MapEntry(key: name, value: finder) in others.entries) {
          if (finder.evaluate().isEmpty) continue;
          final r = tester.getRect(finder);
          if (r.isEmpty) continue;
          expect(b.overlaps(r), isFalse, reason: 'bar $b / $name $r');
        }
      });
    }
  });

  group('side panel sheet corners (Task 13 fix round)', () {
    Material sheet(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GoogleStyleTripSheet),
            matching: find.byType(Material),
          )
          .first,
    );

    dropInTest('in the side panel the sheet is a card: four corners of 24, '
        'unclipped (its shadow shows)', (tester, h) async {
      await h.mount(tester, size: const Size(915, 412));
      await h.drive(tester);
      expect(sheet(tester).borderRadius, BorderRadius.circular(24));
      expect(
        find.ancestor(
          of: find.byType(GoogleStyleTripSheet),
          matching: find.byType(ClipRRect),
        ),
        findsNothing,
      );
    });

    Material first(WidgetTester tester, Type type) => tester.widget<Material>(
      find
          .descendant(of: find.byType(type), matching: find.byType(Material))
          .first,
    );
    Finder clipAbove(Type type) =>
        find.ancestor(of: find.byType(type), matching: find.byType(ClipRRect));

    dropInTest('in the side panel the overview panel is a card: four corners '
        'of 16, unclipped', (tester, h) async {
      await h.mount(tester, size: const Size(915, 412));
      h.flow.previewRoutes([sampleRoute, alt]);
      await h.frames(tester);
      expect(
        first(tester, GoogleStyleOverviewPanel).borderRadius,
        BorderRadius.circular(16),
      );
      expect(first(tester, GoogleStyleOverviewPanel).elevation, 8);
      expect(clipAbove(GoogleStyleOverviewPanel), findsNothing);
    });

    dropInTest('in the side panel the arrival sheet is a card: four corners '
        'of 24, unclipped', (tester, h) async {
      await h.mount(tester, size: const Size(915, 412));
      h.flow.previewRoutes([sampleRoute]);
      await tester.pump();
      h.flow.start();
      await h.run(
        tester,
        8,
        fixAt: (s) =>
            h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
      );
      expect(h.flow.state.value, isA<FlowArrived>());
      expect(
        first(tester, GoogleStyleArrivalSheet).borderRadius,
        BorderRadius.circular(24),
      );
      expect(first(tester, GoogleStyleArrivalSheet).elevation, 8);
      expect(clipAbove(GoogleStyleArrivalSheet), findsNothing);
    });

    dropInTest('in portrait both stay bottom sheets: top corners only', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(412, 915));
      h.flow.previewRoutes([sampleRoute]);
      await h.frames(tester);
      expect(
        first(tester, GoogleStyleOverviewPanel).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(16)),
      );
      h.flow.start();
      await h.run(
        tester,
        8,
        fixAt: (s) =>
            h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
      );
      expect(
        first(tester, GoogleStyleArrivalSheet).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    });

    dropInTest('in portrait it stays a bottom sheet: top corners only', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      expect(
        sheet(tester).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    });
  });
}
