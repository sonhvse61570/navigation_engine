import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart' show onePixelPng;
import 'support/fake_google_maps_platform.dart';

class _Fixes implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  bool _running = false;
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void dispose() {}
}

const _place = AlongRoutePlace(
  id: 'a',
  name: 'Fuel',
  position: GeoPoint(10.78, 106.70),
);

/// A route 3 km north and a detour that leaves it at 1 km, runs 300 m to
/// the east of it and comes back at 2 km.
(NavRoute, NavRoute) _sharedRoutes() {
  const origin = GeoPoint(10.77, 106.70);
  List<GeoPoint> straight(GeoPoint from, double bearing, double length) => [
    for (var d = 0.0; d <= length + 1e-6; d += 50)
      offsetPoint(from, bearing, d),
  ];
  final turnOff = offsetPoint(origin, 0, 1000);
  final east = offsetPoint(turnOff, 90, 300);
  final north = offsetPoint(east, 0, 1000);
  final back = offsetPoint(origin, 0, 2000);
  return (
    NavRoute.fromPoints(straight(origin, 0, 3000)),
    NavRoute.fromPoints([
      ...straight(origin, 0, 1000),
      ...straight(turnOff, 90, 300).skip(1),
      ...straight(east, 0, 1000).skip(1),
      ...straight(north, 270, 300).skip(1).take(5),
      ...straight(back, 0, 1000),
    ]),
  );
}

/// A tap at [p] as the SDK hit-tests it: the tappable polyline of the last
/// build that passes within 10 m of [p] takes it (the top one first),
/// else the map does.
void _tapAt(FakeGoogleMapsPlatform platform, GeoPoint p) {
  final lines = platform.polylines.where((l) => l.consumeTapEvents).toList()
    ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
  for (final line in lines) {
    if (line.points.length < 2) continue;
    final path = NavRoute.fromPoints([
      for (final q in line.points) GeoPoint(q.latitude, q.longitude),
    ]);
    if (path.snap(p).offset < 10) {
      platform.tapPolyline(line.polylineId.value);
      return;
    }
  }
  platform.tapMap(gm.LatLng(p.lat, p.lng));
}

