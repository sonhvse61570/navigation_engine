// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_flutter_map/navigation_engine_flutter_map.dart';
import 'package:navigation_engine_flutter_map/src/flutter_map_navigation_map.dart'
    show toLatLng;

const _viewport = Size(400, 800);
const _padding = EdgeInsets.fromLTRB(10, 20, 30, 300);
const _alternative = Color(0xFF9AA0A6);

/// Two parallel east-west routes, about 330 m apart.
final _west = NavRoute.fromPoints(const [
  GeoPoint(10.770, 106.690),
  GeoPoint(10.770, 106.695),
  GeoPoint(10.770, 106.700),
]);
final _north = NavRoute.fromPoints(const [
  GeoPoint(10.773, 106.690),
  GeoPoint(10.773, 106.695),
  GeoPoint(10.773, 106.700),
]);
final _routes = [_west, _north];

List<GeoPoint> _allPoints(List<NavRoute> routes) => [
  for (final r in routes) ...r.points,
];

String _label(NavRoute r) => identical(r, _west) ? 'west' : 'north';

/// Shows a bare map wired to [map], 400 x 800.
Future<void> _mountMap(WidgetTester tester, FlutterMapNavigationMap map) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: fm.FlutterMap(
        mapController: map.controller,
        options: fm.MapOptions(
          initialCenter: const LatLng(0, 0),
          initialZoom: 3,
          onMapReady: map.onMapReady,
        ),
        children: const [],
      ),
    ),
  );
  await tester.pump();
}

class _Fixes implements FixSource {
  @override
  Stream<NavFix> get fixes => const Stream.empty();
  @override
  bool get isRunning => true;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
}

