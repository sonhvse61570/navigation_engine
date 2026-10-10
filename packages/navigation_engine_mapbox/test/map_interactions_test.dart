// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';
import 'package:navigation_engine_mapbox/src/mapbox_navigation_map.dart'
    show MapboxNavigationMapTesting, toGeoPoint;

import 'support/fake_mapbox_view.dart';
import 'support/recording_backend.dart';

typedef _Map = MapboxNavigationMap;

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

/// Lets the adapter and the fake backend finish their pending work: the
/// backend answers each call after a zero-delay timer, so a chain of calls
/// needs one event-loop turn per link.
Future<void> _settle() async {
  for (var turn = 0; turn < 200; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Uint8List _b(String s) => Uint8List.fromList(s.codeUnits);
String _text(Uint8List bytes) => String.fromCharCodes(bytes);

/// An east-west road at [lat], about 2.2 km long.
NavRoute _road(double lat) => NavRoute.fromPoints([
  GeoPoint(lat, 106.680),
  GeoPoint(lat, 106.690),
  GeoPoint(lat, 106.700),
]);

final _main = _road(10.770);
final _altA = _road(10.772);
final _altB = _road(10.774);
final _altC = _road(10.776);

AlternateRoute _alternate(NavRoute r, {int minutes = -2, double at = 100}) =>
    AlternateRoute(
      route: r,
      timeDelta: Duration(minutes: minutes),
      divergence: at,
    );

const _p1 = AlongRoutePlace(
  id: 'p1',
  name: 'Fuel',
  position: GeoPoint(10.771, 106.685),
);
const _p2 = AlongRoutePlace(
  id: 'p2',
  name: 'Coffee',
  position: GeoPoint(10.771, 106.690),
);
const _p3 = AlongRoutePlace(
  id: 'p3',
  name: 'Food',
  position: GeoPoint(10.771, 106.695),
);

String _bubbleText(AlternateRoute a) => a.minutesDelta < 0
    ? '${-a.minutesDelta} min faster'
    : '${a.minutesDelta} min slower';

String _optionText(NavRoute r) => identical(r, _main) ? 'main' : 'other';

/// Renders a bubble as `<text>/<sel|alt>`, recording each call; it can be
/// held back ([gate]) or made to fail ([error]).
class _LabelPainter {
  final calls = <(String, bool, double, RouteLabelColors)>[];
  Completer<void>? gate;
  Object? error;

  Future<Uint8List> call(
    String text, {
    required bool selected,
    required double pixelRatio,
    required RouteLabelColors colors,
  }) async {
    calls.add((text, selected, pixelRatio, colors));
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return _b('$text/${selected ? 'sel' : 'alt'}');
  }
}

/// Renders a search pin as `pin/<plain|focused>/<colour>`.
class _PinPainter {
  final calls = <(bool, double, Color)>[];
  Completer<void>? gate;
  Object? error;

  Future<Uint8List> call({
    required bool focused,
    required double pixelRatio,
    required Color color,
  }) async {
    calls.add((focused, pixelRatio, color));
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return _b('pin/${focused ? 'focused' : 'plain'}/${color.toARGB32()}');
  }
}

/// Renders the destination pin as `dest/<ratio>`.
class _DestinationPainter {
  final calls = <double>[];
  Completer<void>? gate;
  Object? error;

  Future<Uint8List> call({required double pixelRatio}) async {
    calls.add(pixelRatio);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return _b('dest/$pixelRatio');
  }
}

/// A map with engine-free painters on a backend.
class _Fixture {
  _Fixture() {
    map
      ..log = (_) {}
      ..labelPainter = labels.call
      ..pinPainter = pins.call
      ..destinationPinPainter = destination.call;
  }

  final backend = RecordingBackend();
  final map = _Map(vehicleImage: (_) async => _b('car'));
  final labels = _LabelPainter();
  final pins = _PinPainter();
  final destination = _DestinationPainter();
}

/// A fixture with its style loaded; the alternates get bubbles unless
/// [bubbles] is false.
Future<_Fixture> _loaded({bool bubbles = true, String? lightPreset}) async {
  final f = _Fixture();
  if (bubbles) f.map.alternateLabel = _bubbleText;
  f.map
    ..lightPreset = lightPreset
    ..attachBackend(f.backend);
  await f.map.onStyleLoaded();
  await _settle();
  return f;
}

List<Map<String, dynamic>> _features(RecordingBackend b, String source) =>
    ((b.sources[source]! as Map)['features'] as List)
        .cast<Map<String, dynamic>>();

List<double> _coords(Map<String, dynamic> feature) => [
  for (final n in (feature['geometry'] as Map)['coordinates'] as List)
    (n as num).toDouble(),
];

Object? _prop(Map<String, dynamic> feature, String key) =>
    (feature['properties'] as Map)[key];

Uint8List _bytes(RecordingBackend b, String id) =>
    (b.images[id]!.$2 as mb.StyleImageBytes).bytes;

/// The errors reported through [FlutterError] while the test runs.
List<FlutterErrorDetails> _reported() {
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = old);
  return errors;
}

/// The style ids of what the map owns besides the session's route layers.
const _extras = [
  _Map.alternatesLayer,
  _Map.alternateLabels,
  _Map.searchPins,
  _Map.destination,
];

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

/// A tap at [p] as the SDK hit-tests the alternates' line layer: a feature
/// that passes within 10 m of [p] is tapped (and the SDK reports the map
/// tap of the gesture too); elsewhere only the map is.
void _tapAt(RecordingBackend b, GeoPoint p) {
  final features = b.sources.containsKey(_Map.alternatesSource)
      ? _features(b, _Map.alternatesSource)
      : const <Map<String, dynamic>>[];
  for (final f in features) {
    final path = NavRoute.fromPoints([
      for (final c in (f['geometry'] as Map)['coordinates'] as List)
        GeoPoint(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
    ]);
    if (path.snap(p).offset < 10) {
      b
        ..tapFeature(_Map.alternatesLayer, properties: {'index': f['id']})
        ..tapMap(p);
      return;
    }
  }
  b.tapMap(p);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alternates', () {
    test('one line feature per alternate, under the route, grey and 70 % '
        'as wide', () async {
      final f = await _loaded(bubbles: false);
      final b = f.backend;
      f.map.showAlternates([
        _alternate(_altA),
        _alternate(_altB, minutes: 3),
      ], onTap: (_) {});
      await _settle();

      final lines = _features(b, _Map.alternatesSource);
      expect([for (final l in lines) _prop(l, 'index')], [0, 1]);
      expect([for (final l in lines) l['id']], [0, 1]);
      expect((lines[1]['geometry'] as Map)['type'], 'LineString');
      // Each line is the alternate's own part (alternateLinePoints): from
      // 40 m before its divergence (here 100 m) to its end.
      final start = _altB.pointAt(60);
      expect(((lines[1]['geometry'] as Map)['coordinates'] as List).first, [
        start.lng,
        start.lat,
      ]);
      expect((lines[1]['geometry'] as Map)['coordinates'], [
        for (final p in alternateLinePoints(_alternate(_altB, minutes: 3)))
          [p.lng, p.lat],
      ]);
      final layer = b.layer(_Map.alternatesLayer).layer as mb.LineLayer;
      expect(layer.sourceId, _Map.alternatesSource);
      expect(layer.lineColor, const Color(0xFF9AA0A6).toARGB32());
      expect(layer.lineWidth, closeTo(8 * 0.7, 1e-9));
      final ids = b.layerIds;
      expect(
        ids.indexOf(_Map.alternatesLayer),
        lessThan(ids.indexOf(_Map.drivenLayer)),
      );
      expect(ids, isNot(contains(_Map.alternateLabels)), reason: 'no label');
      expect(b.taps.keys, contains(_Map.alternatesLayer));
    });

    test('the lines sit under the route options, whichever comes '
        'first', () async {
      final f = await _loaded(bubbles: false);
      final b = f.backend;
      void lowest() {
        final ids = b.layerIds;
        final at = ids.indexOf(_Map.alternatesLayer);
        for (final id in ids) {
          if (id.startsWith(_Map.optionPrefix)) {
            expect(at, lessThan(ids.indexOf(id)), reason: id);
          }
        }
      }

      f.map.showRouteOptions([_main, _altA], 0);
      await _settle();
      f.map.showAlternates([_alternate(_altB)], onTap: (_) {});
      await _settle();
      lowest();
      // New routes are added again, below the session's route.
      f.map.showRouteOptions([_altC, _main], 1);
      await _settle();
      lowest();
      // A new selection reorders them in place.
      f.map.showRouteOptions([_altC, _main], 0);
      await _settle();
      lowest();
    });

    test('bubbles sit at min(divergence + 400 m, the middle of the rest), '
        'in the faster or slower colours, above the route and below the '
        'vehicle', () async {
      final f = await _loaded();
      final b = f.backend;
      const faster = RouteLabelColors(fill: Color(0xFF000001));
      const slower = RouteLabelColors(fill: Color(0xFF000002));
      f.map.setAlternateLabelColors(faster: faster, slower: slower);
      // A: 100 + 400 = 500 m (before the middle); B: the middle of the rest.
      f.map.showAlternates([
        _alternate(_altA, minutes: -2, at: 100),
        _alternate(_altB, minutes: 3, at: 1900),
      ], onTap: (_) {});
      await _settle();

      expect(
        [for (final c in f.labels.calls) (c.$1, c.$2, c.$3, c.$4)],
        [
          ('2 min faster', false, 3.0, faster),
          ('3 min slower', false, 3.0, slower),
        ],
      );
      final bubbles = _features(b, _Map.alternateLabels);
      expect(
        [for (final x in bubbles) _prop(x, 'image')],
        [_Map.alternateLabelImage(0), _Map.alternateLabelImage(1)],
      );
      final a = _altA.pointAt(500);
      final m = _altB.pointAt((1900 + _altB.length) / 2);
      expect(_coords(bubbles[0])[0], closeTo(a.lng, 1e-9));
      expect(_coords(bubbles[0])[1], closeTo(a.lat, 1e-9));
      expect(_coords(bubbles[1])[0], closeTo(m.lng, 1e-9));
      expect(_text(_bytes(b, _Map.alternateLabelImage(0))), '2 min faster/alt');
      expect(b.images[_Map.alternateLabelImage(1)]!.$1, 3);
      final layer = b.layer(_Map.alternateLabels).layer as mb.SymbolLayer;
      expect(layer.sourceId, _Map.alternateLabels);
      expect(layer.iconAnchor, mb.IconAnchor.BOTTOM);
      expect(layer.iconAllowOverlap, isTrue);
      final ids = b.layerIds;
      expect(
        ids.indexOf(_Map.alternateLabels),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.alternateLabels),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );
    });

    test('no label draws no bubbles; a label adds them; null removes them '
        '(the lines stay); the same label or a second null sends '
        'nothing', () async {
      final f = await _loaded(bubbles: false);
      final b = f.backend;
      f.map.showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.alternateLabels)));

      f.map.alternateLabel = _bubbleText;
      await _settle();
      expect(b.layerIds, contains(_Map.alternateLabels));

      b.calls.clear();
      f.map.alternateLabel = _bubbleText;
      await _settle();
      expect(b.calls, isEmpty, reason: 'the same texts');

      f.map.alternateLabel = null;
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(b.sources.keys, isNot(contains(_Map.alternateLabels)));
      expect(b.images.keys, isNot(contains(_Map.alternateLabelImage(0))));
      expect(b.layerIds, contains(_Map.alternatesLayer));

      b.calls.clear();
      f.map.alternateLabel = null;
      await _settle();
      expect(b.calls, isEmpty);
    });

    test('a tap on a line or a bubble calls onTap with its index', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      f.map.showAlternates([
        _alternate(_altA),
        _alternate(_altB),
      ], onTap: taps.add);
      await _settle();

      b.tapFeature(_Map.alternatesLayer, id: '1', properties: {'index': 1});
      b.tapFeature(_Map.alternateLabels, id: '0', properties: {'index': 0});
      // The id alone, as a double (the web reports numbers so).
      b.tapFeature(_Map.alternatesLayer, id: '1.0');
      expect(taps, [1, 0, 1]);
      b.tapFeature(_Map.alternatesLayer, id: '5', properties: {'index': 5});
      b.tapFeature(_Map.alternateLabels);
      expect(taps, [1, 0, 1]);
    });

    test('a tap on a line or a bubble drawn for an older list is '
        'ignored', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      void tap(String layer, int i) =>
          b.tapFeature(layer, id: '$i', properties: {'index': i});
      f.map.showAlternates([
        _alternate(_altA),
        _alternate(_altB),
      ], onTap: taps.add);
      await _settle();

      // C replaces A at 0; B stays at 1. The new bubbles wait.
      final gate = f.labels.gate = Completer<void>();
      f.map.showAlternates([
        _alternate(_altC, minutes: -5),
        _alternate(_altB),
      ], onTap: taps.add);
      // The lines are not drawn again yet.
      tap(_Map.alternatesLayer, 0);
      tap(_Map.alternatesLayer, 1);
      expect(taps, [1]);

      await _settle();
      // The lines are new; the bubbles are still the old ones.
      tap(_Map.alternatesLayer, 0);
      tap(_Map.alternateLabels, 0);
      tap(_Map.alternateLabels, 1);
      expect(taps, [1, 0, 1]);

      gate.complete();
      await _settle();
      tap(_Map.alternateLabels, 0);
      expect(taps, [1, 0, 1, 0]);
      expect(_text(_bytes(b, _Map.alternateLabelImage(0))), '5 min faster/alt');
    });

    test('a line ends 40 m after the rejoin', () async {
      final f = await _loaded(bubbles: false);
      final rejoining = AlternateRoute(
        route: _altA,
        timeDelta: Duration.zero,
        divergence: 100,
        rejoin: (alternate: 1500, current: 1500),
      );
      f.map.showAlternates([rejoining], onTap: (_) {});
      await _settle();
      final line =
          (_features(f.backend, _Map.alternatesSource).single['geometry']
                  as Map)['coordinates']
              as List;
      expect(line, [
        for (final p in alternateLinePoints(rejoining)) [p.lng, p.lat],
      ]);
      final end = _altA.pointAt(1540);
      expect(line.last, [end.lng, end.lat]);
    });

    test('a bubble lies on the drawn line: on a short detour, at the '
        'middle of the part that differs (alternateLabelDistance)', () async {
      final f = await _loaded();
      final (_, detour) = _sharedRoutes();
      final short = AlternateRoute(
        route: detour,
        timeDelta: Duration.zero,
        divergence: 1040,
        rejoin: (alternate: 1240, current: 1000),
      );
      f.map.showAlternates([short], onTap: (_) {});
      await _settle();
      final mid = detour.pointAt(1140);
      expect(_coords(_features(f.backend, _Map.alternateLabels).single), [
        mid.lng,
        mid.lat,
      ]);
    });

    test('an empty list clears them, as clearAlternates', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      f.map.showAlternates([_alternate(_altA)], onTap: taps.add);
      await _settle();
      f.map.showAlternates(const [], onTap: taps.add);
      await _settle();
      for (final id in [_Map.alternatesLayer, _Map.alternateLabels]) {
        expect(b.layerIds, isNot(contains(id)));
        expect(b.sources.keys, isNot(contains(id)));
      }
      expect(b.images.keys, isNot(contains(_Map.alternateLabelImage(0))));
    });

    test('a map built without colours has the shared defaults', () {
      final map = _Fixture().map;
      addTearDown(map.dispose);
      expect(map.labelColors, MapDefaultColors.routeLabels);
      expect(map.alternateColor, MapDefaultColors.alternate);
      expect(map.fasterLabelColors, MapDefaultColors.fasterLabels);
      expect(map.slowerLabelColors, MapDefaultColors.slowerLabels);
      expect(map.pinColor, MapDefaultColors.searchPin);
    });

    test('clearAlternates removes the lines, the bubbles, their sources '
        'and images; taps after it, or after dispose, are ignored', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      f.map.showAlternates([_alternate(_altA)], onTap: taps.add);
      await _settle();

      f.map.clearAlternates();
      // Still in the style until the update runs.
      b.tapFeature(_Map.alternatesLayer, properties: {'index': 0});
      b.tapFeature(_Map.alternateLabels, properties: {'index': 0});
      expect(taps, isEmpty);
      await _settle();
      for (final id in [_Map.alternatesLayer, _Map.alternateLabels]) {
        expect(b.layerIds, isNot(contains(id)));
        expect(b.sources.keys, isNot(contains(id)));
      }
      expect(b.images.keys, isNot(contains(_Map.alternateLabelImage(0))));

      f.map.showAlternates([_alternate(_altA)], onTap: taps.add);
      await _settle();
      f.map.dispose();
      b.tapFeature(_Map.alternatesLayer, properties: {'index': 0});
      b.tapFeature(_Map.alternateLabels, properties: {'index': 0});
      expect(taps, isEmpty);
    });

    test('a colour or route width change restyles the lines', () async {
      final f = await _loaded(bubbles: false);
      final b = f.backend;
      f.map.showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      mb.LineLayer line() =>
          b.layer(_Map.alternatesLayer).layer as mb.LineLayer;

      f.map.alternateColor = const Color(0xFF112233);
      await _settle();
      expect(line().lineColor, 0xFF112233);
      f.map.routeColors = const RouteColors(aheadWidth: 10);
      await _settle();
      expect(line().lineWidth, closeTo(7, 1e-9));
      expect(line().lineColor, 0xFF112233);
    });

    test('a failed bubble render removes the bubbles, keeps the lines and '
        'is reported', () async {
      final errors = _reported();
      final f = await _loaded();
      final b = f.backend;
      f.map.showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      expect(b.layerIds, contains(_Map.alternateLabels));

      f.labels.error = StateError('bubble');
      f.map.showAlternates([_alternate(_altA, minutes: -7)], onTap: (_) {});
      await _settle();
      expect(b.layerIds, contains(_Map.alternatesLayer));
      expect(b.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
    });
  });

  group('route option taps', () {
    test('a tap on an option line or label drawn for other routes than the '
        'option now at its index is ignored', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      f.map
        ..routeLabel = _optionText
        ..onRouteOptionTap = taps.add
        ..showRouteOptions([_main, _altA], 0);
      await _settle();
      b.tapFeature(_Map.optionLabels, id: '0', properties: {'index': 0});
      expect(taps, [0]);

      // C replaces the main route at 0; A stays at 1. Not drawn yet.
      f.map.showRouteOptions([_altC, _altA], 0);
      b
        ..tapFeature(_Map.optionLayer(0))
        ..tapFeature(_Map.optionCasingLayer(0))
        ..tapFeature(_Map.optionLabels, id: '0', properties: {'index': 0});
      expect(taps, [0], reason: 'drawn for the main route');
      b.tapFeature(_Map.optionLayer(1));
      expect(taps, [0, 1]);

      await _settle();
      b
        ..tapFeature(_Map.optionLayer(0))
        ..tapFeature(_Map.optionLabels, id: '0', properties: {'index': 0});
      expect(taps, [0, 1, 0, 0]);

      f.map.dispose();
      b.tapFeature(_Map.optionLayer(0));
      expect(taps, hasLength(4));
    });

    test('a label left over from other routes (its removal failed) is '
        'ignored while the new lines are drawn', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <int>[];
      f.map
        ..routeLabel = _optionText
        ..onRouteOptionTap = taps.add
        ..showRouteOptions([_main, _altA], 0);
      await _settle();

      // New routes: the new labels wait, and the old label layer stays.
      final gate = f.labels.gate = Completer<void>();
      b.failRemoveOf = _Map.optionLabels;
      f.map.showRouteOptions([_altC, _altB], 0);
      await _settle();
      expect(b.layerIds, contains(_Map.optionLabels));
      b
        ..tapFeature(_Map.optionLabels, id: '0', properties: {'index': 0})
        ..tapFeature(_Map.optionLabels, id: '1', properties: {'index': 1});
      expect(taps, isEmpty);
      b.tapFeature(_Map.optionLayer(1));
      expect(taps, [1], reason: 'the new lines are drawn');

      gate.complete();
      await _settle();
      b.tapFeature(_Map.optionLabels, id: '0', properties: {'index': 0});
      expect(taps, [1, 0]);
    });
  });

  group('search pins', () {
    test('one pin per place, the focused one last and larger, above the '
        'route and below the vehicle, anchored at the tip', () async {
      final f = await _loaded();
      final b = f.backend;
      await f.map.showSearchPins([_p1, _p2, _p3], focusedId: 'p2');
      await _settle();

      final warning = MapboxStyleColors.day.warning;
      expect(f.pins.calls, [(false, 3.0, warning), (true, 3.0, warning)]);
      final pins = _features(b, _Map.searchPins);
      expect([for (final p in pins) _prop(p, 'index')], [0, 2, 1]);
      expect(
        [for (final p in pins) _prop(p, 'image')],
        [_Map.searchPinImage, _Map.searchPinImage, _Map.searchPinFocusedImage],
      );
      expect(_coords(pins.first), [106.685, 10.771]);
      expect(
        _text(_bytes(b, _Map.searchPinFocusedImage)),
        'pin/focused/${warning.toARGB32()}',
      );
      expect(b.images[_Map.searchPinImage]!.$1, 3);
      final layer = b.layer(_Map.searchPins).layer as mb.SymbolLayer;
      expect(layer.sourceId, _Map.searchPins);
      expect(layer.iconAnchor, mb.IconAnchor.BOTTOM);
      expect(layer.symbolZOrder, mb.SymbolZOrder.SOURCE);
      final ids = b.layerIds;
      expect(
        ids.indexOf(_Map.searchPins),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.searchPins),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );
    });

    test('a tap reports the place drawn there while it is still shown, to '
        'the newest onTap', () async {
      final f = await _loaded();
      final b = f.backend;
      final tapped = <String>[];
      void tap(int i) =>
          b.tapFeature(_Map.searchPins, id: '$i', properties: {'index': i});
      await f.map.showSearchPins([
        _p1,
        _p2,
        _p3,
      ], onTap: (p) => tapped.add(p.id));
      await _settle();
      tap(2);
      expect(tapped, ['p3']);

      // A newer list reorders the places; until it is drawn, the pins
      // drawn keep their places.
      final reordered = f.map.showSearchPins(
        [_p3, _p1, _p2],
        focusedId: 'p3',
        onTap: (p) => tapped.add('new ${p.id}'),
      );
      tap(0);
      expect(tapped, ['p3', 'new p1']);
      await reordered;
      await _settle();
      tap(0);
      expect(tapped, ['p3', 'new p1', 'new p3']);

      // A newer list without p2: its old pin reports nothing.
      final fewer = f.map.showSearchPins([_p1], onTap: (p) => tapped.add('x'));
      tap(2);
      expect(tapped, hasLength(3));
      await fewer;
      await _settle();

      f.map.clearSearchPins();
      tap(0);
      expect(tapped, hasLength(3));
      await _settle();

      await f.map.showSearchPins([_p1], onTap: (p) => tapped.add('y'));
      await _settle();
      f.map.dispose();
      tap(0);
      expect(tapped, hasLength(3));
    });

    test('clear, and an empty list, remove the layer, the source and the '
        'images', () async {
      final f = await _loaded();
      final b = f.backend;
      void gone() {
        expect(b.layerIds, isNot(contains(_Map.searchPins)));
        expect(b.sources.keys, isNot(contains(_Map.searchPins)));
        expect(b.images.keys, isNot(contains(_Map.searchPinImage)));
        expect(b.images.keys, isNot(contains(_Map.searchPinFocusedImage)));
      }

      await f.map.showSearchPins([_p1]);
      await _settle();
      f.map.clearSearchPins();
      await _settle();
      gone();
      await f.map.showSearchPins([_p1]);
      await _settle();
      await f.map.showSearchPins([]);
      await _settle();
      gone();
    });

    test('a newer call or a clear drops a render still pending', () async {
      final f = await _loaded();
      final b = f.backend;
      final held = f.pins.gate = Completer<void>();
      final first = f.map.showSearchPins([_p1]);
      await _settle();
      f.pins.gate = null;
      await f.map.showSearchPins([_p2]);
      held.complete();
      await first;
      await _settle();
      expect(_features(b, _Map.searchPins), hasLength(1));
      expect(_coords(_features(b, _Map.searchPins).single), [106.690, 10.771]);

      final again = f.pins.gate = Completer<void>();
      final third = f.map.showSearchPins([_p3]);
      await _settle();
      f.map.clearSearchPins();
      again.complete();
      await third;
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.searchPins)));
    });

    test('a failed render clears the pins and is reported; the future '
        'completes', () async {
      final errors = _reported();
      final f = await _loaded();
      final b = f.backend;
      await f.map.showSearchPins([_p1]);
      await _settle();
      f.pins.error = StateError('pin');
      await f.map.showSearchPins([_p2]);
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.searchPins)));
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
    });

    test('a pinColor change paints the pins shown again (same places, focus '
        'and taps)', () async {
      final f = await _loaded();
      final b = f.backend;
      final tapped = <String>[];
      await f.map.showSearchPins(
        [_p1, _p2],
        focusedId: 'p1',
        onTap: (p) => tapped.add(p.id),
      );
      await _settle();
      f.pins.calls.clear();

      f.map.pinColor = const Color(0xFF00AA00);
      await _settle();
      expect({for (final c in f.pins.calls) c.$3}, {const Color(0xFF00AA00)});
      expect(
        [for (final p in _features(b, _Map.searchPins)) _prop(p, 'index')],
        [1, 0],
      );
      expect(_text(_bytes(b, _Map.searchPinImage)), 'pin/plain/${0xFF00AA00}');
      b.tapFeature(_Map.searchPins, properties: {'index': 0});
      expect(tapped, ['p1']);
    });
  });

  group('destination pin', () {
    const a = GeoPoint(10.78, 106.70);
    const c = GeoPoint(10.79, 106.71);

    test('drawn above the route and below the vehicle, anchored at its tip; '
        'moved; null removes it; rendered once per ratio', () async {
      final f = await _loaded();
      final b = f.backend;
      f.map.showDestinationPin(a);
      await _settle();
      final pin = _features(b, _Map.destination).single;
      expect(_coords(pin), [106.70, 10.78]);
      final layer = b.layer(_Map.destination).layer as mb.SymbolLayer;
      expect(layer.iconImage, _Map.destinationImage);
      expect(layer.iconAnchor, mb.IconAnchor.BOTTOM);
      expect(_text(_bytes(b, _Map.destinationImage)), 'dest/3.0');
      expect(b.images[_Map.destinationImage]!.$1, 3);
      final ids = b.layerIds;
      expect(
        ids.indexOf(_Map.destination),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.destination),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );

      f.map.showDestinationPin(c);
      await _settle();
      expect(_coords(_features(b, _Map.destination).single), [106.71, 10.79]);

      f.map.showDestinationPin(null);
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.destination)));
      expect(b.sources.keys, isNot(contains(_Map.destination)));
      expect(b.images.keys, isNot(contains(_Map.destinationImage)));

      f.map.showDestinationPin(a);
      await _settle();
      expect(b.layerIds, contains(_Map.destination));
      expect(f.destination.calls, [3.0], reason: 'once per ratio');
    });

    test('a newer call drops a render still pending', () async {
      final f = await _loaded();
      final b = f.backend;
      final held = f.destination.gate = Completer<void>();
      f.map.showDestinationPin(a);
      await _settle();
      f.map.showDestinationPin(c);
      held.complete();
      await _settle();
      expect(_coords(_features(b, _Map.destination).single), [106.71, 10.79]);

      final again = f.destination.gate = Completer<void>();
      f.map.pixelRatio = 2;
      f.map.showDestinationPin(a);
      await _settle();
      f.map.showDestinationPin(null);
      again.complete();
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.destination)));
    });

    test('a failed render removes the pin, is reported and is not '
        'kept', () async {
      final errors = _reported();
      final f = await _loaded();
      final b = f.backend;
      f.map.showDestinationPin(a);
      await _settle();
      f.destination.error = StateError('pin');
      f.map.pixelRatio = 2;
      f.map.showDestinationPin(c);
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.destination)));
      expect(errors, hasLength(1));

      f.destination.error = null;
      f.map.showDestinationPin(c);
      await _settle();
      expect(b.layerIds, contains(_Map.destination));
      expect(f.destination.calls, [3.0, 2.0, 2.0]);
    });

    test('the default painter is paintDestinationPin', () async {
      final backend = RecordingBackend();
      final map = _Map(vehicleImage: (_) async => _b('car'))
        ..log = (_) {}
        ..attachBackend(backend);
      await map.onStyleLoaded();
      map.showDestinationPin(a);
      await backend.imageAdded(_Map.destinationImage);
      expect(
        _bytes(backend, _Map.destinationImage),
        await paintDestinationPin(pixelRatio: 3),
      );
      map.dispose();
    });
  });

  group('order and reloads', () {
    // Each arrival draws one of the symbol layers (and the alternates' line).
    final arrivals = <String, Future<void> Function(_Map map)>{
      'pins': (m) => m.showSearchPins([_p1]),
      'destination': (m) async => m.showDestinationPin(_p2.position),
      'options': (m) async => m
        ..routeLabel = _optionText
        ..showRouteOptions([_main, _altA], 0),
      'alternates': (m) async =>
          m.showAlternates([_alternate(_altB)], onTap: (_) {}),
    };

    List<List<String>> orders(List<String> names) => names.length <= 1
        ? [names]
        : [
            for (final first in names)
              for (final rest in orders([
                for (final n in names)
                  if (n != first) n,
              ]))
                [first, ...rest],
          ];

    test('the layers keep their order whatever order they come in: the '
        'alternates, the options, the route, then the alternate bubbles, the '
        'option labels, the destination, the search pins and the '
        'vehicle', () async {
      for (final order in orders(arrivals.keys.toList())) {
        final f = await _loaded();
        for (final name in order) {
          await arrivals[name]!(f.map);
          await _settle();
        }
        expect(f.backend.layerIds, [
          _Map.alternatesLayer,
          _Map.optionCasingLayer(1),
          _Map.optionLayer(1),
          _Map.optionCasingLayer(0),
          _Map.optionLayer(0),
          _Map.drivenLayer,
          _Map.aheadLayer,
          _Map.alternateLabels,
          _Map.optionLabels,
          _Map.destination,
          _Map.searchPins,
          _Map.vehicleLayer,
        ], reason: order.join(', '));
        f.map.dispose();
      }
    });

    /// Everything drawn, with taps recorded.
    Future<(_Fixture, List<String>)> drawAll({String? lightPreset}) async {
      final f = await _loaded(lightPreset: lightPreset);
      final taps = <String>[];
      f.map
        ..routeLabel = _optionText
        ..onRouteOptionTap = ((i) => taps.add('option $i'))
        ..showRouteOptions([_main, _altA], 0)
        ..showAlternates([
          _alternate(_altB),
        ], onTap: (i) => taps.add('alternate $i'))
        ..showDestinationPin(_p3.position);
      await f.map.showSearchPins([_p1, _p2], onTap: (p) => taps.add(p.id));
      await _settle();
      return (f, taps);
    }

    Map<String, String> imagesOf(RecordingBackend b) => {
      for (final id in b.images.keys)
        id: '${b.images[id]!.$1} ${_text(_bytes(b, id))}',
    };

    test('a style reload draws everything again: the light preset first, '
        'the same layers, sources and images, and the taps still '
        'work', () async {
      final (f, taps) = await drawAll(lightPreset: 'night');
      final b = f.backend;
      for (final id in _extras) {
        expect(b.layerIds, contains(id));
      }
      final layers = List.of(b.layerIds);
      final sources = jsonEncode(b.sources);
      final images = imagesOf(b);

      b
        ..resetStyle()
        ..calls.clear();
      await f.map.onStyleLoaded();
      await _settle();
      expect(b.names.first, 'setStyleImportConfigProperty');
      expect(b.config[(_Map.basemapImport, 'lightPreset')], 'night');
      expect(b.layerIds, layers);
      expect(jsonEncode(b.sources), sources);
      expect(imagesOf(b), images);

      b
        ..tapFeature(_Map.optionLayer(1))
        ..tapFeature(_Map.alternatesLayer, properties: {'index': 0})
        ..tapFeature(_Map.alternateLabels, properties: {'index': 0})
        ..tapFeature(_Map.searchPins, properties: {'index': 1});
      expect(taps, ['option 1', 'alternate 0', 'alternate 0', 'p2']);
    });

    test('a light preset change keeps everything drawn: no reload', () async {
      final (f, _) = await drawAll(lightPreset: 'day');
      final b = f.backend;
      final layers = List.of(b.layerIds);
      b.calls.clear();
      f.map.lightPreset = 'night';
      await _settle();
      expect(b.names, ['setStyleImportConfigProperty']);
      expect(b.layerIds, layers);
      expect(b.config[(_Map.basemapImport, 'lightPreset')], 'night');
    });

    test('what is shown before the style loads is drawn once it '
        'loads', () async {
      final f = _Fixture();
      f.map
        ..alternateLabel = _bubbleText
        ..showAlternates([_alternate(_altA)], onTap: (_) {})
        ..showDestinationPin(_p2.position);
      final pins = f.map.showSearchPins([_p1]);
      await _settle();
      await pins;
      f.map.attachBackend(f.backend);
      await f.map.onStyleLoaded();
      await _settle();
      for (final id in _extras) {
        expect(f.backend.layerIds, contains(id));
      }
    });

    test('a failed style change draws what changed meanwhile into the old '
        'style', () async {
      final (f, _) = await drawAll();
      final b = f.backend;
      b.failOnce.add('loadStyleURI');
      f.map
        ..changeStyle('mapbox://styles/example/other')
        ..showDestinationPin(_p1.position);
      await _settle();
      expect(_coords(_features(b, _Map.destination).single), [106.685, 10.771]);
      await f.map.showSearchPins([_p3]);
      await _settle();
      expect(_coords(_features(b, _Map.searchPins).single), [106.695, 10.771]);
      for (final id in _extras) {
        expect(b.layerIds, contains(id));
      }
    });

    test('dispose drops pending renders and taps', () async {
      final f = await _loaded();
      final b = f.backend;
      final taps = <String>[];
      f.map.showAlternates([
        _alternate(_altA),
      ], onTap: (i) => taps.add('alternate $i'));
      await _settle();
      final gate = Completer<void>();
      f.labels.gate = gate;
      f.pins.gate = gate;
      f.destination.gate = gate;
      f.map
        ..showAlternates([
          _alternate(_altA, minutes: -9),
        ], onTap: (i) => taps.add('alternate $i'))
        ..showDestinationPin(_p2.position);
      final pins = f.map.showSearchPins([_p1], onTap: (p) => taps.add(p.id));
      await _settle();
      f.map.dispose();
      gate.complete();
      await pins;
      await _settle();
      expect(b.layerIds, isNot(contains(_Map.searchPins)));
      expect(b.layerIds, isNot(contains(_Map.destination)));
      expect(_text(_bytes(b, _Map.alternateLabelImage(0))), '2 min faster/alt');
      b
        ..tapFeature(_Map.alternatesLayer, properties: {'index': 0})
        ..tapFeature(_Map.alternateLabels, properties: {'index': 0});
      expect(taps, isEmpty);
    });
  });

  group('map taps', () {
    const p = GeoPoint(10.775, 106.69);
    const q = GeoPoint(10.776, 106.691);

    /// A map with every feature of its own drawn, on a backend.
    Future<(_Map, RecordingBackend, List<GeoPoint>, List<GeoPoint>)> drawn(
      WidgetTester tester,
    ) async {
      final f = _Fixture();
      final taps = <GeoPoint>[];
      final longs = <GeoPoint>[];
      f.map
        ..alternateLabel = _bubbleText
        ..routeLabel = _optionText
        ..onMapTap = taps.add
        ..onMapLongPress = longs.add
        ..attachBackend(f.backend);
      unawaited(f.map.onStyleLoaded());
      await tester.pump(Duration.zero);
      f.map
        ..showRouteOptions([_main, _altA], 0)
        ..showAlternates([_alternate(_altB)], onTap: (_) {})
        ..showDestinationPin(_p3.position);
      unawaited(f.map.showSearchPins([_p1]));
      await tester.pump(Duration.zero);
      for (final id in _extras) {
        expect(f.backend.layerIds, contains(id));
      }
      addTearDown(f.map.dispose);
      return (f.map, f.backend, taps, longs);
    }

    final kinds = <String, void Function(RecordingBackend b)>{
      'a route option line': (b) => b.tapFeature(_Map.optionLayer(1)),
      'a route option casing': (b) => b.tapFeature(_Map.optionCasingLayer(0)),
      'a route option label': (b) =>
          b.tapFeature(_Map.optionLabels, id: '1', properties: {'index': 1}),
      'an alternate line': (b) =>
          b.tapFeature(_Map.alternatesLayer, properties: {'index': 0}),
      'an alternate bubble': (b) =>
          b.tapFeature(_Map.alternateLabels, properties: {'index': 0}),
      'a search pin': (b) =>
          b.tapFeature(_Map.searchPins, properties: {'index': 0}),
      'the destination pin': (b) => b.tapFeature(_Map.destination),
    };

    testWidgets('a map tap reaches onMapTap one turn later, with its place; '
        'a long press at once', (tester) async {
      final (_, b, taps, longs) = await drawn(tester);
      b.tapMap(p);
      expect(taps, isEmpty, reason: 'held for one turn');
      await tester.pump(Duration.zero);
      expect(taps, [p]);
      b.longPressMap(q);
      expect(longs, [q]);
    });

    testWidgets('without callbacks a tap does nothing', (tester) async {
      final (map, b, _, _) = await drawn(tester);
      map
        ..onMapTap = null
        ..onMapLongPress = null;
      b
        ..tapMap(p)
        ..longPressMap(p);
      await tester.pump(Duration.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the callbacks are read when the tap is delivered', (
      tester,
    ) async {
      final (map, b, taps, _) = await drawn(tester);
      final later = <GeoPoint>[];
      b.tapMap(p);
      map.onMapTap = later.add;
      await tester.pump(Duration.zero);
      expect(taps, isEmpty);
      expect(later, [p]);
    });

    for (final MapEntry(key: kind, value: tapFeature) in kinds.entries) {
      testWidgets('$kind: the SDK\'s map tap after it, in its frame, is '
          'dropped', (tester) async {
        final (_, b, taps, _) = await drawn(tester);
        tapFeature(b);
        b.tapMap(p);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty);
      });

      testWidgets('$kind: the SDK\'s map tap before it, in its turn, is '
          'dropped', (tester) async {
        final (_, b, taps, _) = await drawn(tester);
        b.tapMap(p);
        tapFeature(b);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty);
      });

      testWidgets('$kind: a long press on it reaches onMapLongPress', (
        tester,
      ) async {
        final (_, b, _, longs) = await drawn(tester);
        tapFeature(b);
        b.longPressMap(q);
        expect(longs, [q]);
      });
    }

    testWidgets('a feature tap drops one map tap, in its frame only', (
      tester,
    ) async {
      final (_, b, taps, _) = await drawn(tester);
      kinds['a search pin']!(b);
      b
        ..tapMap(p)
        ..tapMap(q);
      await tester.pump(Duration.zero);
      expect(taps, [q]);

      kinds['a search pin']!(b);
      await tester.pump();
      b.tapMap(p);
      await tester.pump(Duration.zero);
      expect(taps, [q, p]);
    });

    testWidgets('a tap on the route where an alternate shares it is a map '
        'tap; a tap on the alternate\'s own part selects it', (tester) async {
      final f = _Fixture();
      final taps = <GeoPoint>[];
      final selected = <int>[];
      f.map
        ..onMapTap = taps.add
        ..attachBackend(f.backend);
      addTearDown(f.map.dispose);
      unawaited(f.map.onStyleLoaded());
      await tester.pump(Duration.zero);
      final (main, detour) = _sharedRoutes();
      f.map.showAlternates([
        AlternateRoute(
          route: detour,
          timeDelta: const Duration(minutes: -1),
          divergence: 1040,
          rejoin: (alternate: detour.length - 1040, current: 2000),
        ),
      ], onTap: selected.add);
      await tester.runAsync(_settle);
      for (final at in [main.pointAt(500), main.pointAt(2600)]) {
        _tapAt(f.backend, at);
        await tester.pump(Duration.zero);
        await tester.pump();
      }
      expect(selected, isEmpty);
      expect(taps, hasLength(2));
      _tapAt(f.backend, detour.pointAt(1800));
      await tester.pump(Duration.zero);
      expect(selected, [0]);
      expect(taps, hasLength(2));
    });

    testWidgets('a map tap still held when the map goes is dropped', (
      tester,
    ) async {
      final (map, b, taps, _) = await drawn(tester);
      b.tapMap(p);
      map.dispose();
      await tester.pump(Duration.zero);
      expect(taps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    test('each map adds its tap listeners once; taps from an earlier map '
        'are ignored', () async {
      final first = RecordingBackend();
      final second = RecordingBackend();
      final taps = <GeoPoint>[];
      final longs = <GeoPoint>[];
      final map = _Map(vehicleImage: (_) async => _b('car'))
        ..log = (_) {}
        ..onMapTap = taps.add
        ..onMapLongPress = longs.add
        ..attachBackend(first);
      await map.onStyleLoaded();
      await map.onStyleLoaded();
      expect(first.mapTapListeners, 1, reason: 'the map, not the style');
      map.attachBackend(second);
      first
        ..tapMap(p)
        ..longPressMap(p);
      second
        ..tapMap(q)
        ..longPressMap(q);
      await _settle();
      expect(taps, [q]);
      expect(longs, [q]);
      expect(second.mapTapListeners, 1);
      map.dispose();
    });

    test('toGeoPoint reads a Mapbox point (lng, lat)', () {
      expect(
        toGeoPoint(mb.Point(coordinates: mb.Position(106.7, 10.77))),
        const GeoPoint(10.77, 106.7),
      );
    });
  });

  group('the view', () {
    const p = GeoPoint(10.775, 106.69);

    Widget host(
      FakeMapboxViews views,
      MapboxNavigationView view, {
      TextDirection direction = TextDirection.ltr,
    }) => Directionality(
      textDirection: direction,
      child: Builder(builder: (context) => views.build(context, view)),
    );

    testWidgets('taps and long presses reach the view\'s callbacks; a '
        'feature tap is no map tap', (tester) async {
      final session = NavigationSession(fixes: _Fixes());
      addTearDown(session.dispose);
      final views = FakeMapboxViews();
      final taps = <GeoPoint>[];
      final longs = <GeoPoint>[];
      final options = <int>[];
      await tester.pumpWidget(
        host(
          views,
          MapboxNavigationView(
            session: session,
            initialCenter: p,
            onMapTap: taps.add,
            onMapLongPress: longs.add,
            onRouteOptionTap: options.add,
            vehicleImage: (_) async => _b('car'),
          ),
        ),
      );
      views
        ..createMap()
        ..loadStyle();
      await tester.pump(Duration.zero);
      views.tapMap(p);
      await tester.pump(Duration.zero);
      expect(taps, [p]);
      views.longPressMap(p);
      expect(longs, [p]);

      views.current.adapter.showRouteOptions([_main, _altA], 0);
      await tester.pump(Duration.zero);
      views.backend.tapFeature(_Map.optionLayer(1));
      views.tapMap(p);
      await tester.pump(Duration.zero);
      expect(options, [1]);
      expect(taps, [p]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    testWidgets('the alternate and pin parameters are forwarded; null keeps '
        'the map\'s own', (tester) async {
      final session = NavigationSession(fixes: _Fixes());
      addTearDown(session.dispose);
      final views = FakeMapboxViews();
      const faster = RouteLabelColors(fill: Color(0xFF000001));
      const slower = RouteLabelColors(fill: Color(0xFF000002));
      MapboxNavigationView view({bool colours = true}) => MapboxNavigationView(
        session: session,
        initialCenter: p,
        alternateLabel: colours ? _bubbleText : null,
        alternateColor: colours ? const Color(0xFF123456) : null,
        fasterLabelColors: colours ? faster : null,
        slowerLabelColors: colours ? slower : null,
        searchPinColor: colours ? const Color(0xFF654321) : null,
      );

      await tester.pumpWidget(host(views, view(colours: false)));
      final map = views.current.adapter;
      final defaults = alternateLabelColorsOf(MapboxStyleColors.day);
      expect(map.alternateLabel, isNull);
      expect(map.alternateColor, const Color(0xFF9AA0A6));
      expect(map.fasterLabelColors, defaults.faster);
      expect(map.slowerLabelColors, defaults.slower);
      expect(map.pinColor, MapboxStyleColors.day.warning);
      // The shared defaults of every adapter.
      expect(map.labelColors, MapDefaultColors.routeLabels);
      expect(map.alternateColor, MapDefaultColors.alternate);
      expect(map.fasterLabelColors, MapDefaultColors.fasterLabels);
      expect(map.slowerLabelColors, MapDefaultColors.slowerLabels);
      expect(map.pinColor, MapDefaultColors.searchPin);

      await tester.pumpWidget(host(views, view()));
      expect(map.alternateLabel, same(_bubbleText));
      expect(map.alternateColor, const Color(0xFF123456));
      expect(map.fasterLabelColors, faster);
      expect(map.slowerLabelColors, slower);
      expect(map.pinColor, const Color(0xFF654321));

      await tester.pumpWidget(host(views, view(colours: false)));
      expect(map.alternateLabel, isNull);
      expect(map.alternateColor, const Color(0xFF123456));
      expect(map.fasterLabelColors, faster);
      expect(map.slowerLabelColors, slower);
      expect(map.pinColor, const Color(0xFF654321));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    group('horizontalFocus', () {
      Future<(FakeMapboxViews, NavigationSession)> mount(
        WidgetTester tester,
        double focus, {
        TextDirection direction = TextDirection.ltr,
      }) async {
        tester.view
          ..physicalSize = const Size(800, 600)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final session = NavigationSession(fixes: _Fixes());
        addTearDown(session.dispose);
        final views = FakeMapboxViews();
        await tester.pumpWidget(
          host(
            views,
            MapboxNavigationView(
              session: session,
              initialCenter: p,
              horizontalFocus: focus,
              bottomInset: 40,
            ),
            direction: direction,
          ),
        );
        views.createMap();
        await tester.pump(Duration.zero);
        return (views, session);
      }

      Future<void> refocus(
        WidgetTester tester,
        FakeMapboxViews views,
        NavigationSession session,
        double focus,
      ) async {
        await tester.pumpWidget(
          host(
            views,
            MapboxNavigationView(
              session: session,
              initialCenter: p,
              horizontalFocus: focus,
              bottomInset: 40,
            ),
          ),
        );
        await tester.pump(Duration.zero);
      }

      mb.LogoSettings logo(FakeMapboxViews v) =>
          v.backend.argsOf('updateLogo').last! as mb.LogoSettings;
      mb.AttributionSettings attribution(FakeMapboxViews v) =>
          v.backend.argsOf('updateAttribution').last! as mb.AttributionSettings;

      Future<void> end(WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(Duration.zero);
      }

      testWidgets('forwarded to the frame; the camera insets move the '
          'focus', (tester) async {
        final (views, _) = await mount(tester, 0.75);
        final frame = tester.widget<NavigationMapFrame>(
          find.byType(NavigationMapFrame),
        );
        expect(frame.horizontalFocus, 0.75);
        final map = views.current.adapter;
        expect(map.padding.left, 400);
        expect(map.padding.right, 0);
        unawaited(
          map.moveCamera(
            const CameraTarget(position: p, bearing: 40, zoom: 17, tilt: 0),
          ),
        );
        await tester.pump(Duration.zero);
        final camera =
            views.backend.argsOf('setCamera').last! as mb.CameraOptions;
        expect(camera.padding!.left, 400);
        await end(tester);
      });

      testWidgets('centred: the logo bottom left and the attribution bottom '
          'right, 8 from the edges', (tester) async {
        final (views, _) = await mount(tester, 0.5);
        expect(logo(views).position, mb.OrnamentPosition.BOTTOM_LEFT);
        expect(logo(views).marginLeft, 8);
        expect(logo(views).marginBottom, 48);
        expect(attribution(views).position, mb.OrnamentPosition.BOTTOM_RIGHT);
        expect(attribution(views).marginRight, 8);
        expect(attribution(views).marginBottom, 48);
        await end(tester);
      });

      testWidgets('a panel on the left: the logo keeps clear of it', (
        tester,
      ) async {
        final (views, _) = await mount(tester, 0.75);
        expect(logo(views).marginLeft, 408);
        expect(attribution(views).marginRight, 8);
        await end(tester);
      });

      testWidgets('a panel on the right (a start-side panel in RTL): the '
          'attribution keeps clear of it', (tester) async {
        final (views, _) = await mount(
          tester,
          0.25,
          direction: TextDirection.rtl,
        );
        expect(attribution(views).marginRight, 408);
        expect(logo(views).marginLeft, 8);
        await end(tester);
      });

      testWidgets('a change places them again', (tester) async {
        final (views, session) = await mount(tester, 0.75);
        views.backend.calls.clear();
        await refocus(tester, views, session, 0.25);
        expect(views.backend.names, ['updateLogo', 'updateAttribution']);
        expect(logo(views).marginLeft, 8);
        expect(attribution(views).marginRight, 408);
        views.backend.calls.clear();
        await refocus(tester, views, session, 0.25);
        expect(views.backend.calls, isEmpty, reason: 'no change');
        await end(tester);
      });
    });
  });
}