void main() {
  late FakeGoogleMapsPlatform platform;
  late NavigationSession session;

  setUp(() {
    platform = FakeGoogleMapsPlatform();
    installFakeGoogleMapsPlatform(platform);
    session = NavigationSession(fixes: _Fixes());
  });

  /// Mounts [view], creates the native view and lets the controller
  /// connect its event streams.
  Future<GoogleMapsNavigationMap> mount(
    WidgetTester tester,
    Widget view,
  ) async {
    await tester.pumpWidget(MaterialApp(home: view));
    platform.createView();
    await tester.pump();
    return session.map! as GoogleMapsNavigationMap;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }

  GoogleMapsNavigationView view({
    void Function(GeoPoint point)? onMapTap,
    void Function(GeoPoint point)? onMapLongPress,
    void Function(int index)? onRouteOptionTap,
    RouteLabelColors? labelColors,
    Color? alternateColor,
    RouteLabelColors? fasterLabelColors,
    RouteLabelColors? slowerLabelColors,
    Color? searchPinColor,
  }) => GoogleMapsNavigationView(
    session: session,
    initialCenter: sampleRoute.points.first,
    onMapTap: onMapTap,
    onMapLongPress: onMapLongPress,
    onRouteOptionTap: onRouteOptionTap,
    routeLabel: (r) => 'label',
    alternateLabel: (a) => 'alt',
    labelColors: labelColors,
    alternateColor: alternateColor,
    fasterLabelColors: fasterLabelColors,
    slowerLabelColors: slowerLabelColors,
    searchPinColor: searchPinColor,
  );

  /// Makes every painter of [map] answer at once with a 1x1 PNG.
  void quickPainters(GoogleMapsNavigationMap map) {
    map
      ..labelPainter = ((
        text, {
        required selected,
        required pixelRatio,
        required colors,
      }) => Future.value(onePixelPng))
      ..pinPainter = (({
        required focused,
        required pixelRatio,
        required color,
      }) => Future.value(onePixelPng))
      ..destinationPinPainter = (({required pixelRatio}) =>
          Future.value(onePixelPng));
  }

  test('a bubble lies on the drawn line: on a short detour, at the middle '
      'of the part that differs (alternateLabelDistance)', () async {
    final map = GoogleMapsNavigationMap();
    addTearDown(map.dispose);
    quickPainters(map);
    map.alternateLabel = (a) => 'x';
    final (_, detour) = _sharedRoutes();
    final short = AlternateRoute(
      route: detour,
      timeDelta: Duration.zero,
      divergence: 1040,
      rejoin: (alternate: 1240, current: 1000),
    );
    map.showAlternates([short], onTap: (_) {});
    await pumpEventQueue();
    final at = map.alternateMarkers.value.single.position;
    final mid = detour.pointAt(1140);
    expect(at.latitude, closeTo(mid.lat, 1e-9));
    expect(at.longitude, closeTo(mid.lng, 1e-9));
  });

  group('map taps and long presses', () {
    testWidgets('reach onMapTap and onMapLongPress as GeoPoints', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      await mount(
        tester,
        view(onMapTap: taps.add, onMapLongPress: presses.add),
      );
      platform.tapMap(const gm.LatLng(10.5, 106.25));
      platform.longPressMap(const gm.LatLng(-33.75, 151.125));
      // A long press at once; a tap after one turn of the event loop (a
      // zero-duration pump), in case a feature tap of the same gesture
      // follows it.
      expect(presses, [const GeoPoint(-33.75, 151.125)]);
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(10.5, 106.25)]);
      await unmount(tester);
    });

    testWidgets('without the callbacks a tap and a long press do nothing', (
      tester,
    ) async {
      await mount(tester, view());
      platform
        ..tapMap(const gm.LatLng(10, 106))
        ..longPressMap(const gm.LatLng(10, 106));
      await tester.pump(Duration.zero);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    /// Mounts a view whose map shows every feature it owns: route options
    /// with bubbles, an alternate with its bubble, a search pin and the
    /// destination pin.
    Future<GoogleMapsNavigationMap> mountFeatures(
      WidgetTester tester, {
      required void Function(GeoPoint) onMapTap,
      void Function(GeoPoint)? onMapLongPress,
      void Function(int index)? onRouteOptionTap,
    }) async {
      final map = await mount(
        tester,
        view(
          onMapTap: onMapTap,
          onMapLongPress: onMapLongPress,
          onRouteOptionTap: onRouteOptionTap,
        ),
      );
      quickPainters(map);
      final alt = sampleRouteAlternatives.single;
      map
        ..showRouteOptions([sampleRoute, alt], 0)
        ..showAlternates([
          AlternateRoute(
            route: alt,
            timeDelta: const Duration(minutes: -2),
            divergence: 300,
          ),
        ], onTap: (_) {})
        ..showDestinationPin(sampleRoute.points.last);
      await map.showSearchPins(const [_place]);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      final ids = platform.markers.map((m) => m.markerId.value).toSet();
      expect(
        ids,
        containsAll(<String>[
          'navigation_engine_option_label_1',
          'navigation_engine_alternate_label_0',
          'navigation_engine_search_a',
          'navigation_engine_destination',
        ]),
      );
      return map;
    }

    const at = gm.LatLng(10.77, 106.70);
    const atPoint = GeoPoint(10.77, 106.70);

    testWidgets('the map tap of a feature tap\'s gesture does not reach '
        'onMapTap, in either order; a long press always does', (tester) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      final options = <int>[];
      await mountFeatures(
        tester,
        onMapTap: taps.add,
        onMapLongPress: presses.add,
        onRouteOptionTap: options.add,
      );
      // The SDK's side of each feature tap, and a map tap for the same
      // gesture (a platform that reports both).
      final features = <void Function()>[
        () => platform.tapPolyline('navigation_engine_option_1'),
        () => platform.tapPolyline('navigation_engine_option_casing_0'),
        () => platform.tapMarker('navigation_engine_option_label_1'),
        () => platform.tapPolyline('navigation_engine_alternate_0'),
        () => platform.tapMarker('navigation_engine_alternate_label_0'),
        () => platform.tapMarker('navigation_engine_search_a'),
        () => platform.tapMarker('navigation_engine_destination'),
      ];
      for (final (i, feature) in features.indexed) {
        // The feature tap first.
        feature();
        platform.tapMap(at);
        platform.longPressMap(at);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty, reason: 'feature $i, then the map');
        expect(presses, hasLength(2 * i + 1), reason: 'feature $i');
        // The map tap first, the feature tap in the same turn.
        platform.tapMap(at);
        feature();
        platform.longPressMap(at);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty, reason: 'the map, then feature $i');
        expect(presses, hasLength(2 * i + 2), reason: 'feature $i');
      }
      expect(options, [1, 1, 0, 0, 1, 1]);
      await unmount(tester);
    });

    testWidgets('a feature tap drops one map tap only, and only in its own '
        'frame: a map tap in a later frame is delivered', (tester) async {
      final taps = <GeoPoint>[];
      await mountFeatures(tester, onMapTap: taps.add);
      platform.tapMarker('navigation_engine_destination');
      platform.tapMap(at);
      // A second map tap in the same frame is another gesture.
      platform.tapMap(const gm.LatLng(10.5, 106.5));
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(10.5, 106.5)]);

      // A feature tap, a frame, then a map tap: the map's own.
      taps.clear();
      platform.tapMarker('navigation_engine_search_a');
      await tester.pump(Duration.zero);
      platform.tapMap(at);
      await tester.pump(Duration.zero);
      expect(taps, [atPoint]);
      await unmount(tester);
    });

    testWidgets('a map tap that a feature tap follows in the same turn is '
        'dropped', (tester) async {
      final taps = <GeoPoint>[];
      final options = <int>[];
      await mountFeatures(
        tester,
        onMapTap: taps.add,
        onRouteOptionTap: options.add,
      );
      platform.tapMap(at);
      platform.tapPolyline('navigation_engine_option_1');
      await tester.pump(Duration.zero);
      expect(options, [1]);
      expect(taps, isEmpty);
      // The token was spent on that map tap: the next one is delivered.
      platform.tapMap(at);
      await tester.pump(Duration.zero);
      expect(taps, [atPoint]);
      await unmount(tester);
    });

    testWidgets('a tap on the route where an alternate shares it is a map '
        'tap; a tap on the alternate\'s own part selects it', (tester) async {
      final taps = <GeoPoint>[];
      final selected = <int>[];
      final map = await mount(tester, view(onMapTap: taps.add));
      final (main, detour) = _sharedRoutes();
      map
        ..showRoute(const [], main.points)
        ..showAlternates([
          AlternateRoute(
            route: detour,
            timeDelta: const Duration(minutes: -1),
            divergence: 1040,
            rejoin: (alternate: detour.length - 1040, current: 2000),
          ),
        ], onTap: selected.add);
      await tester.pump();
      // The shared start and the shared end, then the detour itself.
      for (final p in [main.pointAt(500), main.pointAt(2600)]) {
        _tapAt(platform, p);
        await tester.pump(Duration.zero);
      }
      expect(selected, isEmpty);
      expect(taps, hasLength(2));
      _tapAt(platform, detour.pointAt(1800));
      await tester.pump(Duration.zero);
      expect(selected, [0]);
      expect(taps, hasLength(2));
      await unmount(tester);
    });

    testWidgets('a tap on the vehicle is a map tap at the vehicle, as on the '
        'other adapters (the SDK does not take it as a marker click)', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      final map = await mount(tester, view(onMapTap: taps.add));
      const car = GeoPoint(10.775, 106.701);
      map.showVehicle(car, 30);
      await tester.pump();
      final vehicle = platform.markers.singleWhere(
        (m) => m.markerId.value == 'navigation_engine_vehicle',
      );
      expect(vehicle.consumeTapEvents, isTrue);
      platform.tapMarker('navigation_engine_vehicle');
      expect(taps, isEmpty, reason: 'one turn later, as any map tap');
      await tester.pump(Duration.zero);
      expect(taps, [car]);
      await unmount(tester);
    });

    testWidgets('without onMapTap a tap on the vehicle does nothing', (
      tester,
    ) async {
      final map = await mount(tester, view());
      map.showVehicle(const GeoPoint(10.775, 106.701), 0);
      await tester.pump();
      platform.tapMarker('navigation_engine_vehicle');
      await tester.pump(Duration.zero);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('a map tap still held when the view goes is dropped', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      await mount(tester, view(onMapTap: taps.add));
      platform.tapMap(at);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      expect(taps, isEmpty);
      expect(tester.takeException(), isNull);
      session.dispose();
    });

    testWidgets('GoogleStyleNavigation forwards both callbacks', (
      tester,
    ) async {
      final flow = NavigationFlowController(
        session: session,
        nightMode: NightMode.alwaysDay,
      );
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      await mount(
        tester,
        GoogleStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: sampleRoute.points.first,
          onMapTap: taps.add,
          onMapLongPress: presses.add,
        ),
      );
      platform
        ..tapMap(const gm.LatLng(10.1, 106.1))
        ..longPressMap(const gm.LatLng(10.2, 106.2));
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(10.1, 106.1)]);
      expect(presses, [const GeoPoint(10.2, 106.2)]);
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      session.dispose();
    });
  });

  group('the destination pin', () {
    testWidgets('is a marker at the point, anchored at its tip; null '
        'removes it', (tester) async {
      final map = await mount(tester, view());
      expect(map, isA<DestinationPinMap>());
      final ratios = <double>[];
      map.destinationPinPainter = ({required pixelRatio}) {
        ratios.add(pixelRatio);
        return Future.value(onePixelPng);
      };
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await tester.pump();
      gm.Marker? pin() => platform.markers
          .where((m) => m.markerId.value == 'navigation_engine_destination')
          .firstOrNull;
      expect(pin()!.position, const gm.LatLng(10.8, 106.7));
      expect(pin()!.anchor, const Offset(0.5, 1));
      expect(pin()!.zIndexInt, lessThan(10), reason: 'under the vehicle');
      expect(ratios, [map.labelPixelRatio]);

      // A move keeps one pin.
      map.showDestinationPin(const GeoPoint(10.9, 106.8));
      await tester.pump();
      expect(pin()!.position, const gm.LatLng(10.9, 106.8));
      expect(
        platform.markers.where(
          (m) => m.markerId.value == 'navigation_engine_destination',
        ),
        hasLength(1),
      );

      map.showDestinationPin(null);
      await tester.pump();
      expect(pin(), isNull);
      await unmount(tester);
    });

    testWidgets('a newer call drops a render still pending', (tester) async {
      final map = await mount(tester, view());
      final first = Completer<Uint8List>();
      var calls = 0;
      map.destinationPinPainter = ({required pixelRatio}) =>
          calls++ == 0 ? first.future : Future.value(onePixelPng);
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      map.showDestinationPin(null);
      first.complete(onePixelPng);
      await tester.pump();
      expect(map.destinationMarker.value, isNull);
      await unmount(tester);
    });

    testWidgets('a render that ends after the map is disposed is dropped', (
      tester,
    ) async {
      final map = await mount(tester, view());
      final pending = Completer<Uint8List>();
      map.destinationPinPainter = ({required pixelRatio}) => pending.future;
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await tester.pumpWidget(const SizedBox());
      pending.complete(onePixelPng);
      await tester.pump();
      expect(tester.takeException(), isNull);
      session.dispose();
    });

    testWidgets('a failed render removes the pin and is reported; the next '
        'call paints again', (tester) async {
      final map = await mount(tester, view());
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      var fail = true;
      map.destinationPinPainter = ({required pixelRatio}) => fail
          ? Future<Uint8List>.error(StateError('paint'))
          : Future.value(onePixelPng);
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await tester.pump();
      FlutterError.onError = previous;
      expect(map.destinationMarker.value, isNull);
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'navigation_engine_google_maps');
      fail = false;
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await tester.pump();
      expect(map.destinationMarker.value, isNotNull);
      await unmount(tester);
    });

    testWidgets('by default it is the shared paintDestinationPin', (
      tester,
    ) async {
      final map = await mount(tester, view());
      map.labelPixelRatio = 2;
      // The render runs outside the fake clock: the map's starts first, and
      // the engine renders in order, so it is done once the test's own one
      // is (then its marker is set within a few turns of the event loop).
      final expected = (await tester.runAsync(() async {
        map.showDestinationPin(const GeoPoint(10.8, 106.7));
        final png = await paintDestinationPin(pixelRatio: 2);
        for (var i = 0; i < 100 && map.destinationMarker.value == null; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        return png;
      }))!;
      await tester.pump();
      final shown = map.destinationMarker.value!;
      final icon = shown.icon as gm.BytesMapBitmap;
      expect(icon.byteData, expected);
      expect(icon.imagePixelRatio, 2);
      await unmount(tester);
    });

    testWidgets('GoogleStyleNavigation pins the selected route\'s end in the '
        'overview and clears it when idle', (tester) async {
      final flow = NavigationFlowController(
        session: session,
        nightMode: NightMode.alwaysDay,
      );
      final map = await mount(
        tester,
        GoogleStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: sampleRoute.points.first,
        ),
      );
      quickPainters(map);
      flow.previewRoutes([sampleRoute]);
      await tester.pump();
      await tester.pump();
      final pin = platform.markers.singleWhere(
        (m) => m.markerId.value == 'navigation_engine_destination',
      );
      final end = sampleRoute.points.last;
      expect(pin.position, gm.LatLng(end.lat, end.lng));
      flow.closeOverview();
      await tester.pump();
      expect(
        platform.markers.map((m) => m.markerId.value),
        isNot(contains('navigation_engine_destination')),
      );
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      session.dispose();
    });
  });

  group('the look of the labels, alternates and pins', () {
    testWidgets('labelColors takes RouteLabelColors; the alternate and pin '
        'colours have their own parameters; null keeps the map\'s', (
      tester,
    ) async {
      const mine = RouteLabelColors(selectedFill: Color(0xFF00FF00));
      const faster = RouteLabelColors(fill: Color(0xFF010101));
      const slower = RouteLabelColors(fill: Color(0xFF020202));
      final map = await mount(tester, view());
      final day = GoogleStyleColors.day;
      // Unset, the shared defaults of every adapter.
      expect(map.labelColors, MapDefaultColors.routeLabels);
      expect(map.alternateColor, MapDefaultColors.alternate);
      expect(map.fasterLabelColors, MapDefaultColors.fasterLabels);
      expect(map.slowerLabelColors, MapDefaultColors.slowerLabels);
      expect(map.pinColor, MapDefaultColors.searchPin);

      await tester.pumpWidget(
        MaterialApp(
          home: view(
            labelColors: mine,
            alternateColor: const Color(0xFF123456),
            fasterLabelColors: faster,
            slowerLabelColors: slower,
            searchPinColor: const Color(0xFF654321),
          ),
        ),
      );
      expect(map.labelColors, mine);
      expect(map.alternateColor, const Color(0xFF123456));
      expect(map.fasterLabelColors, faster);
      expect(map.slowerLabelColors, slower);
      expect(map.pinColor, const Color(0xFF654321));

      // One bubble colour alone keeps the other one.
      await tester.pumpWidget(
        MaterialApp(home: view(fasterLabelColors: day.fasterLabelColors)),
      );
      expect(map.fasterLabelColors, day.fasterLabelColors);
      expect(map.slowerLabelColors, slower);

      await tester.pumpWidget(MaterialApp(home: view()));
      expect(map.labelColors, mine);
      expect(map.alternateColor, const Color(0xFF123456));
      expect(map.pinColor, const Color(0xFF654321));
      await unmount(tester);
    });

    testWidgets('a Mapbox-style look on Google: the Mapbox colours\' '
        'routeLabelColors', (tester) async {
      final map = await mount(
        tester,
        view(labelColors: MapboxStyleColors.night.routeLabelColors),
      );
      expect(map.labelColors, MapboxStyleColors.night.routeLabelColors);
      await unmount(tester);
    });

    testWidgets('GoogleStyleNavigation keeps the Google-style colours at '
        'night', (tester) async {
      final flow = NavigationFlowController(
        session: session,
        nightMode: NightMode.alwaysNight,
      );
      final map = await mount(
        tester,
        GoogleStyleNavigation(
          session: session,
          flow: flow,
          initialCenter: sampleRoute.points.first,
        ),
      );
      final night = GoogleStyleColors.night;
      expect(map.labelColors, night.routeLabelColors);
      expect(map.alternateColor, night.alternative);
      expect(map.alternativeColor, night.alternative);
      expect(map.fasterLabelColors, night.fasterLabelColors);
      expect(map.slowerLabelColors, night.slowerLabelColors);
      expect(map.pinColor, night.warning);
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      session.dispose();
    });
  });
}
