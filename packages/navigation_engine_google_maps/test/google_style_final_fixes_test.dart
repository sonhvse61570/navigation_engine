import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _centre = ValueKey('google_style_trip_sheet_centre');
const _pill = ValueKey('google_style_sound_pill');
const _gas = ValueKey('google_style_search_chip_gas');
const _addStop = ValueKey('google_style_search_add_stop');
const _header = ValueKey('google_style_header_card');

const _fuel = AlongRoutePlace(
  id: 'fuel',
  name: 'Fuel Stop',
  position: GeoPoint(10.776, 106.701),
  detour: Duration(minutes: 3),
);
const _cafe = AlongRoutePlace(
  id: 'cafe',
  name: 'Corner Cafe',
  position: GeoPoint(10.777, 106.702),
);

void main() {
  const strings = NavigationStrings();
  final alt = sampleRouteAlternatives.single;

  Iterable<String> searchPins(DropInHarness h) => h.platform.markers
      .map((m) => m.markerId.value)
      .where((id) => id.startsWith('navigation_engine_search_'));

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byTooltip(strings.searchAlongRoute));
    await tester.pump();
    expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
  }

  Future<void> searchGas(WidgetTester tester) async {
    await tester.tap(find.byKey(_gas));
    await tester.pump();
    await tester.pump();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void expectStillNavigating(DropInHarness h) {
    expect(find.byType(GoogleStyleNavigation), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(h.flow.state.value, isA<FlowNavigating>());
  }

  group('I1: system back closes the open layer first', () {
    dropInTest('the search overlay', (tester, h) async {
      await h.mount(tester, pushed: true);
      await h.drive(tester);
      await openSearch(tester);
      h.session.follow = false;
      await back(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expectStillNavigating(h);
      expect(h.session.follow, isTrue, reason: 'as the overlay\'s back arrow');
    });

    dropInTest('the expanded trip sheet menu', (tester, h) async {
      await h.mount(tester, pushed: true);
      await h.drive(tester);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      final directions = find.byKey(
        ValueKey('google_style_sheet_action_${strings.directions}'),
      );
      expect(directions, findsOneWidget);
      await back(tester);
      expect(directions, findsNothing);
      expectStillNavigating(h);
    });

    dropInTest('the sound pill', (tester, h) async {
      await h.mount(tester, pushed: true);
      await h.drive(tester);
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await tester.pump();
      expect(find.byKey(_pill), findsOneWidget);
      await back(tester);
      expect(find.byKey(_pill), findsNothing);
      expectStillNavigating(h);
      expect(h.audioChanges, isEmpty);
    });

    dropInTest('one layer per back: the pill, then the search', (
      tester,
      h,
    ) async {
      await h.mount(tester, pushed: true);
      await h.drive(tester);
      await openSearch(tester);
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await tester.pump();
      expect(find.byKey(_pill), findsOneWidget);
      await back(tester);
      expect(find.byKey(_pill), findsNothing);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      await back(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expectStillNavigating(h);
    });

    dropInTest('with nothing open, back leaves the screen as before', (
      tester,
      h,
    ) async {
      await h.mount(tester, pushed: true);
      await h.drive(tester);
      await back(tester);
      expect(find.byType(GoogleStyleNavigation), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('M1: the Google logo stays visible', () {
    dropInTest('portrait: the map padding lifts it above the trip sheet and '
        'the speed, and keeps the follow focus', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await h.frames(tester);
      final padding = h.platform.mapConfiguration.padding!;
      final sheet = tester.getRect(find.byType(GoogleStyleTripSheet));
      final speed = tester.getRect(find.byType(GoogleStyleSpeedCluster));
      expect(padding.bottom, greaterThanOrEqualTo(800 - sheet.top - 0.5));
      expect(padding.bottom, greaterThanOrEqualTo(800 - speed.top - 0.5));
      // The SDK centres the camera in the padded view: still at 0.7.
      expect(padding.top - padding.bottom, closeTo(0.4 * 800, 0.5));
    });

    dropInTest('landscape: above the speed cluster, then the Re-center pill, '
        'in the map area', (tester, h) async {
      await h.mount(tester, size: const Size(915, 412));
      await h.drive(tester);
      await h.frames(tester);
      var padding = h.platform.mapConfiguration.padding!;
      final speed = tester.getRect(find.byType(GoogleStyleSpeedCluster));
      expect(padding.bottom, greaterThanOrEqualTo(412 - speed.top - 0.5));
      expect(padding.top - padding.bottom, closeTo(0.4 * 412, 0.5));
      expect(padding.left, closeTo(8 + 915 * 0.42 + 8, 1));
      h.session.follow = false;
      await h.frames(tester);
      await h.frames(tester);
      padding = h.platform.mapConfiguration.padding!;
      final recenter = tester.getRect(find.byType(GoogleStyleRecenterButton));
      expect(padding.bottom, greaterThanOrEqualTo(412 - recenter.top - 0.5));
      expect(padding.top - padding.bottom, closeTo(0.4 * 412, 0.5));
    });
  });

  dropInTest('Add stop closes the search and follows again', (tester, h) async {
    h.places = const [_fuel];
    await h.mount(tester);
    await h.drive(tester);
    await openSearch(tester);
    await searchGas(tester);
    await tester.tap(find.text('Fuel Stop'));
    await h.frames(tester);
    expect(h.session.follow, isFalse);
    await tester.tap(find.byKey(_addStop));
    await h.frames(tester);
    expect(h.added, [_fuel]);
    expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
    expect(searchPins(h), isEmpty);
    expect(h.session.follow, isTrue);
    expect(find.byKey(_header), findsOneWidget, reason: 'guidance is back');
  });

  group('M3 / T10: changes while the search is open', () {
    dropInTest('night: the overlay and the shown pins take the night '
        'colours', (tester, h) async {
      h.places = const [_fuel];
      await h.mount(tester);
      final pinColors = <Color>[];
      h.map.pinPainter =
          ({required focused, required pixelRatio, required color}) async {
            pinColors.add(color);
            return onePixelPng;
          };
      await h.drive(tester);
      await openSearch(tester);
      await searchGas(tester);
      expect(searchPins(h), ['navigation_engine_search_fuel']);
      expect(pinColors.toSet(), {GoogleStyleColors.day.warning});
      h.flow.nightMode = NightMode.alwaysNight;
      await h.frames(tester);
      await h.frames(tester);
      final overlay = tester.widget<GoogleStyleSearchAlongRoute>(
        find.byType(GoogleStyleSearchAlongRoute),
      );
      expect(overlay.colors, GoogleStyleColors.night);
      expect(pinColors.last, GoogleStyleColors.night.warning);
      expect(searchPins(h), ['navigation_engine_search_fuel']);
    });

    dropInTest('language: the overlay and the shown bubbles take the new '
        'words', (tester, h) async {
      await h.mount(tester);
      final labels = <String>[];
      h.map.labelPainter =
          (text, {required selected, required pixelRatio, required colors}) {
            labels.add(text);
            return Future.value(onePixelPng);
          };
      await h.drive(tester, routes: [sampleRoute, alt], from: 100);
      await h.frames(tester);
      final shown = h.flow.alternates.value.single;
      String label(NavigationStrings s) {
        final m = shown.minutesDelta;
        return m < 0
            ? s.minFaster(-m)
            : m > 0
            ? s.minSlower(m)
            : s.similarEta;
      }

      expect(labels, contains(label(strings)));
      await openSearch(tester);
      const vi = NavigationStrings.vietnamese();
      await tester.pumpWidget(h.app(strings: vi));
      await h.frames(tester);
      expect(find.text(vi.searchHint), findsOneWidget);
      expect(labels.last, label(vi));
      expect(
        h.platform.markers.map((m) => m.markerId.value),
        contains('navigation_engine_alternate_label_0'),
      );
    });
  });

  late _FreshReroutes reroutes;
  dropInTest('T12-5: a reroute while results show clears them and searches '
      'again along the new route', (tester, h) async {
    h.places = const [_fuel];
    await h.mount(tester);
    await h.drive(tester);
    await openSearch(tester);
    await searchGas(tester);
    expect(searchPins(h), ['navigation_engine_search_fuel']);
    h.places = const [_cafe];
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
    expect((h.flow.state.value as FlowNavigating).route, same(fresh));
    expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
    expect(h.searches, hasLength(2));
    expect(h.searches.last.route, same(fresh));
    expect(h.searches.last.category, AlongRouteCategory.gas);
    expect(searchPins(h), ['navigation_engine_search_cafe']);
    expect(find.text('Fuel Stop'), findsNothing);
    expect(find.text('Corner Cafe'), findsOneWidget);
  }, provider: () => reroutes = _FreshReroutes());

  group('T12-6: the report sheet ends with navigation', () {
    Future<void> openReport(WidgetTester tester) async {
      await tester.tap(find.byType(GoogleStyleReportButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleReportSheet), findsOneWidget);
    }

    dropInTest('stop closes it; nothing is reported', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      await openReport(tester);
      h.flow.stop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleReportSheet), findsNothing);
      expect(h.reports, isEmpty);
      expect(find.byKey(const ValueKey('google_style_toast')), findsNothing);
    });

    dropInTest('arrival closes it', (tester, h) async {
      await h.mount(tester);
      h.flow.previewRoutes([sampleRoute]);
      await tester.pump();
      h.flow.start();
      await tester.pump();
      await h.run(
        tester,
        1,
        fixAt: (s) =>
            h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
      );
      expect(h.flow.state.value, isA<FlowNavigating>());
      await openReport(tester);
      await h.run(
        tester,
        8,
        fixAt: (s) =>
            h.fixOn(sampleRoute, sampleRoute.length - 32 + 8.0 * s, speed: 8),
      );
      expect(h.flow.state.value, isA<FlowArrived>());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GoogleStyleReportSheet), findsNothing);
      expect(h.reports, isEmpty);
    });
  });

  dropInTest('T13-7: at 915x412 the open menu shows at least 4 rows, the '
      'header hidden meanwhile', (tester, h) async {
    await h.mount(tester, size: const Size(915, 412));
    await h.drive(tester);
    expect(find.byKey(_header), findsOneWidget);
    await tester.tap(find.byKey(_centre));
    await h.settle(tester);
    await h.frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_header), findsNothing);
    final viewport = tester.getRect(
      find
          .ancestor(
            of: find.byType(GoogleStyleTripSheet),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'google_style_sheet_action_',
          ),
    );
    final visible = rows.evaluate().where((e) {
      final r = tester.getRect(find.byWidget(e.widget));
      return r.top >= viewport.top - 0.5 && r.bottom <= viewport.bottom + 0.5;
    });
    expect(visible.length, greaterThanOrEqualTo(4));
    // Closed again, the header comes back.
    await tester.tap(find.byKey(_centre));
    await h.settle(tester);
    await h.frames(tester);
    expect(find.byKey(_header), findsOneWidget);
  });
}
