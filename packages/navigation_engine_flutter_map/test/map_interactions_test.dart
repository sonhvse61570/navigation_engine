// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_flutter_map/navigation_engine_flutter_map.dart';
import 'package:navigation_engine_flutter_map/src/flutter_map_navigation_map.dart'
    show toLatLng;

const _viewport = Size(400, 800);

/// A 1x1 transparent PNG: what the fake painters return.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Two option routes, east-west, about 330 m apart.
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

/// A long alternate (about 2.2 km) and a short one (about 550 m), 660 m
/// apart.
final _longRoute = NavRoute.fromPoints(const [
  GeoPoint(10.770, 106.690),
  GeoPoint(10.770, 106.700),
  GeoPoint(10.770, 106.710),
]);
final _shortRoute = NavRoute.fromPoints(const [
  GeoPoint(10.776, 106.690),
  GeoPoint(10.776, 106.695),
]);

/// Faster, leaving 200 m along: its bubble sits 400 m past that.
final _fast = AlternateRoute(
  route: _longRoute,
  timeDelta: const Duration(minutes: -2),
  divergence: 200,
);

/// Slower, leaving 100 m along: its bubble sits at the middle of its own
/// part, nearer than 400 m.
final _slow = AlternateRoute(
  route: _shortRoute,
  timeDelta: const Duration(minutes: 3),
  divergence: 100,
);

String _altLabel(AlternateRoute a) => identical(a.route, _longRoute)
    ? 'FAST'
    : identical(a.route, _shortRoute)
    ? 'SLOW'
    : 'OTHER';

const _placeA = AlongRoutePlace(
  id: 'a',
  name: 'Fuel A',
  position: GeoPoint(10.770, 106.692),
);
const _placeB = AlongRoutePlace(
  id: 'b',
  name: 'Fuel B',
  position: GeoPoint(10.770, 106.698),
);

/// One call of a fake pin painter.
typedef _PinCall = ({bool focused, double pixelRatio, Color color});

/// Fake painters that record their calls; a call can be held on [gate] or
/// fail with [error].
class _Painters {
  final pinCalls = <_PinCall>[];
  final destinationCalls = <double>[];
  Completer<void>? gate;
  Object? error;

  /// The bytes of each search pin, by focus: distinct lists, so a marker's
  /// image tells which it is.
  final normal = Uint8List.fromList(_png);
  final focused = Uint8List.fromList(_png);
  final destination = Uint8List.fromList(_png);

  Future<Uint8List> pin({
    required bool focused,
    required double pixelRatio,
    required Color color,
  }) async {
    pinCalls.add((focused: focused, pixelRatio: pixelRatio, color: color));
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return focused ? this.focused : normal;
  }

  Future<Uint8List> destinationPin({required double pixelRatio}) async {
    destinationCalls.add(pixelRatio);
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return destination;
  }

  void install(FlutterMapNavigationMap map) => map
    ..pinPainter = pin
    ..destinationPinPainter = destinationPin;
}

/// The image a pin marker shows (the marker's child is the map's private
/// tap target, whose `child` is the image).
Image _imageOf(fm.Marker m) => (m.child as dynamic).child as Image;

Uint8List _bytesOf(fm.Marker m) => (_imageOf(m).image as MemoryImage).bytes;

