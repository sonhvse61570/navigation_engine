import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/fake_google_maps_platform.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

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

void main() {
  final alt = sampleRouteAlternatives.single;
  final faster = AlternateRoute(
    route: alt,
    timeDelta: const Duration(minutes: -2),
    divergence: 300,
  );
  final slower = AlternateRoute(
    route: NavRoute.fromPoints(alt.points.reversed.toList()),
    timeDelta: const Duration(minutes: 3),
    divergence: 100,
  );
  const place = AlongRoutePlace(
    id: 'a',
    name: 'Fuel',
    position: GeoPoint(10.78, 106.70),
    detour: Duration(minutes: 4),
  );
  const other = AlongRoutePlace(
    id: 'b',
    name: 'Cafe',
    position: GeoPoint(10.79, 106.71),
  );

  test('the bubble colours of a theme', () {
    const c = GoogleStyleColors.night;
    expect(c.fasterLabelColors.fill, c.buttonSurface);
    expect(c.fasterLabelColors.text, c.etaText);
    expect(c.slowerLabelColors.fill, c.buttonSurface);
    expect(c.slowerLabelColors.text, c.onSurfaceVariant);
  });

  test('AlongRoutePlace and AlongRouteQuery hold their values', () {
    expect(
      place,
      const AlongRoutePlace(
        id: 'a',
        name: 'Fuel',
        position: GeoPoint(10.78, 106.70),
        detour: Duration(minutes: 4),
      ),
    );
    expect(place, isNot(other));
    final q = AlongRouteQuery(
      category: AlongRouteCategory.coffee,
      route: alt,
      fromDistance: 120,
    );
    expect(
      (q.text, q.category, q.fromDistance),
      (null, AlongRouteCategory.coffee, 120.0),
    );
    expect(AlongRouteCategory.values.map((c) => c.name), [
      'gas',
      'restaurant',
      'coffee',
      'grocery',
    ]);
  });

  group('alternates on the map', () {
    test('grey lines under the route, 70 % as wide; a tap selects', () {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final taps = <int>[];
      map.showRoute(sampleRoute.points.take(2).toList(), sampleRoute.points);
      map.showAlternates([faster], onTap: taps.add);
      final line = map.alternatePolylines.value.single;
      expect(line.polylineId.value, 'navigation_engine_alternate_0');
      expect(line.color, GoogleStyleColors.day.alternative);
      expect(line.width, (const RouteColors().aheadWidth * 0.7).round());
      for (final route in map.polylines.value) {
        expect(route.zIndex, greaterThan(line.zIndex));
      }
      line.onTap!();
      expect(taps, [0]);
    });

    test('a bubble at the middle of the part after the divergence (at most '
        '400 m past it), in the faster or slower colours; a tap '
        'selects', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final painted = <(String, RouteLabelColors)>[];
      map
        ..alternateLabel = ((a) => a.minutesDelta < 0 ? 'faster' : 'slower')
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              painted.add((text, colors));
              return _pixel;
            };
      final taps = <int>[];
      map.showAlternates([faster, slower], onTap: taps.add);
      await pumpEventQueue();
      expect(painted.map((p) => p.$1), ['faster', 'slower']);
      expect(painted[0].$2, map.fasterLabelColors);
      expect(painted[1].$2, map.slowerLabelColors);
      final bubble = map.alternateMarkers.value.singleWhere(
        (m) => m.markerId.value == 'navigation_engine_alternate_label_0',
      );
      final mid = alt.pointAt(math.min(300 + 400, (300 + alt.length) / 2));
      expect(bubble.position.latitude, closeTo(mid.lat, 1e-9));
      expect(bubble.position.longitude, closeTo(mid.lng, 1e-9));
      expect(bubble.anchor, const Offset(0.5, 1));
      bubble.onTap!();
      expect(taps, [0]);
    });

    test('the line is the alternate\'s own part: from 40 m before the '
        'divergence to 40 m after the rejoin (alternateLinePoints)', () {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final rejoining = AlternateRoute(
        route: alt,
        timeDelta: const Duration(minutes: -2),
        divergence: 300,
        rejoin: (alternate: alt.length - 300, current: 1000),
      );
      map.showAlternates([faster, rejoining], onTap: (_) {});
      List<gm.LatLng> points(int i) => map.alternatePolylines.value
          .singleWhere(
            (p) => p.polylineId.value == 'navigation_engine_alternate_$i',
          )
          .points;
      expect(points(0), [
        for (final p in alternateLinePoints(faster)) gm.LatLng(p.lat, p.lng),
      ]);
      expect(points(1), [
        for (final p in alternateLinePoints(rejoining)) gm.LatLng(p.lat, p.lng),
      ]);
      expect(points(0).length, lessThan(alt.points.length));
      final start = alt.pointAt(260);
      expect(points(0).first.latitude, closeTo(start.lat, 1e-9));
      expect(points(0).first.longitude, closeTo(start.lng, 1e-9));
      final end = alt.pointAt(alt.length - 260);
      expect(points(1).last.latitude, closeTo(end.lat, 1e-9));
      expect(points(1).last.longitude, closeTo(end.lng, 1e-9));
    });

    test('a tap on a line drawn for an older list is ignored', () {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final taps = <int>[];
      map.showAlternates([faster, slower], onTap: taps.add);
      gm.Polyline line(int i) => map.alternatePolylines.value.singleWhere(
        (p) => p.polylineId.value == 'navigation_engine_alternate_$i',
      );
      // The SDK still holds the old polylines for one round trip.
      final old = line(0).onTap!;
      map.showAlternates([slower, faster], onTap: taps.add);
      old();
      expect(taps, isEmpty, reason: 'index 0 is another route now');
      line(0).onTap!();
      expect(taps, [0]);
      final kept = line(1).onTap!;
      map.showAlternates([slower, faster], onTap: taps.add);
      kept();
      expect(taps, [0, 1], reason: 'the same route at index 1');
      map.clearAlternates();
      kept();
      expect(taps, [0, 1]);
    });

    test('clearAlternates removes them and drops a bubble render still '
        'pending', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final gate = Completer<Uint8List>();
      map
        ..alternateLabel = ((_) => 'x')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) => gate.future;
      map.showAlternates([faster], onTap: (_) {});
      map.clearAlternates();
      gate.complete(_pixel);
      await pumpEventQueue();
      expect(map.alternatePolylines.value, isEmpty);
      expect(map.alternateMarkers.value, isEmpty);
    });

    test(
      'a colour change restyles the lines; new bubble colours repaint',
      () async {
        final map = GoogleMapsNavigationMap();
        addTearDown(map.dispose);
        final painted = <RouteLabelColors>[];
        map
          ..alternateLabel = ((_) => 'x')
          ..labelPainter =
              (
                text, {
                required selected,
                required pixelRatio,
                required colors,
              }) async {
                painted.add(colors);
                return _pixel;
              };
        map.showAlternates([faster], onTap: (_) {});
        await pumpEventQueue();
        map.alternateColor = GoogleStyleColors.night.alternative;
        expect(
          map.alternatePolylines.value.single.color,
          GoogleStyleColors.night.alternative,
        );
        map.setAlternateLabelColors(
          faster: GoogleStyleColors.night.fasterLabelColors,
          slower: GoogleStyleColors.night.slowerLabelColors,
        );
        await pumpEventQueue();
        expect(painted.last, GoogleStyleColors.night.fasterLabelColors);
      },
    );
    test('a bubble sits at most 400 m past the divergence, near the car; '
        'a short alternate keeps it at the middle', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      map
        ..alternateLabel = ((a) => '${a.minutesDelta}')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) => Future.value(_pixel);
      // 3 km north: the middle after 300 m is 1650 m along, off screen at
      // follow zoom.
      final long = NavRoute.fromPoints([
        const GeoPoint(10.77, 106.70),
        offsetPoint(const GeoPoint(10.77, 106.70), 0, 3000),
      ]);
      // 500 m: the middle after 300 m is 400 m along, nearer than 700 m.
      final short = NavRoute.fromPoints([
        const GeoPoint(10.77, 106.70),
        offsetPoint(const GeoPoint(10.77, 106.70), 0, 500),
      ]);
      map.showAlternates([
        AlternateRoute(route: long, timeDelta: Duration.zero, divergence: 300),
        AlternateRoute(route: short, timeDelta: Duration.zero, divergence: 300),
      ], onTap: (_) {});
      await pumpEventQueue();
      gm.LatLng at(int i) => map.alternateMarkers.value
          .singleWhere(
            (m) => m.markerId.value == 'navigation_engine_alternate_label_$i',
          )
          .position;
      final ahead = long.pointAt(700);
      expect(at(0).latitude, closeTo(ahead.lat, 1e-9));
      expect(at(0).longitude, closeTo(ahead.lng, 1e-9));
      final mid = short.pointAt(400);
      expect(at(1).latitude, closeTo(mid.lat, 1e-9));
      expect(at(1).longitude, closeTo(mid.lng, 1e-9));
    });

    test('a re-show drops the older bubble render still pending', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final gate = Completer<Uint8List>();
      map
        ..alternateLabel = ((a) => a.minutesDelta < 0 ? 'old' : 'new')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) => text == 'old' ? gate.future : Future.value(_pixel);
      map.showAlternates([faster], onTap: (_) {});
      map.showAlternates([slower], onTap: (_) {});
      await pumpEventQueue();
      gate.complete(_pixel);
      await pumpEventQueue();
      final bubble = map.alternateMarkers.value.single;
      final mid = slower.route.pointAt(
        math.min(
          slower.divergence + 400,
          (slower.divergence + slower.route.length) / 2,
        ),
      );
      expect(bubble.position.latitude, closeTo(mid.lat, 1e-9));
      expect(bubble.position.longitude, closeTo(mid.lng, 1e-9));
    });

    test('during a re-show an old bubble still labelling the same route at '
        'its index keeps selecting it', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      var gate = Completer<Uint8List>()..complete(_pixel);
      map
        ..alternateLabel = ((a) => '${a.minutesDelta}')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) => gate.future;
      final taps = <int>[];
      map.showAlternates([faster, slower], onTap: taps.add);
      await pumpEventQueue();
      final old = {
        for (final m in map.alternateMarkers.value) m.markerId.value: m,
      };
      // The same routes in the same order, with new texts still rendering.
      gate = Completer<Uint8List>();
      map.alternateLabel = (a) => 'new ${a.minutesDelta}';
      map.showAlternates([faster, slower], onTap: taps.add);
      await pumpEventQueue();
      old['navigation_engine_alternate_label_1']!.onTap!();
      old['navigation_engine_alternate_label_0']!.onTap!();
      expect(taps, [1, 0]);
      gate.complete(_pixel);
      await pumpEventQueue();
    });

    test('during a re-show a stale bubble tap is ignored; the new bubbles '
        'select their own alternate', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      var gate = Completer<Uint8List>()..complete(_pixel);
      map
        ..alternateLabel = ((a) => '${a.minutesDelta}')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) => gate.future;
      final taps = <int>[];
      map.showAlternates([faster, slower], onTap: taps.add);
      await pumpEventQueue();
      final old = {
        for (final m in map.alternateMarkers.value) m.markerId.value: m,
      };
      // A new list, the other way round, whose bubbles are still rendering.
      gate = Completer<Uint8List>();
      map.alternateLabel = (a) => 'new ${a.minutesDelta}';
      map.showAlternates([slower, faster], onTap: taps.add);
      await pumpEventQueue();
      expect(map.alternateMarkers.value, isNotEmpty);
      old['navigation_engine_alternate_label_0']!.onTap!();
      old['navigation_engine_alternate_label_1']!.onTap!();
      expect(taps, isEmpty);
      gate.complete(_pixel);
      await pumpEventQueue();
      final fresh = {
        for (final m in map.alternateMarkers.value) m.markerId.value: m,
      };
      fresh['navigation_engine_alternate_label_1']!.onTap!();
      expect(taps, [1]);
    });

    test('bubbles consume their taps', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      map
        ..alternateLabel = ((_) => 'x')
        ..labelPainter = (
          text, {
          required selected,
          required pixelRatio,
          required colors,
        }) async => _pixel;
      map.showAlternates([faster], onTap: (_) {});
      await pumpEventQueue();
      expect(map.alternateMarkers.value.single.consumeTapEvents, isTrue);
    });

    test('a failed bubble render keeps the lines, drops the bubbles and is '
        'reported', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      var fail = false;
      map
        ..alternateLabel = ((a) => fail ? 'broken' : 'x')
        ..labelPainter =
            (
              text, {
              required selected,
              required pixelRatio,
              required colors,
            }) async {
              if (text == 'broken') throw StateError('no bubble');
              return _pixel;
            };
      map.showAlternates([faster], onTap: (_) {});
      await pumpEventQueue();
      expect(map.alternateMarkers.value, hasLength(1));
      fail = true;
      map.showAlternates([faster], onTap: (_) {});
      await pumpEventQueue();
      FlutterError.onError = previous;
      expect(map.alternatePolylines.value, hasLength(1));
      expect(map.alternateMarkers.value, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'navigation_engine_google_maps');
    });

    test('new label texts paint the shown bubbles again; the same texts do '
        'not (T10)', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final painted = <String>[];
      map
        ..alternateLabel = ((a) => 'en ${a.minutesDelta}')
        ..labelPainter =
            (text, {required selected, required pixelRatio, required colors}) {
              painted.add(text);
              return Future.value(_pixel);
            };
      map.showAlternates([faster], onTap: (_) {});
      await pumpEventQueue();
      expect(painted, ['en -2']);
      // A new closure with the same words: nothing to paint.
      map.alternateLabel = (a) => 'en ${a.minutesDelta}';
      await pumpEventQueue();
      expect(painted, ['en -2']);
      map.alternateLabel = (a) => 'vi ${a.minutesDelta}';
      await pumpEventQueue();
      expect(painted, ['en -2', 'vi -2']);
      expect(map.alternateMarkers.value, hasLength(1));
      map.alternateLabel = null;
      expect(map.alternateMarkers.value, isEmpty, reason: 'no bubbles');
    });

    test('a route width change redraws the alternates', () {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      map.showAlternates([faster], onTap: (_) {});
      map.routeColors = const RouteColors(aheadWidth: 20);
      expect(map.alternatePolylines.value.single.width, 14);
      expect(
        map.alternatePolylines.value.single.polylineId.value,
        'navigation_engine_alternate_0',
      );
    });
  });

  group('search pins', () {
    test('the map is a SearchPinsMap', () {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      expect(map, isA<SearchPinsMap>());
    });

    test(
      'one pin per place, the focused one on top; clear removes them',
      () async {
        final map = GoogleMapsNavigationMap();
        addTearDown(map.dispose);
        final focusedLog = <bool>[];
        map.pinPainter =
            ({
              required bool focused,
              required double pixelRatio,
              required Color color,
            }) async {
              focusedLog.add(focused);
              return _pixel;
            };
        final tapped = <AlongRoutePlace>[];
        await map.showSearchPins(
          [place, other],
          focusedId: 'b',
          onTap: tapped.add,
        );
        final markers = {
          for (final m in map.searchMarkers.value) m.markerId.value: m,
        };
        expect(markers.keys.toSet(), {
          'navigation_engine_search_a',
          'navigation_engine_search_b',
        });
        expect(
          markers['navigation_engine_search_b']!.zIndexInt,
          greaterThan(markers['navigation_engine_search_a']!.zIndexInt),
        );
        expect(
          markers['navigation_engine_search_a']!.anchor,
          const Offset(0.5, 1),
        );
        expect(focusedLog.toSet(), {true, false});
        markers['navigation_engine_search_a']!.onTap!();
        expect(tapped, [place]);
        map.clearSearchPins();
        expect(map.searchMarkers.value, isEmpty);
      },
    );

    test('a pin colour change paints the shown pins again (T10)', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final colors = <Color>[];
      map.pinPainter =
          ({
            required bool focused,
            required double pixelRatio,
            required Color color,
          }) async {
            colors.add(color);
            return _pixel;
          };
      final tapped = <AlongRoutePlace>[];
      await map.showSearchPins(
        [place, other],
        focusedId: 'b',
        onTap: tapped.add,
      );
      expect(colors.toSet(), {MapDefaultColors.searchPin});
      map.pinColor = GoogleStyleColors.night.warning;
      await pumpEventQueue();
      expect(colors.last, GoogleStyleColors.night.warning);
      final markers = {
        for (final m in map.searchMarkers.value) m.markerId.value: m,
      };
      expect(markers.keys.toSet(), {
        'navigation_engine_search_a',
        'navigation_engine_search_b',
      });
      expect(
        markers['navigation_engine_search_b']!.zIndexInt,
        greaterThan(markers['navigation_engine_search_a']!.zIndexInt),
        reason: 'the focus is kept',
      );
      markers['navigation_engine_search_a']!.onTap!();
      expect(tapped, [place], reason: 'the taps are kept');
      // Cleared pins are not painted again.
      map.clearSearchPins();
      final painted = colors.length;
      map.pinColor = GoogleStyleColors.day.warning;
      await pumpEventQueue();
      expect(colors, hasLength(painted));
      expect(map.searchMarkers.value, isEmpty);
    });

    test('a tap on a pin drawn for an older list reports only a place still '
        'shown, with the newest onTap', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      map.pinPainter = ({
        required bool focused,
        required double pixelRatio,
        required Color color,
      }) async => _pixel;
      final first = <AlongRoutePlace>[];
      final second = <AlongRoutePlace>[];
      await map.showSearchPins([place, other], onTap: first.add);
      gm.Marker pin(String id) => map.searchMarkers.value.singleWhere(
        (m) => m.markerId.value == 'navigation_engine_search_$id',
      );
      // The SDK still holds the old markers for one round trip.
      final oldA = pin('a').onTap!;
      final oldB = pin('b').onTap!;
      final pending = map.showSearchPins([other], onTap: second.add);
      oldA();
      oldB();
      expect(first, isEmpty);
      expect(second, [other]);
      await pending;
      final kept = pin('b').onTap!;
      map.clearSearchPins();
      kept();
      expect(second, [other]);
    });

    test('clearSearchPins drops a pin render still pending', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final gate = Completer<Uint8List>();
      map.pinPainter = ({
        required focused,
        required pixelRatio,
        required color,
      }) => gate.future;
      final shown = map.showSearchPins([place]);
      map.clearSearchPins();
      gate.complete(_pixel);
      await shown;
      expect(map.searchMarkers.value, isEmpty);
    });

    test('a newer call drops an older pin render still pending', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      var gate = Completer<Uint8List>();
      map.pinPainter = ({
        required focused,
        required pixelRatio,
        required color,
      }) => gate.future;
      final first = map.showSearchPins([place]);
      final older = gate;
      gate = Completer<Uint8List>()..complete(_pixel);
      await map.showSearchPins([other]);
      older.complete(_pixel);
      await first;
      expect(map.searchMarkers.value.map((m) => m.markerId.value), [
        'navigation_engine_search_b',
      ]);
    });

    test('pins consume their taps', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      map.pinPainter = ({
        required focused,
        required pixelRatio,
        required color,
      }) async => _pixel;
      await map.showSearchPins([place], onTap: (_) {});
      expect(map.searchMarkers.value.single.consumeTapEvents, isTrue);
    });

    test('a failed pin render clears the old pins and is reported', () async {
      final map = GoogleMapsNavigationMap();
      addTearDown(map.dispose);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      var fail = false;
      map.pinPainter =
          ({required focused, required pixelRatio, required color}) async {
            if (fail) throw StateError('no pin');
            return _pixel;
          };
      await map.showSearchPins([place, other]);
      expect(map.searchMarkers.value, hasLength(2));
      fail = true;
      await map.showSearchPins([other]);
      FlutterError.onError = previous;
      expect(map.searchMarkers.value, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'navigation_engine_google_maps');
    });

    testWidgets('paintSearchPin paints a PNG of the logical size times the '
        'ratio', (tester) async {
      final (normal, big) = (await tester.runAsync(
        () async => (
          await paintSearchPin(
            focused: false,
            pixelRatio: 2,
            color: const Color(0xFFD93025),
          ),
          await paintSearchPin(
            focused: true,
            pixelRatio: 2,
            color: const Color(0xFFD93025),
          ),
        ),
      ))!;
      int width(Uint8List png) =>
          ByteData.sublistView(png, 16, 20).getUint32(0);
      int height(Uint8List png) =>
          ByteData.sublistView(png, 20, 24).getUint32(0);
      expect(normal.sublist(1, 4), 'PNG'.codeUnits);
      expect((width(normal), height(normal)), (56, 72));
      expect(width(big), greaterThan(width(normal)));
    });
  });

  testWidgets('paintSearchPin keeps its whole 2 px outline inside the image', (
    tester,
  ) async {
    const red = Color(0xFFD93025);
    final pixels = (await tester.runAsync(() async {
      final png = await paintSearchPin(
        focused: false,
        pixelRatio: 1,
        color: red,
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData();
      frame.image.dispose();
      return data!;
    }))!;
    // The 28x36 pin is widest 14 px down: its left edge is the outline,
    // 2 px of white, not 1 px and then the fill.
    int alpha(int x, int y) => pixels.getUint8((y * 28 + x) * 4 + 3);
    int green(int x, int y) => pixels.getUint8((y * 28 + x) * 4 + 1);
    for (final x in [0, 1]) {
      expect(alpha(x, 14), greaterThan(200), reason: 'x $x is painted');
      expect(green(x, 14), greaterThan(200), reason: 'x $x is white');
    }
    // The top: 2 px of white above the fill too.
    for (final y in [0, 1]) {
      expect(green(14, y), greaterThan(200), reason: 'y $y is white');
    }
  });

  group('the view', () {
    late FakeGoogleMapsPlatform platform;
    late NavigationSession session;
    setUp(() {
      platform = FakeGoogleMapsPlatform();
      installFakeGoogleMapsPlatform(platform);
      session = NavigationSession(fixes: _Fixes());
    });

    Future<void> mount(WidgetTester tester, Widget view) async {
      await tester.pumpWidget(MaterialApp(home: view));
      platform.createView();
      await tester.pump();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    }

    testWidgets('traffic and map type reach the map, with the same view', (
      tester,
    ) async {
      GoogleMapsNavigationView view({bool traffic = false, gm.MapType? type}) =>
          GoogleMapsNavigationView(
            session: session,
            initialCenter: sampleRoute.points.first,
            trafficEnabled: traffic,
            mapType: type ?? gm.MapType.normal,
          );
      await mount(tester, view());
      expect(platform.mapConfiguration.trafficEnabled, isFalse);
      expect(platform.mapConfiguration.mapType, gm.MapType.normal);
      await tester.pumpWidget(
        MaterialApp(home: view(traffic: true, type: gm.MapType.hybrid)),
      );
      await tester.pump();
      expect(platform.mapConfiguration.trafficEnabled, isTrue);
      expect(platform.mapConfiguration.mapType, gm.MapType.hybrid);
      expect(platform.creationIds, hasLength(1));
      await unmount(tester);
    });

    testWidgets('horizontalFocus pads the map on the left', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mount(
        tester,
        GoogleMapsNavigationView(
          session: session,
          initialCenter: sampleRoute.points.first,
          horizontalFocus: 0.7,
        ),
      );
      expect(platform.mapConfiguration.padding!.left, closeTo(320, 0.5));
      await unmount(tester);
    });

    testWidgets('horizontalFocus is physical: in RTL the view does not mirror '
        'it, and a focus left of centre pads the map on the right', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(800, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget rtl(double focus) => Directionality(
        textDirection: TextDirection.rtl,
        child: GoogleMapsNavigationView(
          session: session,
          initialCenter: sampleRoute.points.first,
          horizontalFocus: focus,
        ),
      );
      await mount(tester, rtl(0.7));
      expect(platform.mapConfiguration.padding!.left, closeTo(320, 0.5));
      expect(platform.mapConfiguration.padding!.right, 0);
      // What a drop-in passes in RTL for a start-side panel: the right inset
      // keeps the map's logo clear of the panel.
      await tester.pumpWidget(MaterialApp(home: rtl(0.3)));
      await tester.pump();
      expect(platform.mapConfiguration.padding!.left, 0);
      expect(platform.mapConfiguration.padding!.right, closeTo(320, 0.5));
      await unmount(tester);
    });

    testWidgets('a flow\'s alternates draw under the route with bubbles; a '
        'tap switches the route', (tester) async {
      final flow = NavigationFlowController(
        session: session,
        nightMode: NightMode.alwaysDay,
      );
      await mount(
        tester,
        GoogleMapsNavigationView(
          session: session,
          initialCenter: sampleRoute.points.first,
          alternateLabel: (a) => '${a.minutesDelta} min',
          labelColors: GoogleStyleColors.night.routeLabelColors,
          alternateColor: GoogleStyleColors.night.alternative,
        ),
      );
      final map = session.map! as GoogleMapsNavigationMap;
      map.labelPainter = (
        text, {
        required selected,
        required pixelRatio,
        required colors,
      }) async => _pixel;
      flow.previewRoutes([sampleRoute, alt]);
      flow.start();
      await tester.pump();
      await tester.pump();
      gm.Polyline line(String id) =>
          platform.polylines.singleWhere((p) => p.polylineId.value == id);
      final alternate = line('navigation_engine_alternate_0');
      expect(
        alternate.zIndex,
        lessThan(line('navigation_engine_ahead').zIndex),
      );
      expect(alternate.color, GoogleStyleColors.night.alternative);
      expect(
        platform.markers.map((m) => m.markerId.value),
        contains('navigation_engine_alternate_label_0'),
      );
      alternate.onTap!();
      expect(session.route, same(alt));
      expect((flow.state.value as FlowNavigating).route, same(alt));
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      session.dispose();
    });

    testWidgets('search pins are drawn with the app markers, and cleared', (
      tester,
    ) async {
      await mount(
        tester,
        GoogleMapsNavigationView(
          session: session,
          initialCenter: sampleRoute.points.first,
        ),
      );
      final map = session.map! as GoogleMapsNavigationMap;
      map.pinPainter = ({
        required focused,
        required pixelRatio,
        required color,
      }) async => _pixel;
      await tester.runAsync(() => map.showSearchPins([place, other]));
      await tester.pump();
      expect(
        platform.markers.map((m) => m.markerId.value),
        containsAll([
          'navigation_engine_search_a',
          'navigation_engine_search_b',
        ]),
      );
      map.clearSearchPins();
      await tester.pump();
      expect(
        platform.markers.where(
          (m) => m.markerId.value.startsWith('navigation_engine_search_'),
        ),
        isEmpty,
      );
      await unmount(tester);
    });
  });
}
