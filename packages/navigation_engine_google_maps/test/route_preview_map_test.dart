// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';
import 'package:navigation_engine_google_maps/src/google_maps_navigation_map.dart'
    show toCameraPosition;

import 'support/fake_google_maps_platform.dart';

const _viewport = Size(400, 800);
const _padding = EdgeInsets.fromLTRB(10, 20, 30, 300);
const _alternative = Color(0xFF9AA0A6);

List<GeoPoint> _allPoints(List<NavRoute> routes) => [
  for (final r in routes) ...r.points,
];

/// The camera the update asks for; fails for any other kind of update.
gm.CameraPosition _positionOf(gmp.CameraUpdate update) =>
    (update as gmp.CameraUpdateNewCameraPosition).cameraPosition;

gm.CameraPosition _expected(List<NavRoute> routes) => toCameraPosition(
  fitCameraToBounds(_allPoints(routes), _viewport, _padding),
);

void _expectSame(gm.CameraPosition actual, gm.CameraPosition expected) {
  expect(actual.target.latitude, closeTo(expected.target.latitude, 1e-9));
  expect(actual.target.longitude, closeTo(expected.target.longitude, 1e-9));
  expect(actual.zoom, closeTo(expected.zoom, 1e-9));
  expect(actual.bearing, 0);
  expect(actual.tilt, 0);
}