/// The label bubble an alternate's marker shows.
RouteLabelBubble _bubbleOf(fm.Marker m) {
  RouteLabelBubble? found;
  void visit(Widget w) {
    if (w is RouteLabelBubble) {
      found = w;
      return;
    }
    // The tap target and the alignment each have one `child`.
    final child = (w as dynamic).child;
    if (child is Widget) visit(child);
  }

  visit(m.child);
  return found!;
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

/// Shows the view with a started session and returns its adapter, with
/// [painters] installed.
Future<FlutterMapNavigationMap> _mountView(
  WidgetTester tester, {
  _Painters? painters,
  void Function(GeoPoint)? onMapTap,
  void Function(GeoPoint)? onMapLongPress,
  double horizontalFocus = 0.5,
  TextDirection textDirection = TextDirection.ltr,
  String Function(NavRoute)? routeLabel,
  void Function(int)? onRouteOptionTap,
  String Function(AlternateRoute)? alternateLabel,
  Color? alternateColor,
  RouteLabelColors? fasterLabelColors,
  RouteLabelColors? slowerLabelColors,
  Color? searchPinColor,
  NavigationSession? session,
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = session ?? (NavigationSession(fixes: _Fixes())..start());
  if (session == null) addTearDown(s.dispose);
  await tester.pumpWidget(
    _view(
      s,
      onMapTap: onMapTap,
      onMapLongPress: onMapLongPress,
      horizontalFocus: horizontalFocus,
      textDirection: textDirection,
      routeLabel: routeLabel,
      onRouteOptionTap: onRouteOptionTap,
      alternateLabel: alternateLabel,
      alternateColor: alternateColor,
      fasterLabelColors: fasterLabelColors,
      slowerLabelColors: slowerLabelColors,
      searchPinColor: searchPinColor,
    ),
  );
  await tester.pump();
  await tester.pump();
  final map = s.map! as FlutterMapNavigationMap;
  (painters ?? _Painters()).install(map);
  return map;
}

Widget _view(
  NavigationSession session, {
  void Function(GeoPoint)? onMapTap,
  void Function(GeoPoint)? onMapLongPress,
  double horizontalFocus = 0.5,
  TextDirection textDirection = TextDirection.ltr,
  String Function(NavRoute)? routeLabel,
  void Function(int)? onRouteOptionTap,
  String Function(AlternateRoute)? alternateLabel,
  Color? alternateColor,
  RouteLabelColors? fasterLabelColors,
  RouteLabelColors? slowerLabelColors,
  Color? searchPinColor,
}) => MaterialApp(
  home: Directionality(
    textDirection: textDirection,
    child: FlutterMapNavigationView(
      session: session,
      initialCenter: _west.points.first,
      initialZoom: 13,
      userAgentPackageName: 'dev.navigationengine.test',
      tileUrlTemplate: '',
      onMapTap: onMapTap,
      onMapLongPress: onMapLongPress,
      horizontalFocus: horizontalFocus,
      routeLabel: routeLabel,
      onRouteOptionTap: onRouteOptionTap,
      alternateLabel: alternateLabel,
      alternateColor: alternateColor,
      fasterLabelColors: fasterLabelColors,
      slowerLabelColors: slowerLabelColors,
      searchPinColor: searchPinColor,
    ),
  ),
);

/// The screen position of [p].
Offset _screenOf(FlutterMapNavigationMap map, GeoPoint p) =>
    map.controller.camera.latLngToScreenOffset(toLatLng(p));

/// The screen position of [route] at [fraction] of its length.
Offset _screenAt(
  FlutterMapNavigationMap map,
  NavRoute route,
  double fraction,
) => _screenOf(map, route.pointAt(route.length * fraction));

/// Waits out flutter_map's double-tap window, then the guard's one turn.
Future<void> _settleTap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(Duration.zero);
}

/// Calls the map's `MapOptions.onTap` directly, as a map tap at [at]. This
/// tests the guard and its wiring (the view's `onTap`, each feature's
/// `featureTapped`): flutter_map itself never reports a map tap for a
/// gesture a feature's layer won, and reports one only after its 250 ms
/// double-tap window, so these orders do not arise from real gestures.
void _guardTap(WidgetTester tester, Offset at) {
  final options = tester
      .widget<fm.FlutterMap>(find.byType(fm.FlutterMap))
      .options;
  options.onTap!(fm.TapPosition(at, at), const LatLng(10.5, 106.5));
}

/// The layers of the map, bottom to top, by what they draw.
List<String> _layerOrder(WidgetTester tester, FlutterMapNavigationMap map) {
  final children = tester
      .widget<fm.FlutterMap>(find.byType(fm.FlutterMap))
      .children;
  final names = <String>[];
  for (final child in children) {
    if (child is fm.TileLayer) {
      names.add('tiles');
    } else if (child is ValueListenableBuilder) {
      final l = child.valueListenable;
      names.add(
        identical(l, map.alternateLines)
            ? 'alternates'
            : identical(l, map.routeOptionLines)
            ? 'options'
            : identical(l, map.route)
            ? 'route'
            : identical(l, map.alternateLabels)
            ? 'alternate bubbles'
            : identical(l, map.routeOptionLabels)
            ? 'option labels'
            : identical(l, map.destinationPin)
            ? 'destination'
            : identical(l, map.searchPins)
            ? 'search pins'
            : identical(l, map.vehicle)
            ? 'vehicle'
            : 'other',
      );
    } else if (child is Padding) {
      names.add('attribution');
    } else {
      names.add('app');
    }
  }
  return names;
}

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

void main() {
  group('alternates', () {
    late FlutterMapNavigationMap map;
    setUp(() => map = FlutterMapNavigationMap());
    tearDown(() => map.dispose());

    test('are grey lines, 70 % as wide as the route', () {
      map
        ..routeColors = const RouteColors(aheadWidth: 10)
        ..showAlternates([_fast, _slow], onTap: (_) {});
      final lines = map.alternateLines.value;
      expect(lines, hasLength(2));
      expect(lines.map((l) => l.color), everyElement(const Color(0xFF9AA0A6)));
      expect(lines.map((l) => l.strokeWidth), everyElement(7));
      // Each line is the alternate's own part (alternateLinePoints): from
      // 40 m before its divergence to its end.
      expect(
        lines[0].points,
        alternateLinePoints(_fast).map(toLatLng).toList(),
      );
      expect(
        lines[1].points,
        alternateLinePoints(_slow).map(toLatLng).toList(),
      );
      expect(lines[0].points.first, toLatLng(_longRoute.pointAt(160)));
      expect(lines[1].points.first, toLatLng(_shortRoute.pointAt(60)));
      expect(lines.map((l) => l.hitValue), everyElement(isNotNull));
    });

    test('a new colour or route width redraws them', () {
      map.showAlternates([_fast], onTap: (_) {});
      map.alternateColor = const Color(0xFF112233);
      expect(map.alternateLines.value.single.color, const Color(0xFF112233));
      map.routeColors = const RouteColors(aheadWidth: 20);
      expect(map.alternateLines.value.single.strokeWidth, 14);
    });

    test('bubbles sit at most 400 m past the divergence, else at the middle '
        'of the alternate\'s own part, in the faster or slower colours', () {
      const faster = RouteLabelColors(text: Color(0xFF00AA00));
      const slower = RouteLabelColors(text: Color(0xFFAA0000));
      map
        ..alternateLabel = _altLabel
        ..setAlternateLabelColors(faster: faster, slower: slower)
        ..showAlternates([_fast, _slow], onTap: (_) {});
      final bubbles = map.alternateLabels.value;
      expect(bubbles, hasLength(2));
      expect(
        bubbles[0].point,
        toLatLng(
          _longRoute.pointAt(200 + FlutterMapNavigationMap.alternateLabelLead),
        ),
      );
      expect(
        bubbles[1].point,
        toLatLng(_shortRoute.pointAt((100 + _shortRoute.length) / 2)),
      );
      expect(_bubbleOf(bubbles[0]).text, 'FAST');
      expect(_bubbleOf(bubbles[0]).colors, faster);
      expect(_bubbleOf(bubbles[1]).text, 'SLOW');
      expect(_bubbleOf(bubbles[1]).colors, slower);
      expect(bubbles.map((b) => _bubbleOf(b).selected), everyElement(isFalse));
      // Upright and anchored at the bottom centre, as the option labels.
      expect(bubbles.map((b) => b.rotate), everyElement(isTrue));
      expect(
        bubbles.map((b) => b.alignment),
        everyElement(Alignment.topCenter),
      );
    });

    test('without alternateLabel there are no bubbles; setting it adds them, '
        'null removes them', () {
      map.showAlternates([_fast, _slow], onTap: (_) {});
      expect(map.alternateLines.value, hasLength(2));
      expect(map.alternateLabels.value, isEmpty);
      map.alternateLabel = _altLabel;
      expect(map.alternateLabels.value, hasLength(2));
      map.alternateLabel = null;
      expect(map.alternateLabels.value, isEmpty);
      expect(map.alternateLines.value, hasLength(2), reason: 'lines stay');
    });

    test('the same label wording the bubbles anew (a new language) rebuilds '
        'them; the same texts keep them', () {
      var words = 'faster';
      String label(AlternateRoute a) => words;
      map
        ..alternateLabel = label
        ..showAlternates([_fast], onTap: (_) {});
      final first = map.alternateLabels.value;
      map.alternateLabel = label;
      expect(map.alternateLabels.value, same(first), reason: 'same texts');
      words = 'nhanh hơn';
      map.alternateLabel = label;
      expect(_bubbleOf(map.alternateLabels.value.single).text, 'nhanh hơn');
    });

    test('new bubble colours rebuild the bubbles shown', () {
      map
        ..alternateLabel = _altLabel
        ..showAlternates([_fast], onTap: (_) {});
      const faster = RouteLabelColors(text: Color(0xFF0000FF));
      map.setAlternateLabelColors(
        faster: faster,
        slower: map.slowerLabelColors,
      );
      expect(_bubbleOf(map.alternateLabels.value.single).colors, faster);
    });

    test('the default bubble colours are the Mapbox-style day ones', () {
      final day = alternateLabelColorsOf(MapboxStyleColors.day);
      expect(map.fasterLabelColors, day.faster);
      expect(map.slowerLabelColors, day.slower);
      expect(day.faster.text, MapboxStyleColors.day.accent);
      expect(day.slower.text, MapboxStyleColors.day.onSurfaceVariant);
      expect(day.faster.fill, MapboxStyleColors.day.surface);
    });

    test('a line ends 40 m after the rejoin', () {
      final rejoining = AlternateRoute(
        route: _longRoute,
        timeDelta: Duration.zero,
        divergence: 200,
        rejoin: (alternate: 1500, current: 1500),
      );
      map.showAlternates([rejoining], onTap: (_) {});
      final line = map.alternateLines.value.single.points;
      expect(line, alternateLinePoints(rejoining).map(toLatLng).toList());
      expect(line.last, toLatLng(_longRoute.pointAt(1540)));
    });

    test('a bubble lies on the drawn line: on a short detour, at the '
        'middle of the part that differs (alternateLabelDistance)', () {
      final (_, detour) = _sharedRoutes();
      final short = AlternateRoute(
        route: detour,
        timeDelta: Duration.zero,
        divergence: 1040,
        rejoin: (alternate: 1240, current: 1000),
      );
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([short], onTap: (_) {});
      expect(
        map.alternateLabels.value.single.point,
        toLatLng(detour.pointAt(1140)),
      );
    });

    test('a map built without colours has the shared defaults', () {
      expect(map.labelColors, MapDefaultColors.routeLabels);
      expect(map.alternateColor, MapDefaultColors.alternate);
      expect(map.fasterLabelColors, MapDefaultColors.fasterLabels);
      expect(map.slowerLabelColors, MapDefaultColors.slowerLabels);
      expect(map.pinColor, MapDefaultColors.searchPin);
    });

    test('clearAlternates removes the lines and the bubbles', () {
      map
        ..alternateLabel = _altLabel
        ..showAlternates([_fast, _slow], onTap: (_) {})
        ..clearAlternates();
      expect(map.alternateLines.value, isEmpty);
      expect(map.alternateLabels.value, isEmpty);
      // A label change afterwards draws nothing.
      map.alternateLabel = (_) => 'x';
      expect(map.alternateLabels.value, isEmpty);
    });
  });

  group('search pins', () {
    late FlutterMapNavigationMap map;
    late _Painters painters;
    setUp(() {
      map = FlutterMapNavigationMap()..pixelRatio = 2;
      painters = _Painters()..install(map);
    });
    tearDown(() => map.dispose());

    test('one marker per place, the focused one larger and last, anchored at '
        'the tip', () async {
      map.pinColor = const Color(0xFF00FF00);
      await map.showSearchPins([_placeB, _placeA], focusedId: 'b');
      final pins = map.searchPins.value;
      expect(pins, hasLength(2));
      expect(pins.first.point, toLatLng(_placeA.position));
      expect(pins.last.point, toLatLng(_placeB.position), reason: 'on top');
      expect(_bytesOf(pins.first), same(painters.normal));
      expect(_bytesOf(pins.last), same(painters.focused));
      expect((pins.first.width, pins.first.height), (28.0, 36.0));
      expect(pins.last.width, closeTo(28 * 1.3, 1e-9));
      expect(pins.last.height, closeTo(36 * 1.3, 1e-9));
      expect(_imageOf(pins.first).image, isA<MemoryImage>());
      expect((_imageOf(pins.first).image as MemoryImage).scale, 2);
      expect(pins.map((p) => p.alignment), everyElement(Alignment.topCenter));
      expect(pins.map((p) => p.rotate), everyElement(isTrue));
      expect(painters.pinCalls, [
        (focused: false, pixelRatio: 2.0, color: const Color(0xFF00FF00)),
        (focused: true, pixelRatio: 2.0, color: const Color(0xFF00FF00)),
      ]);
    });

    test('the default pin colour is the Mapbox-style day warning', () {
      expect(map.pinColor, MapboxStyleColors.day.warning);
    });

    test('clearSearchPins and an empty list remove them', () async {
      await map.showSearchPins([_placeA]);
      expect(map.searchPins.value, hasLength(1));
      map.clearSearchPins();
      expect(map.searchPins.value, isEmpty);
      await map.showSearchPins([_placeA]);
      await map.showSearchPins(const []);
      expect(map.searchPins.value, isEmpty);
    });

    test('a newer call or a clear drops a render still pending', () async {
      painters.gate = Completer();
      final first = map.showSearchPins([_placeA]);
      map.clearSearchPins();
      painters.gate!.complete();
      await first;
      expect(map.searchPins.value, isEmpty);

      final held = Completer<void>();
      painters.gate = held;
      final older = map.showSearchPins([_placeA]);
      painters.gate = null;
      await map.showSearchPins([_placeB]);
      expect(map.searchPins.value.single.point, toLatLng(_placeB.position));
      // Release the older render: it must not replace the newer pins.
      held.complete();
      await older;
      expect(map.searchPins.value.single.point, toLatLng(_placeB.position));
    });

    test('a failed render clears the pins and reports the error', () async {
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      await map.showSearchPins([_placeA]);
      painters.error = StateError('boom');
      await map.showSearchPins([_placeB]);
      expect(map.searchPins.value, isEmpty);
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'navigation_engine_flutter_map');
    });

    test('a new pin colour paints the pins shown again', () async {
      await map.showSearchPins([_placeA], focusedId: 'a');
      painters.pinCalls.clear();
      map.pinColor = const Color(0xFF0000FF);
      await pumpEventQueue();
      expect(
        painters.pinCalls.map((c) => c.color),
        everyElement(const Color(0xFF0000FF)),
      );
      expect(painters.pinCalls, hasLength(2));
      expect(map.searchPins.value.single.point, toLatLng(_placeA.position));
    });
  });

  group('destination pin', () {
    late FlutterMapNavigationMap map;
    late _Painters painters;
    setUp(() {
      map = FlutterMapNavigationMap()..pixelRatio = 3;
      painters = _Painters()..install(map);
    });
    tearDown(() => map.dispose());

    test('moves, and null removes it; the image is rendered once', () async {
      map.showDestinationPin(_placeA.position);
      await pumpEventQueue();
      final pin = map.destinationPin.value!;
      expect(pin.point, toLatLng(_placeA.position));
      expect((pin.width, pin.height), (32.0, 42.0));
      expect(pin.alignment, Alignment.topCenter);
      expect(pin.rotate, isTrue);
      expect(_bytesOf(pin), same(painters.destination));
      expect((_imageOf(pin).image as MemoryImage).scale, 3);

      map.showDestinationPin(_placeB.position);
      await pumpEventQueue();
      expect(map.destinationPin.value!.point, toLatLng(_placeB.position));
      expect(painters.destinationCalls, [3.0], reason: 'cached per ratio');

      map.showDestinationPin(null);
      expect(map.destinationPin.value, isNull);
    });

    test('a newer call drops a render still pending', () async {
      painters.gate = Completer();
      map
        ..showDestinationPin(_placeA.position)
        ..showDestinationPin(null);
      painters.gate!.complete();
      await pumpEventQueue();
      expect(map.destinationPin.value, isNull);
    });

    test('a failed render removes the pin and reports the error', () async {
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      painters.error = StateError('boom');
      map.showDestinationPin(_placeA.position);
      await pumpEventQueue();
      expect(map.destinationPin.value, isNull);
      expect(errors.single.exception, isA<StateError>());
      // The failed image is not kept: the next call renders again.
      painters.error = null;
      map.showDestinationPin(_placeB.position);
      await pumpEventQueue();
      expect(map.destinationPin.value!.point, toLatLng(_placeB.position));
      expect(painters.destinationCalls, hasLength(2));
    });

    testWidgets('the default painter is paintDestinationPin', (tester) async {
      final plain = FlutterMapNavigationMap()..pixelRatio = 1;
      addTearDown(plain.dispose);
      plain.showDestinationPin(_placeA.position);
      final expected = await tester.runAsync(
        () => paintDestinationPin(pixelRatio: 1),
      );
      for (var i = 0; i < 100 && plain.destinationPin.value == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(_bytesOf(plain.destinationPin.value!), expected);
    });
  });

  test('dispose drops pending renders', () async {
    final map = FlutterMapNavigationMap();
    final painters = _Painters()
      ..install(map)
      ..gate = Completer();
    final pins = map.showSearchPins([_placeA]);
    map
      ..showDestinationPin(_placeA.position)
      ..dispose();
    painters.gate!.complete();
    // Writing to the disposed notifiers would throw.
    await pins;
    await pumpEventQueue();
  });

  group('the view', () {
    testWidgets('draws the layers in order: alternates under the route, '
        'pins above it and below the vehicle', (tester) async {
      final map = await _mountView(tester, alternateLabel: _altLabel);
      map
        ..showAlternates([_fast], onTap: (_) {})
        ..showDestinationPin(_placeA.position);
      await map.showSearchPins([_placeA]);
      await tester.pump();
      expect(_layerOrder(tester, map), [
        'tiles',
        'alternates',
        'options',
        'route',
        'alternate bubbles',
        'option labels',
        'destination',
        'search pins',
        'vehicle',
        'attribution',
      ]);
      expect(find.byType(RouteLabelBubble), findsOneWidget);
      // Two pins (search and destination) are images on the map.
      expect(
        find.descendant(
          of: find.byType(fm.MarkerLayer),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('forwards the alternate and pin parameters to the map', (
      tester,
    ) async {
      const faster = RouteLabelColors(text: Color(0xFF010101));
      const slower = RouteLabelColors(text: Color(0xFF020202));
      final map = await _mountView(
        tester,
        alternateLabel: _altLabel,
        alternateColor: const Color(0xFF030303),
        fasterLabelColors: faster,
        slowerLabelColors: slower,
        searchPinColor: const Color(0xFF040404),
      );
      expect(map.alternateLabel, same(_altLabel));
      expect(map.alternateColor, const Color(0xFF030303));
      expect(map.fasterLabelColors, faster);
      expect(map.slowerLabelColors, slower);
      expect(map.pinColor, const Color(0xFF040404));
      expect(map.pixelRatio, 1, reason: 'the device pixel ratio');
    });

    testWidgets('null colours keep the map\'s own', (tester) async {
      final map = await _mountView(tester);
      expect(map.alternateLabel, isNull);
      expect(map.alternateColor, const Color(0xFF9AA0A6));
      expect(
        map.fasterLabelColors,
        alternateLabelColorsOf(MapboxStyleColors.day).faster,
      );
      expect(map.pinColor, MapboxStyleColors.day.warning);
    });

    group('alternate taps', () {
      Future<(FlutterMapNavigationMap, List<int>)> mount(
        WidgetTester tester, {
        String Function(AlternateRoute)? label,
      }) async {
        final taps = <int>[];
        final map = await _mountView(tester, alternateLabel: label);
        map.showAlternates([_fast, _slow], onTap: taps.add);
        await map.fitRoutes([
          _longRoute,
          _shortRoute,
        ], const EdgeInsets.all(40));
        await tester.pump();
        return (map, taps);
      }

      testWidgets('a tap on a line calls onTap with its index', (tester) async {
        final (map, taps) = await mount(tester);
        await tester.tapAt(_screenAt(map, _shortRoute, 0.9));
        await _settleTap(tester);
        expect(taps, [1]);
        await tester.tapAt(_screenAt(map, _longRoute, 0.9));
        await _settleTap(tester);
        expect(taps, [1, 0]);
      });

      testWidgets('a tap on a bubble calls onTap with its index', (
        tester,
      ) async {
        final (_, taps) = await mount(tester, label: _altLabel);
        await tester.tap(find.text('SLOW'));
        await _settleTap(tester);
        await tester.tap(find.text('FAST'));
        await _settleTap(tester);
        expect(taps, [1, 0]);
      });

      testWidgets('a tap on a line drawn for an older list is ignored', (
        tester,
      ) async {
        final (map, taps) = await mount(tester);
        // The same line, for another route object: a new alternate list.
        final copy = AlternateRoute(
          route: NavRoute.fromPoints(_shortRoute.points),
          timeDelta: _slow.timeDelta,
          divergence: _slow.divergence,
        );
        final at = _screenAt(map, _shortRoute, 0.9);
        final gesture = await tester.startGesture(at);
        map.showAlternates([_fast, copy], onTap: taps.add);
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(taps, isEmpty, reason: 'pressed on the old line');

        await tester.tapAt(at);
        await _settleTap(tester);
        expect(taps, [1], reason: 'the new line takes taps');
      });

      testWidgets('a tap on a bubble drawn for an older list is ignored', (
        tester,
      ) async {
        final (map, taps) = await mount(tester, label: (_) => 'ALT');
        final copy = AlternateRoute(
          route: NavRoute.fromPoints(_shortRoute.points),
          timeDelta: _slow.timeDelta,
          divergence: _slow.divergence,
        );
        final at = tester.getCenter(find.text('ALT').last);
        final gesture = await tester.startGesture(at);
        map.showAlternates([_fast, copy], onTap: taps.add);
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(taps, isEmpty, reason: 'pressed on the old bubble');

        await tester.tap(find.text('ALT').last);
        await _settleTap(tester);
        expect(taps, [1], reason: 'the new bubble takes taps');
      });

      testWidgets('a tap where an alternate shares the route is a map tap, '
          'even where the route is not drawn; a tap on its own part '
          'selects it', (tester) async {
        final mapTaps = <GeoPoint>[];
        final taps = <int>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        final (main, detour) = _sharedRoutes();
        map.showAlternates([
          AlternateRoute(
            route: detour,
            timeDelta: const Duration(minutes: -1),
            divergence: 1040,
            rejoin: (alternate: detour.length - 1040, current: 2000),
          ),
        ], onTap: taps.add);
        await map.fitRoutes([detour], const EdgeInsets.all(40));
        await tester.pump();
        for (final p in [main.pointAt(500), main.pointAt(2600)]) {
          await tester.tapAt(_screenOf(map, p));
          await _settleTap(tester);
        }
        expect(taps, isEmpty);
        expect(mapTaps, hasLength(2));
        await tester.tapAt(_screenOf(map, detour.pointAt(1800)));
        await _settleTap(tester);
        expect(taps, [0]);
        expect(mapTaps, hasLength(2));
      });

      testWidgets('the session route takes the taps where it covers an '
          'alternate: they are map taps', (tester) async {
        final mapTaps = <GeoPoint>[];
        final taps = <int>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        map
          ..showAlternates([_fast], onTap: taps.add)
          ..showRoute(
            [_longRoute.points.first, _longRoute.pointAt(500)],
            [_longRoute.pointAt(500), _longRoute.points[1]],
          );
        await map.fitRoutes([_longRoute], const EdgeInsets.all(40));
        await tester.pump();
        await tester.tapAt(_screenAt(map, _longRoute, 0.25));
        await _settleTap(tester);
        expect(taps, isEmpty);
        expect(mapTaps, hasLength(1));
        // Past the route's end the alternate takes the tap.
        await tester.tapAt(_screenAt(map, _longRoute, 0.9));
        await _settleTap(tester);
        expect(taps, [0]);
        expect(mapTaps, hasLength(1));
      });
    });

    group('pin taps', () {
      testWidgets('a tap on a search pin calls onTap with its place', (
        tester,
      ) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        final tapped = <AlongRoutePlace>[];
        await map.showSearchPins([_placeA, _placeB], onTap: tapped.add);
        await tester.pump();
        await tester.tapAt(
          _screenOf(map, _placeB.position) - const Offset(0, 18),
        );
        await _settleTap(tester);
        expect(tapped, [_placeB]);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a search pin without onTap still takes the tap', (
        tester,
      ) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        await map.showSearchPins([_placeA]);
        await tester.pump();
        await tester.tapAt(
          _screenOf(map, _placeA.position) - const Offset(0, 18),
        );
        await _settleTap(tester);
        expect(mapTaps, isEmpty);
      });

      // A third place, between A and B.
      const placeC = AlongRoutePlace(
        id: 'c',
        name: 'Fuel C',
        position: GeoPoint(10.770, 106.695),
      );

      testWidgets('a press on a pin that a newer list moves to another slot '
          'never reports the place now in its slot', (tester) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        final tapped = <String>[];
        void onTap(AlongRoutePlace p) => tapped.add(p.id);
        await map.showSearchPins([_placeA, _placeB, placeC], onTap: onTap);
        await tester.pump();
        final gesture = await tester.startGesture(
          _screenOf(map, placeC.position) - const Offset(0, 18),
        );
        // Focusing A moves it to the end: C's slot now holds A.
        await map.showSearchPins(
          [_placeA, _placeB, placeC],
          focusedId: 'a',
          onTap: onTap,
        );
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(tapped, isNot(contains('a')));
        // C is still drawn under the finger: the press is C's, not the
        // map's.
        expect(tapped, ['c']);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a press on a pin that a newer list removes reports '
          'nothing, and is no map tap', (tester) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        final tapped = <String>[];
        void onTap(AlongRoutePlace p) => tapped.add(p.id);
        await map.showSearchPins([_placeA, _placeB, placeC], onTap: onTap);
        await tester.pump();
        final gesture = await tester.startGesture(
          _screenOf(map, placeC.position) - const Offset(0, 18),
        );
        // C goes; A, now focused, takes its slot.
        await map.showSearchPins(
          [_placeB, _placeA],
          focusedId: 'a',
          onTap: onTap,
        );
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(tapped, isEmpty);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a press on a pin drawn again unchanged still reports its '
          'place', (tester) async {
        final map = await _mountView(tester);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        final tapped = <String>[];
        void onTap(AlongRoutePlace p) => tapped.add(p.id);
        await map.showSearchPins([_placeA, _placeB, placeC], onTap: onTap);
        await tester.pump();
        final gesture = await tester.startGesture(
          _screenOf(map, placeC.position) - const Offset(0, 18),
        );
        // A new colour paints the same pins again, in the same slots.
        map.pinColor = const Color(0xFF123456);
        await tester.pump();
        expect(map.searchPins.value, hasLength(3));
        await gesture.up();
        await _settleTap(tester);
        expect(tapped, ['c']);
      });

      testWidgets('a press on a route option label that a new selection '
          'moves to another slot reports its own route', (tester) async {
        final mapTaps = <GeoPoint>[];
        final taps = <int>[];
        final map = await _mountView(
          tester,
          onMapTap: mapTaps.add,
          routeLabel: (r) => identical(r, _west) ? 'W' : 'N',
          onRouteOptionTap: taps.add,
        );
        map.showRouteOptions([_west, _north], 0);
        await map.fitRoutes([_west, _north], const EdgeInsets.all(40));
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('N')),
        );
        // Selecting N draws its label last: W's label takes N's slot.
        map.showRouteOptions([_west, _north], 1);
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(taps, [1]);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a drag that starts on a pin pans the map and is no tap', (
        tester,
      ) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        final tapped = <AlongRoutePlace>[];
        await map.showSearchPins([_placeA], onTap: tapped.add);
        await tester.pump();
        final before = map.controller.camera.center;
        await tester.dragFrom(
          _screenOf(map, _placeA.position) - const Offset(0, 18),
          const Offset(0, 150),
        );
        await _settleTap(tester);
        expect(map.controller.camera.center, isNot(before));
        expect(tapped, isEmpty);
        expect(mapTaps, isEmpty);
      });

      // Shows W and N as route options with labels, and presses on N's.
      Future<(FlutterMapNavigationMap, TestGesture, List<int>, List<GeoPoint>)>
      pressOnLabelN(WidgetTester tester) async {
        final mapTaps = <GeoPoint>[];
        final taps = <int>[];
        final map = await _mountView(
          tester,
          onMapTap: mapTaps.add,
          routeLabel: (r) => identical(r, _west) ? 'W' : 'N',
          onRouteOptionTap: taps.add,
        );
        map.showRouteOptions([_west, _north], 0);
        await map.fitRoutes([_west, _north], const EdgeInsets.all(40));
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('N')),
        );
        return (map, gesture, taps, mapTaps);
      }

      testWidgets('a press on a route option label that ends after the view '
          'is gone calls nothing', (tester) async {
        final (_, gesture, taps, mapTaps) = await pressOnLabelN(tester);
        await tester.pumpWidget(const SizedBox());
        await gesture.up();
        await _settleTap(tester);
        expect(taps, isEmpty);
        expect(mapTaps, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a press on a route option label that ends after the '
          'options are cleared reports nothing, and is no map tap', (
        tester,
      ) async {
        final (map, gesture, taps, mapTaps) = await pressOnLabelN(tester);
        map.clearRouteOptions();
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(taps, isEmpty);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a press on a route option label that a new list moves to '
          'another index reports nothing', (tester) async {
        final (map, gesture, taps, mapTaps) = await pressOnLabelN(tester);
        // N is now at index 0, and index 1 is W: neither stands for the
        // label pressed at index 1.
        map.showRouteOptions([_north, _west], 0);
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(taps, isEmpty);
        expect(mapTaps, isEmpty);
      });

      testWidgets('a press on the destination pin that moves reports no '
          'place and no map tap', (tester) async {
        final mapTaps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: mapTaps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        map.showDestinationPin(_placeA.position);
        await tester.pump();
        final gesture = await tester.startGesture(
          _screenOf(map, _placeA.position) - const Offset(0, 20),
        );
        map.showDestinationPin(_placeB.position);
        await tester.pump();
        await gesture.up();
        await _settleTap(tester);
        expect(mapTaps, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });

    group('map taps', () {
      testWidgets('a tap and a long press reach onMapTap and onMapLongPress', (
        tester,
      ) async {
        final taps = <GeoPoint>[];
        final presses = <GeoPoint>[];
        final map = await _mountView(
          tester,
          onMapTap: taps.add,
          onMapLongPress: presses.add,
        );
        const at = Offset(120, 200);
        final expected = map.controller.camera.screenOffsetToLatLng(at);
        await tester.tapAt(at);
        await _settleTap(tester);
        expect(taps, hasLength(1));
        expect(taps.single.lat, closeTo(expected.latitude, 1e-9));
        expect(taps.single.lng, closeTo(expected.longitude, 1e-9));

        await tester.longPressAt(const Offset(300, 400));
        await tester.pump();
        final pressed = map.controller.camera.screenOffsetToLatLng(
          const Offset(300, 400),
        );
        expect(presses, hasLength(1));
        expect(presses.single.lat, closeTo(pressed.latitude, 1e-9));
        expect(presses.single.lng, closeTo(pressed.longitude, 1e-9));
        expect(taps, hasLength(1), reason: 'a long press is no tap');
      });

      testWidgets('without the callbacks a tap and a long press do nothing', (
        tester,
      ) async {
        await _mountView(tester);
        await tester.tapAt(const Offset(120, 200));
        await _settleTap(tester);
        await tester.longPressAt(const Offset(120, 200));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the callbacks are read when a tap comes', (tester) async {
        final session = NavigationSession(fixes: _Fixes())..start();
        addTearDown(session.dispose);
        final first = <GeoPoint>[];
        final second = <GeoPoint>[];
        final presses = <GeoPoint>[];
        await _mountView(tester, session: session, onMapTap: first.add);
        await tester.pumpWidget(
          _view(session, onMapTap: second.add, onMapLongPress: presses.add),
        );
        await tester.tapAt(const Offset(120, 200));
        await _settleTap(tester);
        await tester.longPressAt(const Offset(120, 200));
        await tester.pump();
        expect(first, isEmpty);
        expect(second, hasLength(1));
        expect(presses, hasLength(1));
      });

      testWidgets('guard wiring: a feature tap drops one direct map tap, in '
          'its frame only', (tester) async {
        final taps = <GeoPoint>[];
        final map = await _mountView(tester, onMapTap: taps.add);
        await map.fitRoutes([_west], const EdgeInsets.all(40));
        map.showDestinationPin(_placeA.position);
        await tester.pump();
        await tester.pump();
        await tester.tapAt(
          _screenOf(map, _placeA.position) - const Offset(0, 20),
        );
        _guardTap(tester, const Offset(10, 10));
        _guardTap(tester, const Offset(10, 10));
        await tester.pump(Duration.zero);
        expect(taps, hasLength(1), reason: 'only the first is dropped');

        await tester.tapAt(
          _screenOf(map, _placeA.position) - const Offset(0, 20),
        );
        await tester.pump(const Duration(milliseconds: 16));
        _guardTap(tester, const Offset(10, 10));
        await tester.pump(Duration.zero);
        expect(taps, hasLength(2), reason: 'a later frame');
      });

      testWidgets('guard wiring: a direct map tap still held when the view '
          'goes is dropped', (tester) async {
        final taps = <GeoPoint>[];
        await _mountView(tester, onMapTap: taps.add);
        _guardTap(tester, const Offset(10, 10));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(Duration.zero);
        expect(taps, isEmpty);
        expect(tester.takeException(), isNull);
      });

      // Each feature the library draws: how to show it, and where to tap it.
      final features =
          <
            String,
            Future<Offset> Function(
              WidgetTester tester,
              FlutterMapNavigationMap map,
              List<String> hits,
            )
          >{
            'a route option line': (tester, map, hits) async {
              map
                ..onRouteOptionTap = ((i) => hits.add('option $i'))
                ..showRouteOptions([_west, _north], 0);
              await map.fitRoutes([_west, _north], const EdgeInsets.all(40));
              await tester.pump();
              return _screenAt(map, _north, 0.15);
            },
            'a route option label': (tester, map, hits) async {
              map
                ..onRouteOptionTap = ((i) => hits.add('option $i'))
                ..routeLabel = ((r) => identical(r, _west) ? 'W' : 'N')
                ..showRouteOptions([_west, _north], 0);
              await map.fitRoutes([_west, _north], const EdgeInsets.all(40));
              await tester.pump();
              return tester.getCenter(find.text('N'));
            },
            'an alternate line': (tester, map, hits) async {
              map.showAlternates([_fast], onTap: (i) => hits.add('alt $i'));
              await map.fitRoutes([_longRoute], const EdgeInsets.all(40));
              await tester.pump();
              return _screenAt(map, _longRoute, 0.9);
            },
            'an alternate bubble': (tester, map, hits) async {
              map
                ..alternateLabel = _altLabel
                ..showAlternates([_fast], onTap: (i) => hits.add('alt $i'));
              await map.fitRoutes([_longRoute], const EdgeInsets.all(40));
              await tester.pump();
              return tester.getCenter(find.text('FAST'));
            },
            'a search pin': (tester, map, hits) async {
              await map.fitRoutes([_west], const EdgeInsets.all(40));
              await map.showSearchPins([
                _placeA,
              ], onTap: (p) => hits.add('pin ${p.id}'));
              await tester.pump();
              return _screenOf(map, _placeA.position) - const Offset(0, 18);
            },
            'the destination pin': (tester, map, hits) async {
              await map.fitRoutes([_west], const EdgeInsets.all(40));
              map.showDestinationPin(_placeA.position);
              await tester.pump();
              await tester.pump();
              return _screenOf(map, _placeA.position) - const Offset(0, 20);
            },
          };

      for (final MapEntry(key: name, value: show) in features.entries) {
        group('on $name', () {
          testWidgets('a tap is no map tap', (tester) async {
            final taps = <GeoPoint>[];
            final hits = <String>[];
            final map = await _mountView(tester, onMapTap: taps.add);
            final at = await show(tester, map, hits);
            await tester.tapAt(at);
            await _settleTap(tester);
            expect(taps, isEmpty);
            if (name != 'the destination pin') expect(hits, hasLength(1));
          });

          testWidgets('guard wiring: a direct map tap after it, in its '
              'frame, is dropped', (tester) async {
            final taps = <GeoPoint>[];
            final map = await _mountView(tester, onMapTap: taps.add);
            final at = await show(tester, map, <String>[]);
            await tester.tapAt(at);
            _guardTap(tester, at);
            await tester.pump(Duration.zero);
            expect(taps, isEmpty);
          });

          testWidgets('guard wiring: a direct map tap before it, in its '
              'turn, is dropped', (tester) async {
            final taps = <GeoPoint>[];
            final map = await _mountView(tester, onMapTap: taps.add);
            final at = await show(tester, map, <String>[]);
            _guardTap(tester, at);
            await tester.tapAt(at);
            await tester.pump(Duration.zero);
            expect(taps, isEmpty);
          });

          testWidgets('a long press reaches onMapLongPress', (tester) async {
            final presses = <GeoPoint>[];
            final map = await _mountView(tester, onMapLongPress: presses.add);
            final at = await show(tester, map, <String>[]);
            await tester.longPressAt(at);
            await tester.pump();
            expect(presses, hasLength(1));
          });
        });
      }
    });

    group('horizontalFocus', () {
      Rect attribution(WidgetTester tester) =>
          tester.getRect(find.byTooltip('Attributions'));

      testWidgets('reaches the frame and moves the followed point', (
        tester,
      ) async {
        final map = await _mountView(tester, horizontalFocus: 0.75);
        expect(
          tester
              .widget<NavigationMapFrame>(find.byType(NavigationMapFrame))
              .horizontalFocus,
          0.75,
        );
        expect(map.mapPadding.left, 200);
        expect(map.mapPadding.right, 0);
        const target = GeoPoint(10.771, 106.694);
        await map.moveCamera(
          const CameraTarget(position: target, bearing: 40, zoom: 16, tilt: 0),
        );
        await tester.pump();
        final shown = _screenOf(map, target);
        expect(shown.dx, closeTo(0.75 * 400, 1e-3));
        expect(shown.dy, closeTo(0.7 * 800, 1e-3));
      });

      testWidgets('centred, the attribution sits at the left edge', (
        tester,
      ) async {
        await _mountView(tester);
        expect(attribution(tester).left, lessThan(20));
      });

      testWidgets('the attribution keeps clear of a panel on the left', (
        tester,
      ) async {
        await _mountView(tester, horizontalFocus: 0.75);
        expect(attribution(tester).left, greaterThanOrEqualTo(200));
        expect(attribution(tester).right, lessThanOrEqualTo(400));
      });

      testWidgets('in RTL, the attribution keeps clear of a panel on the '
          'right, and of one on the left', (tester) async {
        await _mountView(
          tester,
          horizontalFocus: 0.25,
          textDirection: TextDirection.rtl,
        );
        expect(attribution(tester).right, lessThanOrEqualTo(200));
        await tester.pumpWidget(const SizedBox());
        await _mountView(
          tester,
          horizontalFocus: 0.75,
          textDirection: TextDirection.rtl,
        );
        expect(attribution(tester).left, greaterThanOrEqualTo(200));
      });

      testWidgets('a new focus moves the attribution', (tester) async {
        final session = NavigationSession(fixes: _Fixes())..start();
        addTearDown(session.dispose);
        await _mountView(tester, session: session);
        expect(attribution(tester).left, lessThan(20));
        await tester.pumpWidget(_view(session, horizontalFocus: 0.75));
        await tester.pump();
        expect(attribution(tester).left, greaterThanOrEqualTo(200));
      });
    });
  });
}