/// Shows the view with a started session and returns its adapter.
Future<FlutterMapNavigationMap> _mountView(
  WidgetTester tester, {
  String Function(NavRoute)? routeLabel,
  void Function(int)? onRouteOptionTap,
  RouteLabelColors? labelColors,
  Color? alternativeRouteColor,
  RouteColors routeColors = const RouteColors(),
  bool night = false,
  String? nightTileUrlTemplate,
  String tileUrlTemplate = '',
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = NavigationSession(fixes: _Fixes())..start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMapNavigationView(
        session: session,
        initialCenter: _west.points.first,
        initialZoom: 13,
        userAgentPackageName: 'dev.navigationengine.test',
        tileUrlTemplate: tileUrlTemplate,
        nightTileUrlTemplate: nightTileUrlTemplate,
        night: night,
        routeColors: routeColors,
        routeLabel: routeLabel,
        onRouteOptionTap: onRouteOptionTap,
        labelColors: labelColors ?? const RouteLabelColors(),
        alternativeRouteColor: alternativeRouteColor ?? _alternative,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return session.map! as FlutterMapNavigationMap;
}

/// The screen position of [route] at [fraction] of its length.
Offset _screenAt(FlutterMapNavigationMap map, NavRoute route, double fraction) {
  final p = route.pointAt(route.length * fraction);
  return map.controller.camera.latLngToScreenOffset(toLatLng(p));
}

void _expectCameraShows(
  FlutterMapNavigationMap map,
  CameraTarget expected, {
  required Offset at,
}) {
  final camera = map.controller.camera;
  expect(camera.zoom, closeTo(expected.zoom, 1e-6));
  expect(camera.rotation, 0);
  final shown = camera.latLngToScreenOffset(toLatLng(expected.position));
  expect(shown.dx, closeTo(at.dx, 1e-3));
  expect(shown.dy, closeTo(at.dy, 1e-3));
}

void main() {
  late FlutterMapNavigationMap map;

  setUp(() => map = FlutterMapNavigationMap());

  fm.Polyline<Object> line(int i) => map.routeOptionLines.value[i];

  test('showRouteOptions draws casing and line per route, selected on top', () {
    addTearDown(map.dispose);
    map.showRouteOptions(_routes, 1);

    final lines = map.routeOptionLines.value;
    expect(lines, hasLength(4));
    // Bottom to top: the muted route (casing, line), then the selected one.
    expect(lines.map((l) => l.hitValue), [0, 0, 1, 1]);

    const colors = RouteColors();
    final otherCasing = line(0), other = line(1);
    final selectedCasing = line(2), selected = line(3);

    expect(selected.color, colors.ahead);
    expect(selected.strokeWidth, colors.aheadWidth);
    expect(
      selectedCasing.color,
      Color.lerp(colors.ahead, const Color(0xFF000000), 0.35),
    );
    expect(selectedCasing.strokeWidth, selected.strokeWidth + 4);

    expect(other.color, _alternative);
    expect(other.strokeWidth, colors.aheadWidth);
    expect(
      otherCasing.color,
      Color.lerp(_alternative, const Color(0xFFFFFFFF), 0.5),
    );
    expect(otherCasing.strokeWidth, other.strokeWidth + 4);

    expect(selected.points, hasLength(_north.points.length));
    expect(selected.points.first, toLatLng(_north.points.first));
    expect(other.points.last, toLatLng(_west.points.last));
  });

  test('muted casings, then muted lines, then the selected pair', () {
    addTearDown(map.dispose);
    map.showRouteOptions([_west, _north, sampleRoute], 1);
    final lines = map.routeOptionLines.value;
    // Bottom to top, as z 3, 4, 5, 6 in the Google adapter: no muted casing
    // may paint over another muted route's line.
    expect(lines.map((l) => l.hitValue), [0, 2, 0, 2, 1, 1]);
    const width = 8.0; // RouteColors.aheadWidth
    expect(lines.map((l) => l.strokeWidth), [
      width + 4, width + 4, width, width, // muted casings, muted lines
      width + 4, width, // selected casing, selected line
    ]);
    expect(lines[0].color, lines[1].color, reason: 'muted casings');
    expect(lines[2].color, _alternative);
    expect(lines[3].color, _alternative);
  });

  test('clearRouteOptions removes lines and labels', () {
    addTearDown(map.dispose);
    map
      ..routeLabel = _label
      ..showRouteOptions(_routes, 0);
    expect(map.routeOptionLines.value, isNotEmpty);
    expect(map.routeOptionLabels.value, isNotEmpty);
    map.clearRouteOptions();
    expect(map.routeOptionLines.value, isEmpty);
    expect(map.routeOptionLabels.value, isEmpty);
  });

  test('labels appear only with routeLabel', () {
    addTearDown(map.dispose);
    map.showRouteOptions(_routes, 0);
    expect(map.routeOptionLabels.value, isEmpty);

    map.routeLabel = _label;
    map.showRouteOptions(_routes, 0);
    final labels = map.routeOptionLabels.value;
    expect(labels, hasLength(2));
    for (final route in _routes) {
      final p = route.pointAt(route.length / 2);
      final m = labels.singleWhere((m) => m.point == toLatLng(p));
      // The bubble's bottom-centre is on the point: the box sits above it.
      expect(m.alignment, Alignment.topCenter);
      expect(m.child, isA<GestureDetector>());
    }
  });

  test('a routeLabel change rebuilds the shown labels', () {
    addTearDown(map.dispose);
    map
      ..routeLabel = _label
      ..showRouteOptions(_routes, 0);
    String textOf(fm.Marker m) =>
        ((m.child as GestureDetector).child! as Align).child!
            is RouteLabelBubble
        ? (((m.child as GestureDetector).child! as Align).child!
                  as RouteLabelBubble)
              .text
        : '';
    expect(map.routeOptionLabels.value.map(textOf), {'west', 'north'});
    map.routeLabel = (r) => 'new ${_label(r)}';
    expect(map.routeOptionLabels.value.map(textOf), {'new west', 'new north'});
    map.routeLabel = null;
    expect(map.routeOptionLabels.value, isEmpty);
  });

  test('a casing and its line share one list of points', () {
    addTearDown(map.dispose);
    map.showRouteOptions(_routes, 0);
    final lines = map.routeOptionLines.value;
    for (final i in [0, 1]) {
      final pair = lines.where((l) => l.hitValue == i).toList();
      expect(pair, hasLength(2));
      expect(pair[0].points, same(pair[1].points), reason: 'route $i');
    }
  });

  testWidgets('a label bubble is selected and coloured by labelColors', (
    tester,
  ) async {
    addTearDown(map.dispose);
    const colors = RouteLabelColors(selectedFill: Color(0xFFFF0000));
    map
      ..routeLabel = _label
      ..labelColors = colors
      ..showRouteOptions(_routes, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [for (final m in map.routeOptionLabels.value) m.child],
        ),
      ),
    );
    final bubbles = tester
        .widgetList<RouteLabelBubble>(find.byType(RouteLabelBubble))
        .toList();
    expect(bubbles, hasLength(2));
    expect(bubbles.map((b) => b.colors), everyElement(colors));
    final byText = {for (final b in bubbles) b.text: b};
    expect(byText[_label(_west)]!.selected, isFalse);
    expect(byText[_label(_north)]!.selected, isTrue);
    expect(bubbles.last.selected, isTrue, reason: 'selected is drawn on top');
  });

  testWidgets('tapping a label reports its route index', (tester) async {
    addTearDown(map.dispose);
    final taps = <int>[];
    map
      ..onRouteOptionTap = taps.add
      ..routeLabel = _label
      ..showRouteOptions(_routes, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [for (final m in map.routeOptionLabels.value) m.child],
        ),
      ),
    );
    await tester.tap(find.text(_label(_north)));
    await tester.tap(find.text(_label(_west)));
    expect(taps, [1, 0]);
  });

  group('taps on the option lines', () {
    testWidgets('a hit on an option line reports its index', (tester) async {
      final taps = <int>[];
      final adapter = await _mountView(tester, onRouteOptionTap: taps.add);
      adapter.showRouteOptions(_routes, 0);
      await adapter.fitRoutes(_routes, const EdgeInsets.all(40));
      await tester.pump();

      await tester.tapAt(_screenAt(adapter, _north, 0.25));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [1]);

      await tester.tapAt(_screenAt(adapter, _west, 0.6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [1, 0]);
    });

    testWidgets('a tap away from the lines reports nothing', (tester) async {
      final taps = <int>[];
      final adapter = await _mountView(tester, onRouteOptionTap: taps.add);
      adapter.showRouteOptions(_routes, 0);
      await adapter.fitRoutes(_routes, const EdgeInsets.all(40));
      await tester.pump();

      // Half-way between the two routes.
      final a = _screenAt(adapter, _west, 0.25);
      final b = _screenAt(adapter, _north, 0.25);
      await tester.tapAt(Offset.lerp(a, b, 0.5)!);
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, isEmpty);
    });

    testWidgets('a tap on a label reports the index, in the view', (
      tester,
    ) async {
      final taps = <int>[];
      final adapter = await _mountView(
        tester,
        routeLabel: _label,
        onRouteOptionTap: taps.add,
      );
      adapter.showRouteOptions(_routes, 0);
      await adapter.fitRoutes(_routes, const EdgeInsets.all(40));
      await tester.pump();

      expect(find.byType(RouteLabelBubble), findsNWidgets(2));
      await tester.tap(find.text(_label(_north)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [1]);
    });

    testWidgets('no option layers while nothing is shown', (tester) async {
      final adapter = await _mountView(tester);
      expect(find.byType(fm.PolylineLayer), findsOneWidget);
      expect(find.byType(fm.MarkerLayer), findsOneWidget);
      adapter.showRouteOptions(_routes, 0);
      await tester.pump();
      // Options below the (empty) session route layer.
      expect(find.byType(fm.PolylineLayer), findsNWidgets(2));
      adapter.clearRouteOptions();
      await tester.pump();
      expect(find.byType(fm.PolylineLayer), findsOneWidget);
    });
  });

  group('label geometry', () {
    // The bubble's bottom-centre is on the route's midpoint.
    void expectOnMidpoints(
      WidgetTester tester,
      FlutterMapNavigationMap adapter,
    ) {
      for (final route in _routes) {
        final mid = adapter.controller.camera.latLngToScreenOffset(
          toLatLng(route.pointAt(route.length / 2)),
        );
        final rect = tester.getRect(
          find.widgetWithText(RouteLabelBubble, _label(route)),
        );
        expect(rect.bottomCenter.dx, closeTo(mid.dx, 1), reason: _label(route));
        expect(rect.bottomCenter.dy, closeTo(mid.dy, 1), reason: _label(route));
      }
    }

    testWidgets('the bubble sits above the route midpoint', (tester) async {
      final adapter = await _mountView(tester, routeLabel: _label);
      adapter.showRouteOptions(_routes, 0);
      await adapter.fitRoutes(_routes, const EdgeInsets.all(40));
      await tester.pump();
      expect(find.byType(RouteLabelBubble), findsNWidgets(2));
      expectOnMidpoints(tester, adapter);

      // Rotated, the bubbles stay upright with the same anchor: the markers
      // turn against the map (`rotate: true`).
      adapter.controller.rotate(30);
      await tester.pump();
      for (final route in _routes) {
        final box = tester.renderObject<RenderBox>(
          find.widgetWithText(RouteLabelBubble, _label(route)),
        );
        // The top edge is level on the screen (a 30 degree tilt would
        // put its ends half the width apart).
        final topLeft = box.localToGlobal(Offset.zero);
        final topRight = box.localToGlobal(Offset(box.size.width, 0));
        expect(topRight.dy, closeTo(topLeft.dy, 0.01), reason: 'upright');
        expect(topRight.dx - topLeft.dx, closeTo(box.size.width, 0.01));
      }
      expectOnMidpoints(tester, adapter);
    });
  });

  group('the view forwards its parameters', () {
    testWidgets('to the adapter', (tester) async {
      const colors = RouteLabelColors(selectedFill: Color(0xFF00FF00));
      final adapter = await _mountView(
        tester,
        routeLabel: _label,
        onRouteOptionTap: (_) {},
        labelColors: colors,
        alternativeRouteColor: const Color(0xFF123456),
        routeColors: const RouteColors(ahead: Color(0xFFFF0000)),
      );
      expect(adapter.routeLabel, same(_label));
      expect(adapter.onRouteOptionTap, isNotNull);
      expect(adapter.labelColors, colors);
      expect(adapter.alternativeColor, const Color(0xFF123456));
      expect(adapter.routeColors.ahead, const Color(0xFFFF0000));
      expect(adapter.viewportSize, _viewport);
      // The frame's focus padding: the vehicle sits at 70 % of the height.
      expect(adapter.mapPadding.top, greaterThan(0));
      expect(
        adapter.mapPadding.top - adapter.mapPadding.bottom,
        closeTo(2 * 160, 1e-6),
      );
    });
  });

  group('fitRoutes', () {
    testWidgets('moves the camera to the fitted target', (tester) async {
      addTearDown(map.dispose);
      await _mountMap(tester, map);
      map.viewportSize = _viewport;

      await map.fitRoutes(_routes, _padding);

      _expectCameraShows(
        map,
        fitCameraToBounds(_allPoints(_routes), _viewport, _padding),
        at: _viewport.center(Offset.zero),
      );
    });

    testWidgets('mapPadding shifts the fitted camera', (tester) async {
      addTearDown(map.dispose);
      await _mountMap(tester, map);
      const mapPadding = EdgeInsets.only(top: 320);
      map
        ..mapPadding = mapPadding
        ..viewportSize = _viewport;

      await map.fitRoutes(_routes, _padding);

      final expected = fitCameraToBounds(
        _allPoints(_routes),
        _viewport,
        _padding,
        mapPadding: mapPadding,
      );
      // The target sits at the centre of the view minus the map padding.
      _expectCameraShows(map, expected, at: const Offset(200, 400 + 160));
      // The routes' bounds centre ends up mid-way in the padded rectangle,
      // as without the map padding.
      final plain = fitCameraToBounds(_allPoints(_routes), _viewport, _padding);
      final shown = map.controller.camera.latLngToScreenOffset(
        toLatLng(plain.position),
      );
      expect(shown.dx, closeTo(200, 1e-3));
      expect(shown.dy, closeTo(400, 1e-3));
    });

    testWidgets('a fit before the map is ready is applied once, later', (
      tester,
    ) async {
      addTearDown(map.dispose);
      await map.fitRoutes(_routes, _padding);
      map.viewportSize = _viewport;

      await _mountMap(tester, map);
      final expected = fitCameraToBounds(
        _allPoints(_routes),
        _viewport,
        _padding,
      );
      _expectCameraShows(map, expected, at: const Offset(200, 400));

      // Not applied again: a moved camera stays where it is.
      map.controller.move(const LatLng(1, 1), 5);
      map
        ..viewportSize = const Size(500, 900)
        ..onMapReady();
      expect(map.controller.camera.zoom, 5);
      expect(map.controller.camera.center, const LatLng(1, 1));
    });

    testWidgets('a fit waits for the viewport size when the map is first', (
      tester,
    ) async {
      addTearDown(map.dispose);
      await _mountMap(tester, map);
      await map.fitRoutes(_routes, _padding);
      expect(map.controller.camera.zoom, 3, reason: 'nothing moved yet');

      map.viewportSize = _viewport;
      _expectCameraShows(
        map,
        fitCameraToBounds(_allPoints(_routes), _viewport, _padding),
        at: const Offset(200, 400),
      );
    });

    testWidgets('a newer fit replaces a pending one; clear drops it', (
      tester,
    ) async {
      addTearDown(map.dispose);
      await map.fitRoutes([_west], _padding);
      await map.fitRoutes(_routes, _padding);
      map.viewportSize = _viewport;
      await _mountMap(tester, map);
      _expectCameraShows(
        map,
        fitCameraToBounds(_allPoints(_routes), _viewport, _padding),
        at: const Offset(200, 400),
      );

      final other = FlutterMapNavigationMap();
      addTearDown(other.dispose);
      await other.fitRoutes(_routes, _padding);
      other.clearRouteOptions();
      other.viewportSize = _viewport;
      await _mountMap(tester, other);
      expect(other.controller.camera.zoom, 3);
    });

    testWidgets('no routes, no fit', (tester) async {
      addTearDown(map.dispose);
      await _mountMap(tester, map);
      map.viewportSize = _viewport;
      await map.fitRoutes(const [], _padding);
      expect(map.controller.camera.zoom, 3);
    });

    testWidgets('a fit resets the rotation', (tester) async {
      addTearDown(map.dispose);
      await _mountMap(tester, map);
      map.controller.rotate(40);
      map.viewportSize = _viewport;
      await map.fitRoutes(_routes, _padding);
      expect(map.controller.camera.rotation, 0);
    });
  });

  group('colour changes while options are shown', () {
    test('alternativeColor redraws the alternatives, hit values kept', () {
      addTearDown(map.dispose);
      map.showRouteOptions(_routes, 1);
      final before = map.routeOptionLines.value.map((l) => l.hitValue).toList();
      expect(line(1).color, _alternative);

      map.alternativeColor = const Color(0xFF5F6368);

      expect(line(1).color, const Color(0xFF5F6368));
      expect(
        line(0).color,
        Color.lerp(const Color(0xFF5F6368), const Color(0xFFFFFFFF), 0.5),
      );
      expect(line(3).color, const RouteColors().ahead);
      expect(map.routeOptionLines.value.map((l) => l.hitValue), before);
    });

    test('routeColors redraws the selected option', () {
      addTearDown(map.dispose);
      map.showRouteOptions(_routes, 1);
      const red = Color(0xFFFF0000);
      map.routeColors = const RouteColors(ahead: red, aheadWidth: 10);
      expect(line(3).color, red);
      expect(line(3).strokeWidth, 10);
      expect(line(1).strokeWidth, 10);
      expect(line(2).strokeWidth, 14);
    });

    test('labelColors rebuilds the labels', () {
      addTearDown(map.dispose);
      map
        ..routeLabel = _label
        ..showRouteOptions(_routes, 0);
      final before = map.routeOptionLabels.value;
      map.labelColors = const RouteLabelColors(fill: Color(0xFF000000));
      expect(map.routeOptionLabels.value, hasLength(2));
      expect(map.routeOptionLabels.value, isNot(same(before)));
    });

    test('the same colour does not rebuild', () {
      addTearDown(map.dispose);
      map
        ..routeLabel = _label
        ..showRouteOptions(_routes, 0);
      final lines = map.routeOptionLines.value;
      final labels = map.routeOptionLabels.value;
      map.alternativeColor = _alternative;
      map.routeColors = const RouteColors();
      map.labelColors = const RouteLabelColors();
      expect(map.routeOptionLines.value, same(lines));
      expect(map.routeOptionLabels.value, same(labels));
    });

    test('nothing is drawn after clearRouteOptions', () {
      addTearDown(map.dispose);
      map
        ..routeLabel = _label
        ..showRouteOptions(_routes, 0)
        ..clearRouteOptions();
      map.alternativeColor = const Color(0xFF5F6368);
      map.routeColors = const RouteColors(ahead: Color(0xFFFF0000));
      map.labelColors = const RouteLabelColors(fill: Color(0xFF000000));
      expect(map.routeOptionLines.value, isEmpty);
      expect(map.routeOptionLabels.value, isEmpty);
    });
  });

  group('night tiles', () {
    String urlOf(WidgetTester tester) =>
        tester.widget<fm.TileLayer>(find.byType(fm.TileLayer)).urlTemplate!;

    testWidgets('are used only with a template', (tester) async {
      await _mountView(tester, night: true, tileUrlTemplate: 'day/{z}');
      expect(urlOf(tester), 'day/{z}', reason: 'no night template');
    });

    testWidgets('a template alone does not switch', (tester) async {
      await _mountView(
        tester,
        nightTileUrlTemplate: 'night/{z}',
        tileUrlTemplate: 'day/{z}',
      );
      expect(urlOf(tester), 'day/{z}', reason: 'not night');
    });

    testWidgets('night with a template uses the night tiles, and back', (
      tester,
    ) async {
      final session = NavigationSession(fixes: _Fixes())..start();
      addTearDown(session.dispose);
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget view({required bool night}) => MaterialApp(
        home: FlutterMapNavigationView(
          session: session,
          initialCenter: _west.points.first,
          userAgentPackageName: 'dev.navigationengine.test',
          tileUrlTemplate: 'day/{z}',
          nightTileUrlTemplate: 'night/{z}',
          night: night,
        ),
      );
      await tester.pumpWidget(view(night: false));
      expect(urlOf(tester), 'day/{z}');
      await tester.pumpWidget(view(night: true));
      expect(urlOf(tester), 'night/{z}');
      await tester.pumpWidget(view(night: false));
      expect(urlOf(tester), 'day/{z}');
    });
  });

  test('dispose disposes the option notifiers', () {
    map.dispose();
    expect(() => map.routeOptionLines.addListener(() {}), throwsFlutterError);
    expect(() => map.routeOptionLabels.addListener(() {}), throwsFlutterError);
  });

  test('a pending fit is dropped on dispose', () async {
    final spy = _SpyController();
    final other = FlutterMapNavigationMap(controller: spy);
    await other.fitRoutes(_routes, _padding);
    other.dispose();
    other.viewportSize = _viewport;
    other.onMapReady();
    expect(spy.moves, isEmpty);
    expect(spy.rotations, isEmpty);

    // Control: the same sequence without dispose moves the camera once,
    // north up (a fit has no bearing).
    final live = FlutterMapNavigationMap(controller: spy);
    addTearDown(live.dispose);
    await live.fitRoutes(_routes, _padding);
    live.viewportSize = _viewport;
    live.onMapReady();
    expect(spy.moves, hasLength(1));
    expect(spy.rotations, [0]);
  });
}

/// Records the camera moves; everything else is unused.
class _SpyController implements fm.MapController {
  final moves = <LatLng>[];
  final rotations = <double>[];

  @override
  bool move(
    LatLng center,
    double zoom, {
    Offset offset = Offset.zero,
    String? id,
  }) {
    moves.add(center);
    return true;
  }

  @override
  bool rotate(double degree, {String? id}) {
    rotations.add(degree);
    return true;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