void main() {
  late FakeGoogleMapsPlatform platform;
  late GoogleMapsNavigationMap map;
  final routes = [sampleRoute, sampleRouteAlternatives.single];

  setUp(() {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    map = GoogleMapsNavigationMap();
  });

  gm.GoogleMapController? lastController;

  /// Shows a [gm.GoogleMap] wired to [target] and creates its native view.
  Future<void> mountMap(
    WidgetTester tester, [
    GoogleMapsNavigationMap? target,
  ]) async {
    await tester.pumpWidget(
      MaterialApp(
        home: gm.GoogleMap(
          key: UniqueKey(),
          initialCameraPosition: const gm.CameraPosition(
            target: gm.LatLng(0, 0),
          ),
          onMapCreated: (c) {
            lastController = c;
            (target ?? map).onMapCreated(c);
          },
        ),
      ),
    );
    platform.createView();
    await tester.pump();
  }

  gm.Polyline option(String id) => map.routeOptionPolylines.value.singleWhere(
    (p) => p.polylineId.value == id,
  );

  test('showRouteOptions draws casing and line per route, selected on top', () {
    addTearDown(map.dispose);
    map.showRouteOptions(routes, 1);

    final all = map.routeOptionPolylines.value;
    expect(all.map((p) => p.polylineId.value).toSet(), {
      'navigation_engine_option_0',
      'navigation_engine_option_1',
      'navigation_engine_option_casing_0',
      'navigation_engine_option_casing_1',
    });
    expect(all, hasLength(4));

    final selected = option('navigation_engine_option_1');
    final other = option('navigation_engine_option_0');
    final selectedCasing = option('navigation_engine_option_casing_1');
    final otherCasing = option('navigation_engine_option_casing_0');
    final colors = const RouteColors();

    expect(selected.color, colors.ahead);
    expect(selected.width, colors.aheadWidth.round());
    expect(selected.zIndex, 6);
    expect(selectedCasing.color, Color.lerp(colors.ahead, Colors.black, 0.35));
    expect(selectedCasing.width, selected.width + 4);
    expect(selectedCasing.zIndex, 5);

    expect(other.color, _alternative);
    expect(other.width, colors.aheadWidth.round());
    expect(other.zIndex, 4);
    expect(otherCasing.color, Color.lerp(_alternative, Colors.white, 0.5));
    expect(otherCasing.width, other.width + 4);
    expect(otherCasing.zIndex, 3);

    expect(all.every((p) => p.consumeTapEvents), isTrue);
    expect(
      selected.points,
      hasLength(sampleRouteAlternatives.single.points.length),
    );
  });

  test('tapping an option polyline reports its index', () {
    addTearDown(map.dispose);
    final taps = <int>[];
    map.onRouteOptionTap = taps.add;
    map.showRouteOptions(routes, 1);

    option('navigation_engine_option_0').onTap!();
    option('navigation_engine_option_casing_1').onTap!();

    expect(taps, [0, 1]);
  });

  test('clearRouteOptions removes them', () {
    addTearDown(map.dispose);
    map.showRouteOptions(routes, 0);
    expect(map.routeOptionPolylines.value, isNotEmpty);
    map.clearRouteOptions();
    expect(map.routeOptionPolylines.value, isEmpty);
  });

  testWidgets('fitRoutes animates to the fitted camera', (tester) async {
    addTearDown(map.dispose);
    await mountMap(tester);
    map.viewportSize = _viewport;

    await map.fitRoutes(routes, _padding);

    expect(platform.cameraAnimations, hasLength(1));
    expect(platform.cameraMoves, isEmpty);
    _expectSame(
      _positionOf(platform.cameraAnimations.single),
      _expected(routes),
    );
  });

  testWidgets('fitRoutes accounts for the map padding', (tester) async {
    addTearDown(map.dispose);
    await mountMap(tester);
    map.mapPadding = const EdgeInsets.only(top: 320);
    map.viewportSize = _viewport;

    await map.fitRoutes(routes, _padding);

    _expectSame(
      _positionOf(platform.cameraAnimations.single),
      toCameraPosition(
        fitCameraToBounds(
          _allPoints(routes),
          _viewport,
          _padding,
          mapPadding: const EdgeInsets.only(top: 320),
        ),
      ),
    );
  });

  testWidgets('a pending fit uses the map padding set meanwhile', (
    tester,
  ) async {
    addTearDown(map.dispose);
    await map.fitRoutes(routes, _padding);
    map.mapPadding = const EdgeInsets.only(top: 320);
    map.viewportSize = _viewport;
    await mountMap(tester);
    _expectSame(
      _positionOf(platform.cameraMoves.single),
      toCameraPosition(
        fitCameraToBounds(
          _allPoints(routes),
          _viewport,
          _padding,
          mapPadding: const EdgeInsets.only(top: 320),
        ),
      ),
    );
  });

  testWidgets('camera errors of a fit are reported, not thrown', (
    tester,
  ) async {
    addTearDown(map.dispose);
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    // The test framework's own reports go on to the previous handler: it
    // fails the test. Collecting them here would leave it hanging.
    FlutterError.onError = (details) =>
        details.library == 'Flutter test framework'
        ? old?.call(details)
        : errors.add(details);
    addTearDown(() => FlutterError.onError = old);
    platform.cameraError = StateError('no map');

    // A pending fit: moveCamera fails.
    await map.fitRoutes(routes, _padding);
    map.viewportSize = _viewport;
    await mountMap(tester);
    expect(errors, hasLength(1));

    // A direct fit: animateCamera fails.
    await map.fitRoutes(routes, _padding);
    await tester.pump();
    expect(errors, hasLength(2));
    expect(errors.map((e) => e.exception), everyElement(isA<StateError>()));
    expect(errors.first.library, 'navigation_engine_google_maps');
  });

  testWidgets('a fit before the map is ready is applied later', (tester) async {
    addTearDown(map.dispose);
    await map.fitRoutes(routes, _padding);
    expect(platform.cameraMoves, isEmpty);
    expect(platform.cameraAnimations, isEmpty);

    map.viewportSize = _viewport;
    expect(platform.cameraMoves, isEmpty);
    expect(platform.cameraAnimations, isEmpty);

    await mountMap(tester);
    expect(platform.cameraMoves, hasLength(1));
    expect(platform.cameraAnimations, isEmpty);
    _expectSame(_positionOf(platform.cameraMoves.single), _expected(routes));

    // A second onMapCreated does not re-apply the fit.
    map.onMapCreated(lastController!);
    await tester.pump();
    expect(platform.cameraMoves, hasLength(1));
  });

  testWidgets('a fit waits for the viewport size when the map is ready first', (
    tester,
  ) async {
    addTearDown(map.dispose);
    await mountMap(tester);
    await map.fitRoutes(routes, _padding);
    expect(platform.cameraMoves, isEmpty);
    expect(platform.cameraAnimations, isEmpty);

    map.viewportSize = _viewport;
    expect(platform.cameraMoves, hasLength(1));
    _expectSame(_positionOf(platform.cameraMoves.single), _expected(routes));

    map.viewportSize = const Size(500, 900);
    expect(platform.cameraMoves, hasLength(1), reason: 'applied once');
  });

  testWidgets('a newer fit replaces a pending one; clear drops it', (
    tester,
  ) async {
    addTearDown(map.dispose);
    await map.fitRoutes([sampleRoute], _padding);
    await map.fitRoutes(routes, _padding);
    map.viewportSize = _viewport;
    await mountMap(tester);
    expect(platform.cameraMoves, hasLength(1));
    _expectSame(_positionOf(platform.cameraMoves.single), _expected(routes));

    // A pending fit dropped by clearRouteOptions is never applied.
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    final other = GoogleMapsNavigationMap();
    addTearDown(other.dispose);
    await other.fitRoutes(routes, _padding);
    other.clearRouteOptions();
    other.viewportSize = _viewport;
    await mountMap(tester, other);
    expect(platform.cameraMoves, isEmpty);
    expect(platform.cameraAnimations, isEmpty);
  });

  group('route labels', () {
    // A 1x1 PNG.
    final pixel = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      13,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      0,
      1,
      0,
      0,
      5,
      0,
      1,
      13,
      10,
      45,
      180,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);

    String label(NavRoute r) => '${(r.duration / 60).round()} min';

    gm.Marker marker(int i) => map.routeOptionMarkers.value.singleWhere(
      (m) => m.markerId.value == 'navigation_engine_option_label_$i',
    );

    test('labels appear once rendered', () async {
      addTearDown(map.dispose);
      final gate = Completer<void>();
      final painted = <String>[];
      map
        ..routeLabel = label
        ..labelPixelRatio = 2
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              painted.add('$text/$selected/$pixelRatio');
              await gate.future;
              return pixel;
            };
      final taps = <int>[];
      map.onRouteOptionTap = taps.add;

      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, isEmpty);

      gate.complete();
      await pumpEventQueue();

      expect(map.routeOptionMarkers.value, hasLength(2));
      expect(painted, [
        '${label(routes[0])}/true/2.0',
        '${label(routes[1])}/false/2.0',
      ]);
      for (var i = 0; i < 2; i++) {
        final m = marker(i);
        expect(m.anchor, const Offset(0.5, 1));
        expect(m.zIndexInt, i == 0 ? 7 : 5);
        final p = routes[i].pointAt(routes[i].length / 2);
        expect(m.position.latitude, p.lat);
        expect(m.position.longitude, p.lng);
        expect(m.icon, isA<gm.BytesMapBitmap>());
        final icon = m.icon as gm.BytesMapBitmap;
        expect(icon.byteData, pixel);
        expect(icon.imagePixelRatio, 2);
      }
      marker(1).onTap!();
      expect(taps, [1]);
    });

    test('labels are painted in labelColors', () async {
      addTearDown(map.dispose);
      final painted = <String>[];
      String key(RouteLabelColors c) =>
          '${c.selectedFill.toARGB32()}/${c.selectedText.toARGB32()}/'
          '${c.fill.toARGB32()}/${c.text.toARGB32()}';
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              painted.add('$text/$selected/${key(colors)}');
              return pixel;
            };
      expect(map.labelColors, GoogleStyleColors.day.routeLabelColors);
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(painted, [
        '${label(routes[0])}/true/${key(GoogleStyleColors.day.routeLabelColors)}',
        '${label(routes[1])}/false/${key(GoogleStyleColors.day.routeLabelColors)}',
      ]);
      final dayMarkers = map.routeOptionMarkers.value;
      painted.clear();

      map.labelColors = GoogleStyleColors.night.routeLabelColors;
      // The day labels stay until the night ones are ready.
      expect(map.routeOptionMarkers.value, same(dayMarkers));
      await pumpEventQueue();
      expect(painted, [
        '${label(routes[0])}/true/${key(GoogleStyleColors.night.routeLabelColors)}',
        '${label(routes[1])}/false/${key(GoogleStyleColors.night.routeLabelColors)}',
      ]);
      expect(map.routeOptionMarkers.value, hasLength(2));
      expect(map.routeOptionMarkers.value, isNot(same(dayMarkers)));
      expect(marker(0).zIndexInt, 7);

      // The same colours, or no options shown: nothing is painted.
      painted.clear();
      map.labelColors = GoogleStyleColors.night.routeLabelColors;
      await pumpEventQueue();
      expect(painted, isEmpty);
      map.clearRouteOptions();
      map.labelColors = GoogleStyleColors.day.routeLabelColors;
      await pumpEventQueue();
      expect(painted, isEmpty);
      expect(map.routeOptionMarkers.value, isEmpty);
    });

    test('a colour change drops an older pending label render', () async {
      addTearDown(map.dispose);
      final gate = Completer<void>();
      var calls = 0;
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              // The day renders wait; the night ones are immediate.
              if (calls++ < 2) await gate.future;
              return Uint8List.fromList([
                colors == GoogleStyleColors.day.routeLabelColors ? 1 : 2,
              ]);
            };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      map.labelColors = GoogleStyleColors.night.routeLabelColors;
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      final icon = marker(0).icon as gm.BytesMapBitmap;
      expect(icon.byteData, [2], reason: 'the night label is kept');
    });

    test('a newer showRouteOptions supersedes pending label renders', () async {
      addTearDown(map.dispose);
      final gates = <Completer<void>>[];
      var calls = 0;
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              // The first call (2 renders) waits; the second call is immediate.
              if (calls++ < 2) {
                final gate = Completer<void>();
                gates.add(gate);
                await gate.future;
              }
              return pixel;
            };

      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      map.showRouteOptions(routes, 1);
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, hasLength(2));
      expect(marker(1).zIndexInt, 7);
      expect(marker(0).zIndexInt, 5);

      for (final g in gates) {
        g.complete();
      }
      await pumpEventQueue();

      expect(map.routeOptionMarkers.value, hasLength(2));
      expect(marker(1).zIndexInt, 7);
      expect(marker(0).zIndexInt, 5);
    });

    test('clearRouteOptions drops pending label renders', () async {
      addTearDown(map.dispose);
      final gate = Completer<void>();
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              await gate.future;
              return pixel;
            };
      map.showRouteOptions(routes, 0);
      map.clearRouteOptions();
      gate.complete();
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, isEmpty);
    });

    test('no routeLabel, no markers', () async {
      addTearDown(map.dispose);
      var painted = 0;
      map.labelPainter =
          (
            text, {
            required selected,
            required pixelRatio,
            required colors,
          }) async {
            painted++;
            return pixel;
          };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, isEmpty);
      expect(painted, 0);
    });

    test('a failing painter adds no labels and does not throw', () async {
      addTearDown(map.dispose);
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              throw StateError('no gpu');
            };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, isEmpty);
      expect(map.routeOptionPolylines.value, hasLength(4));
    });
  });

  group('colour changes while options are shown', () {
    Set<String> ids() =>
        map.routeOptionPolylines.value.map((p) => p.polylineId.value).toSet();

    test('alternativeColor redraws the alternatives, ids unchanged', () {
      addTearDown(map.dispose);
      map.showRouteOptions(routes, 1);
      final before = ids();
      expect(option('navigation_engine_option_0').color, _alternative);

      map.alternativeColor = const Color(0xFF5F6368);

      expect(
        option('navigation_engine_option_0').color,
        const Color(0xFF5F6368),
      );
      expect(
        option('navigation_engine_option_casing_0').color,
        Color.lerp(const Color(0xFF5F6368), Colors.white, 0.5),
      );
      expect(
        option('navigation_engine_option_1').color,
        const RouteColors().ahead,
      );
      expect(ids(), before);
      expect(
        option('navigation_engine_option_0').onTap,
        isNotNull,
        reason: 'taps survive a rebuild',
      );
    });

    test(
      'routeColors redraws the selected option and keeps the labels',
      () async {
        addTearDown(map.dispose);
        map
          ..routeLabel = ((r) => 'x')
          ..labelPainter = (
            text, {
            required selected,
            required pixelRatio,
            required colors,
          }) async => Uint8List.fromList([1]);
        map.showRouteOptions(routes, 1);
        await pumpEventQueue();
        final markers = map.routeOptionMarkers.value;
        expect(markers, hasLength(2));

        const red = Color(0xFFFF0000);
        map.routeColors = const RouteColors(ahead: red, aheadWidth: 10);

        expect(option('navigation_engine_option_1').color, red);
        expect(option('navigation_engine_option_1').width, 10);
        expect(option('navigation_engine_option_0').width, 10);
        expect(map.routeOptionMarkers.value, same(markers));
      },
    );

    test('the same colour does not rebuild', () {
      addTearDown(map.dispose);
      map.showRouteOptions(routes, 0);
      final before = map.routeOptionPolylines.value;
      map.alternativeColor = _alternative;
      expect(map.routeOptionPolylines.value, same(before));
    });

    test('nothing is drawn after clearRouteOptions', () {
      addTearDown(map.dispose);
      map.showRouteOptions(routes, 0);
      map.clearRouteOptions();
      map.alternativeColor = const Color(0xFF5F6368);
      map.routeColors = const RouteColors(ahead: Color(0xFFFF0000));
      expect(map.routeOptionPolylines.value, isEmpty);
    });
  });

  group('label image cache', () {
    final png = Uint8List.fromList([1, 2, 3]);
    // Distinct texts: the cache is keyed by text.
    String label(NavRoute r) => identical(r, routes.first) ? 'first' : 'second';

    test('the same labels are not painted twice', () async {
      addTearDown(map.dispose);
      var calls = 0;
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              calls++;
              return png;
            };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(calls, routes.length);

      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(calls, routes.length);
      expect(map.routeOptionMarkers.value, hasLength(routes.length));
    });

    test('the label image cache evicts the least recently used', () async {
      addTearDown(map.dispose);
      final painted = <String>[];
      var text = 'keep';
      map
        ..routeLabel = ((_) => text)
        ..labelPainter =
            (
              t, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              painted.add(t);
              return png;
            };
      void show(String t) {
        text = t;
        map.showRouteOptions([routes.first], 0);
      }

      show('keep');
      // More new labels than the cache holds (32), with 'keep' used again
      // in between: it stays, the others go oldest first.
      for (var i = 0; i < 40; i++) {
        show('label $i');
        show('keep');
      }
      expect(painted.where((t) => t == 'keep'), hasLength(1));
      show('label 0');
      expect(painted.where((t) => t == 'label 0'), hasLength(2));
      await pumpEventQueue();
    });

    test('another selection or ratio paints again', () async {
      addTearDown(map.dispose);
      final keys = <String>[];
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              keys.add('$text/$selected/$pixelRatio');
              return png;
            };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(keys, hasLength(2));

      // Route 0 unselected and route 1 selected are two new images.
      map.showRouteOptions(routes, 1);
      await pumpEventQueue();
      expect(keys, hasLength(4));

      map.labelPixelRatio = 2;
      map.showRouteOptions(routes, 1);
      await pumpEventQueue();
      expect(keys, hasLength(6));
      expect(keys.toSet(), hasLength(6));
    });

    test('a failed render is not cached', () async {
      addTearDown(map.dispose);
      var calls = 0;
      var fail = true;
      map
        ..routeLabel = label
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              calls++;
              if (fail) throw StateError('no gpu');
              return png;
            };
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(map.routeOptionMarkers.value, isEmpty);
      expect(calls, 2);

      fail = false;
      map.showRouteOptions(routes, 0);
      await pumpEventQueue();
      expect(calls, 4);
      expect(map.routeOptionMarkers.value, hasLength(2));
    });

    test('holds up to 32 images and drops the least recently used', () async {
      addTearDown(map.dispose);
      var calls = 0;
      var prefix = 0;
      map
        ..routeLabel = ((r) => '$prefix ${label(r)}')
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              calls++;
              return png;
            };
      Future<void> show() async {
        map.showRouteOptions(routes, 0);
        await pumpEventQueue();
      }

      // 2 images per round: 16 rounds fill the cache exactly.
      for (prefix = 0; prefix < 16; prefix++) {
        await show();
      }
      expect(calls, 32);

      prefix = 15;
      await show();
      expect(calls, 32, reason: 'still cached');
      prefix = 0;
      await show();
      expect(calls, 32, reason: 'the oldest is still there: 32 fit');

      // One more round evicts the two least recently used images: prefix 1
      // (prefix 0 was just used again).
      prefix = 16;
      await show();
      expect(calls, 34);
      prefix = 0;
      await show();
      expect(calls, 34, reason: 'used again, so kept');
      prefix = 1;
      await show();
      expect(calls, 36, reason: 'prefix 1 was dropped');
      prefix = 15;
      await show();
      expect(calls, 36, reason: 'a newer one is kept');
    });
  });

  test('dispose disposes the option notifiers', () {
    map.dispose();
    expect(
      () => map.routeOptionPolylines.addListener(() {}),
      throwsFlutterError,
    );
    expect(() => map.routeOptionMarkers.addListener(() {}), throwsFlutterError);
  });
}
