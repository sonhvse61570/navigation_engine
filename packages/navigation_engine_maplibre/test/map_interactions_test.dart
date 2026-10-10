// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';

import 'support/recording_platform.dart';

typedef _Map = MapLibreNavigationMap;

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

/// Lets the adapter's pending work run: the fake platform answers through
/// futures, not timers.
Future<void> _settle() => pumpEventQueue();

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

/// An east-west route at [lat], about 2.2 km long.
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
  position: GeoPoint(10.78, 106.69),
);
const _p2 = AlongRoutePlace(
  id: 'p2',
  name: 'Cafe',
  position: GeoPoint(10.79, 106.69),
);

/// Painters that answer with readable bytes and record their calls.
class _Painters {
  final labels = <(String, bool, RouteLabelColors)>[];
  final pins = <(bool, double, Color)>[];
  final destinations = <double>[];

  /// When set, label renders wait for it.
  Completer<void>? labelGate;

  /// When set, label renders fail.
  bool failLabels = false;

  /// When set, pin renders fail.
  bool failPins = false;

  /// When set, destination renders fail.
  bool failDestination = false;

  void install(MapLibreNavigationMap map) {
    map
      ..labelPainter = label
      ..pinPainter = pin
      ..destinationPinPainter = destination;
  }

  Future<Uint8List> label(
    String text, {
    required bool selected,
    required double pixelRatio,
    required RouteLabelColors colors,
  }) async {
    labels.add((text, selected, colors));
    final gate = labelGate;
    if (gate != null) await gate.future;
    if (failLabels) throw StateError('label');
    return _bytes(text);
  }

  Future<Uint8List> pin({
    required bool focused,
    required double pixelRatio,
    required Color color,
  }) async {
    pins.add((focused, pixelRatio, color));
    if (failPins) throw StateError('pin');
    return _bytes(focused ? 'focused' : 'pin');
  }

  Future<Uint8List> destination({required double pixelRatio}) async {
    destinations.add(pixelRatio);
    if (failDestination) throw StateError('destination');
    return _bytes('dest');
  }
}

/// A map with its style loaded on a fresh platform, its painters faked.
Future<(MapLibreNavigationMap, RecordingPlatform, _Painters)> _loaded() async {
  final platform = RecordingPlatform();
  final painters = _Painters();
  final map = MapLibreNavigationMap()
    ..log = <String>[].add
    ..onMapCreated(controllerOn(platform));
  painters.install(map);
  await map.onStyleLoaded();
  await _settle();
  return (map, platform, painters);
}

/// The reported Flutter errors until the end of the test.
List<FlutterErrorDetails> _captureErrors() {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

List<Map<String, dynamic>> _features(RecordingPlatform p, String source) => [
  for (final f in (p.sources[source]!['features'] as List))
    (f as Map).cast<String, dynamic>(),
];

List<double> _lngLat(GeoPoint p) => [p.lng, p.lat];

List<Object?> _coordinates(Map<String, dynamic> feature) =>
    (feature['geometry'] as Map)['coordinates'] as List<Object?>;

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
void _tapAt(RecordingPlatform platform, GeoPoint p) {
  final source = platform.sources[_Map.alternatesSource];
  for (final f
      in source == null
          ? const <Map<String, dynamic>>[]
          : _features(platform, _Map.alternatesSource)) {
    final path = NavRoute.fromPoints([
      for (final c in _coordinates(f).cast<List<Object?>>())
        GeoPoint(c[1]! as double, c[0]! as double),
    ]);
    if (path.snap(p).offset < 10) {
      platform
        ..tapFeature(_Map.alternatesLayer, id: f['id'])
        ..tapMap(ml.LatLng(p.lat, p.lng));
      return;
    }
  }
  platform.tapMap(ml.LatLng(p.lat, p.lng));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alternates', () {
    test('are one grey line layer under the route, 70 % as wide', () async {
      final (map, platform, _) = await _loaded();
      map.showAlternates([_alternate(_altA), _alternate(_altB)], onTap: (_) {});
      await _settle();
      final ids = platform.layerIds;
      expect(ids, contains(_Map.alternatesLayer));
      expect(
        ids.indexOf(_Map.alternatesLayer),
        lessThan(ids.indexOf(_Map.drivenLayer)),
      );
      final layer = platform.layer(_Map.alternatesLayer);
      expect(layer.kind, 'line');
      expect(layer.source, _Map.alternatesSource);
      expect(layer.interactive, isTrue);
      expect(layer.properties['line-color'], _hex(const Color(0xFF9AA0A6)));
      expect(layer.properties['line-width'], closeTo(8 * 0.7, 1e-9));
      final features = _features(platform, _Map.alternatesSource);
      expect([for (final f in features) f['id']], [0, 1]);
      // Each line is the alternate's own part (alternateLinePoints): from
      // 40 m before its divergence (here 100 m) to its end.
      expect(_coordinates(features[1]), [
        for (final p in alternateLinePoints(_alternate(_altB))) _lngLat(p),
      ]);
      expect(_coordinates(features[1]).first, _lngLat(_altB.pointAt(60)));
    });

    test('a line ends 40 m after the rejoin', () async {
      final (map, platform, _) = await _loaded();
      final rejoining = AlternateRoute(
        route: _altA,
        timeDelta: Duration.zero,
        divergence: 100,
        rejoin: (alternate: 1500, current: 1500),
      );
      map.showAlternates([rejoining], onTap: (_) {});
      await _settle();
      final line = _coordinates(
        _features(platform, _Map.alternatesSource).single,
      );
      expect(line, [
        for (final p in alternateLinePoints(rejoining)) _lngLat(p),
      ]);
      expect(line.last, _lngLat(_altA.pointAt(1540)));
    });

    test('a bubble lies on the drawn line: on a short detour, at the '
        'middle of the part that differs (alternateLabelDistance)', () async {
      final (map, platform, _) = await _loaded();
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
      await _settle();
      expect(
        _coordinates(_features(platform, _Map.alternateLabels).single),
        _lngLat(detour.pointAt(1140)),
      );
    });

    test('an empty list clears them, as clearAlternates', () async {
      final (map, platform, _) = await _loaded();
      final taps = <int>[];
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([_alternate(_altA)], onTap: taps.add);
      await _settle();
      map.showAlternates(const [], onTap: taps.add);
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.alternatesLayer)));
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(platform.sources, isNot(contains(_Map.alternatesSource)));
      expect(platform.sources, isNot(contains(_Map.alternateLabels)));
      platform
        ..tapFeature(_Map.alternatesLayer, id: 0)
        ..tapFeature(_Map.alternateLabels, id: 0);
      expect(taps, isEmpty);
    });

    test('bubbles sit at most 400 m past the divergence, else at the middle '
        'of the rest', () async {
      final (map, platform, painters) = await _loaded();
      map
        ..alternateLabel = ((a) => '${a.minutesDelta}')
        ..showAlternates([
          _alternate(_altA, minutes: -2, at: 100),
          _alternate(_altB, minutes: 3, at: 1800),
        ], onTap: (_) {});
      await _settle();
      final features = _features(platform, _Map.alternateLabels);
      expect(_coordinates(features[0]), _lngLat(_altA.pointAt(500)));
      expect(
        _coordinates(features[1]),
        _lngLat(_altB.pointAt((1800 + _altB.length) / 2)),
      );
      expect([for (final f in features) f['id']], [0, 1]);
      expect(platform.images[_Map.alternateLabelImage(0)], _bytes('-2'));
      expect(platform.images[_Map.alternateLabelImage(1)], _bytes('3'));
      // Faster and slower colours, never "selected".
      expect(painters.labels, [
        ('-2', false, map.fasterLabelColors),
        ('3', false, map.slowerLabelColors),
      ]);
      expect(map.fasterLabelColors, isNot(map.slowerLabelColors));
      final ids = platform.layerIds;
      expect(
        ids.indexOf(_Map.alternateLabels),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.alternateLabels),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );
      expect(platform.layer(_Map.alternateLabels).interactive, isTrue);
    });

    test('without alternateLabel there are no bubbles', () async {
      final (map, platform, painters) = await _loaded();
      map.showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(painters.labels, isEmpty);
    });

    test('a null alternateLabel removes the bubbles, and then changes '
        'nothing', () async {
      final (map, platform, _) = await _loaded();
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      map.alternateLabel = null;
      await _settle();
      expect(platform.layerIds, contains(_Map.alternatesLayer));
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      platform.calls.clear();
      map.alternateLabel = null;
      await _settle();
      expect(platform.calls, isEmpty);
    });

    test('a tap on a line or a bubble calls onTap with its index', () async {
      final (map, platform, _) = await _loaded();
      final taps = <int>[];
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([
          _alternate(_altA),
          _alternate(_altB),
        ], onTap: taps.add);
      await _settle();
      platform
        ..tapFeature(_Map.alternatesLayer, id: 1)
        ..tapFeature(_Map.alternateLabels, id: 0)
        // The SDK may report a numeric id as a double.
        ..tapFeature(_Map.alternateLabels, id: 1.0);
      expect(taps, [1, 0, 1]);
    });

    test('a tap on what an older list drew is ignored', () async {
      final (map, platform, painters) = await _loaded();
      final taps = <int>[];
      map
        ..alternateLabel = ((a) => a.route == _altC ? 'c' : 'ab')
        ..showAlternates([
          _alternate(_altA),
          _alternate(_altB),
        ], onTap: taps.add);
      await _settle();

      // A new list whose bubbles take a while: the old bubbles stay.
      painters.labelGate = Completer<void>();
      map.showAlternates([_alternate(_altC)], onTap: taps.add);
      // Not yet drawn: the old lines label other routes.
      platform.tapFeature(_Map.alternatesLayer, id: 0);
      await _settle();
      expect(_features(platform, _Map.alternateLabels), hasLength(2));
      platform
        ..tapFeature(_Map.alternateLabels, id: 0)
        ..tapFeature(_Map.alternateLabels, id: 1);
      expect(taps, isEmpty);

      // The new lines are drawn: a tap on one counts.
      platform.tapFeature(_Map.alternatesLayer, id: 0);
      expect(taps, [0]);

      painters.labelGate!.complete();
      await _settle();
      expect(_features(platform, _Map.alternateLabels), hasLength(1));
      platform.tapFeature(_Map.alternateLabels, id: 0);
      expect(taps, [0, 0]);
    });

    test('clearAlternates removes the lines, the bubbles and their '
        'sources', () async {
      final (map, platform, _) = await _loaded();
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      map.clearAlternates();
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.alternatesLayer)));
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(platform.sources, isNot(contains(_Map.alternatesSource)));
      expect(platform.sources, isNot(contains(_Map.alternateLabels)));
      final taps = <int>[];
      map.showAlternates([_alternate(_altB)], onTap: taps.add);
      map.clearAlternates();
      await _settle();
      platform.tapFeature(_Map.alternatesLayer, id: 0);
      expect(taps, isEmpty);
    });

    test('a new colour or route width restyles the line', () async {
      final (map, platform, _) = await _loaded();
      map.showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      platform.calls.clear();
      map.alternateColor = const Color(0xFF112233);
      await _settle();
      final (id, props) =
          platform.argsOf('setLayerProperties').single!
              as (String, Map<String, dynamic>);
      expect(id, _Map.alternatesLayer);
      expect(props['line-color'], '#112233');
      platform.calls.clear();
      map.routeColors = const RouteColors(aheadWidth: 10);
      await _settle();
      final widths = {
        for (final (id, props)
            in platform
                .argsOf('setLayerProperties')
                .cast<(String, Map<String, dynamic>)>())
          id: props['line-width'],
      };
      expect(widths[_Map.alternatesLayer], closeTo(7, 1e-9));
    });

    test('a failed bubble render keeps the lines, drops the bubbles and '
        'reports the error', () async {
      final errors = _captureErrors();
      final (map, platform, painters) = await _loaded();
      map
        ..alternateLabel = ((a) => 'x')
        ..showAlternates([_alternate(_altA)], onTap: (_) {});
      await _settle();
      painters.failLabels = true;
      map.alternateLabel = (a) => 'y';
      await _settle();
      expect(platform.layerIds, contains(_Map.alternatesLayer));
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(errors, hasLength(1));
    });
  });

  group('search pins', () {
    test('are a symbol layer above the route and below the vehicle, the '
        'focused one last and larger', () async {
      final (map, platform, painters) = await _loaded();
      await map.showSearchPins([_p1, _p2], focusedId: 'p1');
      await _settle();
      expect(platform.images[_Map.searchPinImage], _bytes('pin'));
      expect(platform.images[_Map.searchPinFocusedImage], _bytes('focused'));
      expect(painters.pins, [
        (false, 3.0, map.pinColor),
        (true, 3.0, map.pinColor),
      ]);
      final features = _features(platform, _Map.searchPins);
      expect([for (final f in features) f['id']], [1, 0]);
      expect(
        [for (final f in features) (f['properties'] as Map)['image']],
        [_Map.searchPinImage, _Map.searchPinFocusedImage],
      );
      expect(_coordinates(features[1]), _lngLat(_p1.position));
      final ids = platform.layerIds;
      expect(
        ids.indexOf(_Map.searchPins),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.searchPins),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );
      final layer = platform.layer(_Map.searchPins);
      expect(layer.interactive, isTrue);
      expect(layer.properties['icon-anchor'], 'bottom');
    });

    test('a tap on a pin calls onTap with its place', () async {
      final (map, platform, _) = await _loaded();
      final tapped = <AlongRoutePlace>[];
      await map.showSearchPins([_p1, _p2], onTap: tapped.add);
      await _settle();
      platform
        ..tapFeature(_Map.searchPins, id: 1)
        ..tapFeature(_Map.searchPins, id: 0.0);
      expect(tapped, [_p2, _p1]);
    });

    test('a tap on a pin drawn for an older list reports only a place still '
        'shown, with the newest onTap', () async {
      final (map, platform, _) = await _loaded();
      final first = <AlongRoutePlace>[];
      final second = <AlongRoutePlace>[];
      await map.showSearchPins([_p1, _p2], onTap: first.add);
      await _settle();
      // A new list: the style holds the old pins until it is drawn.
      final pending = map.showSearchPins([_p2], onTap: second.add);
      platform
        ..tapFeature(_Map.searchPins, id: 0)
        ..tapFeature(_Map.searchPins, id: 1);
      expect(first, isEmpty);
      expect(second, [_p2]);
      await pending;
      await _settle();
      // Cleared: the pin still drawn for a round trip reports nothing.
      map.clearSearchPins();
      platform.tapFeature(_Map.searchPins, id: 0);
      expect(second, [_p2]);
    });

    test('clearSearchPins and an empty list remove them', () async {
      final (map, platform, _) = await _loaded();
      await map.showSearchPins([_p1]);
      await _settle();
      map.clearSearchPins();
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.searchPins)));
      expect(platform.sources, isNot(contains(_Map.searchPins)));

      await map.showSearchPins([_p1]);
      await _settle();
      expect(platform.layerIds, contains(_Map.searchPins));
      await map.showSearchPins(const []);
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.searchPins)));
    });

    test('a newer call drops a pin render still pending', () async {
      final (map, platform, _) = await _loaded();
      final first = map.showSearchPins([_p1]);
      map.clearSearchPins();
      await first;
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.searchPins)));
    });

    test('a failed render clears the pins and reports the error', () async {
      final errors = _captureErrors();
      final (map, platform, painters) = await _loaded();
      await map.showSearchPins([_p1]);
      await _settle();
      painters.failPins = true;
      await map.showSearchPins([_p2]);
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.searchPins)));
      expect(errors, hasLength(1));
    });

    test('a new pin colour paints the pins shown again', () async {
      final (map, platform, painters) = await _loaded();
      final tapped = <AlongRoutePlace>[];
      await map.showSearchPins([_p1], onTap: tapped.add);
      await _settle();
      map.pinColor = const Color(0xFF00FF00);
      await _settle();
      expect(painters.pins.last, (true, 3.0, const Color(0xFF00FF00)));
      platform.tapFeature(_Map.searchPins, id: 0);
      expect(tapped, [_p1]);
    });
  });

  group('destination pin', () {
    test('is a symbol layer above the route and below the vehicle', () async {
      final (map, platform, painters) = await _loaded();
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await _settle();
      expect(platform.images[_Map.destinationImage], _bytes('dest'));
      expect(painters.destinations, [3.0]);
      final features = _features(platform, _Map.destination);
      expect(_coordinates(features.single), [106.7, 10.8]);
      final ids = platform.layerIds;
      expect(
        ids.indexOf(_Map.destination),
        greaterThan(ids.indexOf(_Map.aheadLayer)),
      );
      expect(
        ids.indexOf(_Map.destination),
        lessThan(ids.indexOf(_Map.vehicleLayer)),
      );
      final layer = platform.layer(_Map.destination);
      expect(layer.interactive, isTrue);
      expect(layer.properties['icon-anchor'], 'bottom');
      expect(layer.properties['icon-image'], _Map.destinationImage);
    });

    test('moves, and null removes it; the image is rendered once', () async {
      final (map, platform, painters) = await _loaded();
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await _settle();
      map.showDestinationPin(const GeoPoint(10.9, 106.6));
      await _settle();
      expect(_coordinates(_features(platform, _Map.destination).single), [
        106.6,
        10.9,
      ]);
      expect(painters.destinations, [3.0]);
      map.showDestinationPin(null);
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.destination)));
      expect(platform.sources, isNot(contains(_Map.destination)));
      // A tap on a pin no longer drawn does not throw.
      platform.tapFeature(_Map.destination, id: 0);
    });

    test('a newer call drops a render still pending', () async {
      final (map, platform, _) = await _loaded();
      map
        ..showDestinationPin(const GeoPoint(10.8, 106.7))
        ..showDestinationPin(null);
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.destination)));
    });

    test('a failed render removes the pin and reports the error', () async {
      final errors = _captureErrors();
      final (map, platform, painters) = await _loaded();
      painters.failDestination = true;
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.destination)));
      expect(errors, hasLength(1));
    });

    test('the default painter is paintDestinationPin', () async {
      final platform = RecordingPlatform();
      final map = MapLibreNavigationMap()
        ..log = <String>[].add
        ..onMapCreated(controllerOn(platform))
        ..pixelRatio = 2;
      await map.onStyleLoaded();
      map.showDestinationPin(const GeoPoint(10.8, 106.7));
      await platform.imageAdded(_Map.destinationImage);
      expect(
        platform.images[_Map.destinationImage],
        await paintDestinationPin(pixelRatio: 2),
      );
    });
  });

  group('order and style reloads', () {
    test(
      'symbol layers: alternate bubbles, route labels, destination, '
      'search pins, then the vehicle, whatever the order they come in',
      () async {
        final (map, platform, _) = await _loaded();
        map
          ..routeLabel = ((r) => 'r')
          ..alternateLabel = ((a) => 'a');
        await map.showSearchPins([_p1]);
        await _settle();
        map.showDestinationPin(const GeoPoint(10.8, 106.7));
        await _settle();
        map.showRouteOptions([_main, _altA], 0);
        await _settle();
        map.showAlternates([_alternate(_altB)], onTap: (_) {});
        await _settle();
        final ids = platform.layerIds;
        expect(ids.sublist(ids.indexOf(_Map.aheadLayer)), [
          _Map.aheadLayer,
          _Map.alternateLabels,
          _Map.optionLabels,
          _Map.destination,
          _Map.searchPins,
          _Map.vehicleLayer,
        ]);
        expect(
          ids.indexOf(_Map.alternatesLayer),
          lessThan(ids.indexOf(_Map.drivenLayer)),
        );
      },
    );

    test('every layer, source and image comes back after a style '
        'reload', () async {
      final (map, platform, _) = await _loaded();
      final taps = <int>[];
      final tapped = <AlongRoutePlace>[];
      map
        ..routeLabel = ((r) => 'r')
        ..alternateLabel = ((a) => 'a')
        ..showRouteOptions([_main, _altA], 0)
        ..showAlternates([_alternate(_altB)], onTap: taps.add)
        ..showDestinationPin(const GeoPoint(10.8, 106.7));
      await map.showSearchPins([_p1], onTap: tapped.add);
      await _settle();
      final layers = List.of(platform.layerIds);
      final sources = {
        for (final e in platform.sources.entries) e.key: e.value,
      };
      final images = Map.of(platform.images);

      platform.reloadStyle();
      map.onStyleChanging();
      await map.onStyleLoaded();
      await _settle();
      expect(platform.layerIds, layers);
      expect(platform.sources, sources);
      expect(platform.images, images);

      platform
        ..tapFeature(_Map.alternatesLayer, id: 0)
        ..tapFeature(_Map.alternateLabels, id: 0)
        ..tapFeature(_Map.searchPins, id: 0);
      expect(taps, [0, 0]);
      expect(tapped, [_p1]);
    });

    test('shown before the style loads, they are drawn once it has', () async {
      final platform = RecordingPlatform();
      final painters = _Painters();
      final map = MapLibreNavigationMap()
        ..log = <String>[].add
        ..onMapCreated(controllerOn(platform));
      painters.install(map);
      map
        ..alternateLabel = ((a) => 'a')
        ..showAlternates([_alternate(_altB)], onTap: (_) {})
        ..showDestinationPin(const GeoPoint(10.8, 106.7));
      await map.showSearchPins([_p1]);
      await _settle();
      expect(platform.layers, isEmpty);
      await map.onStyleLoaded();
      await _settle();
      expect(
        platform.layerIds,
        containsAll(<String>[
          _Map.alternatesLayer,
          _Map.alternateLabels,
          _Map.destination,
          _Map.searchPins,
        ]),
      );
    });

    test('dispose drops pending renders and taps', () async {
      final (map, platform, painters) = await _loaded();
      final taps = <int>[];
      painters.labelGate = Completer<void>();
      map
        ..alternateLabel = ((a) => 'a')
        ..showAlternates([_alternate(_altB)], onTap: taps.add)
        ..showDestinationPin(const GeoPoint(10.8, 106.7))
        ..dispose();
      painters.labelGate!.complete();
      await _settle();
      expect(platform.layerIds, isNot(contains(_Map.alternateLabels)));
      expect(platform.layerIds, isNot(contains(_Map.destination)));
    });
  });

  group('the view', () {
    late RecordingPlatform platform;

    setUp(() => platform = RecordingPlatform());

    Future<MapLibreNavigationMap> mount(
      WidgetTester tester, {
      void Function(GeoPoint)? onMapTap,
      void Function(GeoPoint)? onMapLongPress,
      double horizontalFocus = 0.5,
      double bottomInset = 0,
      TextDirection direction = TextDirection.ltr,
      String Function(AlternateRoute)? alternateLabel,
      Color? alternateColor,
      RouteLabelColors? fasterLabelColors,
      RouteLabelColors? slowerLabelColors,
      Color? searchPinColor,
      NavigationSession? session,
    }) async {
      installRecordingPlatform(platform);
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = session ?? (NavigationSession(fixes: _Fixes())..start());
      if (session == null) addTearDown(s.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: MapLibreNavigationView(
            session: s,
            styleString: 'day.json',
            initialCenter: _main.points.first,
            vehicleImage: (_) async => Uint8List(4),
            onMapTap: onMapTap,
            onMapLongPress: onMapLongPress,
            horizontalFocus: horizontalFocus,
            bottomInset: bottomInset,
            alternateLabel: alternateLabel,
            alternateColor: alternateColor,
            fasterLabelColors: fasterLabelColors,
            slowerLabelColors: slowerLabelColors,
            searchPinColor: searchPinColor,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = s.map! as MapLibreNavigationMap;
      map.log = <String>[].add;
      _Painters().install(map);
      return map;
    }

    Future<void> loadStyle(
      WidgetTester tester,
      MapLibreNavigationMap map,
    ) async {
      unawaited(map.onStyleLoaded());
      await tester.pump();
      await tester.pump();
    }

    const at = ml.LatLng(10.5, 106.25);
    const atPoint = GeoPoint(10.5, 106.25);

    testWidgets('a tap and a long press reach onMapTap and onMapLongPress', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      await mount(tester, onMapTap: taps.add, onMapLongPress: presses.add);
      platform
        ..tapMap(at)
        ..longPressMap(const ml.LatLng(-33.75, 151.125));
      // A long press at once; a tap after one turn of the event loop.
      expect(presses, [const GeoPoint(-33.75, 151.125)]);
      expect(taps, isEmpty);
      await tester.pump(Duration.zero);
      expect(taps, [atPoint]);
    });

    testWidgets('without the callbacks a tap and a long press do nothing', (
      tester,
    ) async {
      await mount(tester);
      platform
        ..tapMap(at)
        ..longPressMap(at);
      await tester.pump(Duration.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the callbacks are read when a tap comes', (tester) async {
      final first = <GeoPoint>[];
      final second = <GeoPoint>[];
      final session = NavigationSession(fixes: _Fixes())..start();
      addTearDown(session.dispose);
      await mount(
        tester,
        session: session,
        onMapTap: first.add,
        onMapLongPress: first.add,
      );
      await mount(
        tester,
        session: session,
        onMapTap: second.add,
        onMapLongPress: second.add,
      );
      platform
        ..tapMap(at)
        ..longPressMap(at);
      await tester.pump(Duration.zero);
      expect(first, isEmpty);
      expect(second, [atPoint, atPoint]);
    });

    /// Mounts a view whose map shows every feature the library draws.
    Future<MapLibreNavigationMap> mountFeatures(
      WidgetTester tester, {
      required List<GeoPoint> taps,
      required List<GeoPoint> presses,
    }) async {
      final map = await mount(
        tester,
        onMapTap: taps.add,
        onMapLongPress: presses.add,
        alternateLabel: (a) => 'a',
      );
      await loadStyle(tester, map);
      map
        ..routeLabel = ((r) => 'r')
        ..showRouteOptions([_main, _altA], 0)
        ..showAlternates([_alternate(_altB)], onTap: (_) {})
        ..showDestinationPin(const GeoPoint(10.8, 106.7));
      await map.showSearchPins([_p1]);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(
        platform.layerIds,
        containsAll(<String>[
          _Map.optionLayer(1),
          _Map.optionLabels,
          _Map.alternatesLayer,
          _Map.alternateLabels,
          _Map.searchPins,
          _Map.destination,
        ]),
      );
      return map;
    }

    final features = <(String, Object?)>[
      (_Map.optionLayer(1), null),
      (_Map.optionCasingLayer(0), null),
      (_Map.optionLabels, 1),
      (_Map.alternatesLayer, 0),
      (_Map.alternateLabels, 0),
      (_Map.searchPins, 0),
      (_Map.destination, 0),
    ];

    testWidgets('the map tap of a feature tap\'s gesture does not reach '
        'onMapTap, in either order; a long press always does', (tester) async {
      final taps = <GeoPoint>[];
      final presses = <GeoPoint>[];
      await mountFeatures(tester, taps: taps, presses: presses);
      for (final (layer, id) in features) {
        // The feature tap first (the order the SDKs report in).
        platform
          ..tapFeature(layer, id: id)
          ..tapMap(at);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty, reason: '$layer, then the map');
        await tester.pump();

        // The map tap first.
        platform
          ..tapMap(at)
          ..tapFeature(layer, id: id);
        await tester.pump(Duration.zero);
        expect(taps, isEmpty, reason: 'the map, then $layer');
        await tester.pump();

        platform
          ..tapFeature(layer, id: id)
          ..longPressMap(at);
        expect(presses, hasLength(1), reason: layer);
        presses.clear();
        await tester.pump();
      }
    });

    testWidgets('a feature tap drops one map tap, in its frame only', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      await mountFeatures(tester, taps: taps, presses: []);
      platform
        ..tapFeature(_Map.searchPins, id: 0)
        ..tapMap(at)
        ..tapMap(const ml.LatLng(1, 2));
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(1, 2)]);

      platform.tapFeature(_Map.destination, id: 0);
      await tester.pump();
      platform.tapMap(at);
      await tester.pump(Duration.zero);
      expect(taps, [const GeoPoint(1, 2), atPoint]);
    });

    testWidgets('a tap on a layer the library does not own is no feature '
        'tap', (tester) async {
      final taps = <GeoPoint>[];
      await mountFeatures(tester, taps: taps, presses: []);
      platform
        ..tapFeature('app_layer', id: 3)
        ..tapMap(at);
      await tester.pump(Duration.zero);
      expect(taps, [atPoint]);
    });

    testWidgets('a tap on the route where an alternate shares it is a map '
        'tap; a tap on the alternate\'s own part selects it', (tester) async {
      final taps = <GeoPoint>[];
      final selected = <int>[];
      final map = await mount(tester, onMapTap: taps.add);
      await loadStyle(tester, map);
      final (main, detour) = _sharedRoutes();
      map.showAlternates([
        AlternateRoute(
          route: detour,
          timeDelta: const Duration(minutes: -1),
          divergence: 1040,
          rejoin: (alternate: detour.length - 1040, current: 2000),
        ),
      ], onTap: selected.add);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      for (final p in [main.pointAt(500), main.pointAt(2600)]) {
        _tapAt(platform, p);
        await tester.pump(Duration.zero);
        await tester.pump();
      }
      expect(selected, isEmpty);
      expect(taps, hasLength(2));
      _tapAt(platform, detour.pointAt(1800));
      await tester.pump(Duration.zero);
      expect(selected, [0]);
      expect(taps, hasLength(2));
    });

    testWidgets('a map built without colours has the shared defaults', (
      tester,
    ) async {
      for (final map in [await mount(tester), MapLibreNavigationMap()]) {
        expect(map.labelColors, MapDefaultColors.routeLabels);
        expect(map.alternateColor, MapDefaultColors.alternate);
        expect(map.fasterLabelColors, MapDefaultColors.fasterLabels);
        expect(map.slowerLabelColors, MapDefaultColors.slowerLabels);
        expect(map.pinColor, MapDefaultColors.searchPin);
      }
    });

    testWidgets('a map tap still held when the view goes is dropped', (
      tester,
    ) async {
      final taps = <GeoPoint>[];
      await mount(tester, onMapTap: taps.add);
      platform.tapMap(at);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      expect(taps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('forwards the alternate and pin parameters to the map', (
      tester,
    ) async {
      String label(AlternateRoute a) => 'a';
      const faster = RouteLabelColors(text: Color(0xFF00AA00));
      const slower = RouteLabelColors(text: Color(0xFF777777));
      final map = await mount(
        tester,
        alternateLabel: label,
        alternateColor: const Color(0xFF123456),
        fasterLabelColors: faster,
        slowerLabelColors: slower,
        searchPinColor: const Color(0xFF654321),
      );
      expect(map.alternateLabel, same(label));
      expect(map.alternateColor, const Color(0xFF123456));
      expect(map.fasterLabelColors, faster);
      expect(map.slowerLabelColors, slower);
      expect(map.pinColor, const Color(0xFF654321));
    });

    testWidgets('null colours keep the map\'s own', (tester) async {
      final map = await mount(tester);
      final fresh = MapLibreNavigationMap();
      expect(map.alternateColor, fresh.alternateColor);
      expect(map.fasterLabelColors, fresh.fasterLabelColors);
      expect(map.slowerLabelColors, fresh.slowerLabelColors);
      expect(map.pinColor, fresh.pinColor);
    });

    group('horizontalFocus', () {
      Object? last(String name) => [
        (platform.creationParams.first['options'] as Map)[name],
        for (final update in platform.argsOf('updateMapOptions'))
          if ((update! as Map).containsKey(name)) (update as Map)[name],
      ].last;

      testWidgets('reaches the frame and moves the camera insets', (
        tester,
      ) async {
        final map = await mount(tester, horizontalFocus: 0.75);
        expect(
          tester
              .widget<NavigationMapFrame>(find.byType(NavigationMapFrame))
              .horizontalFocus,
          0.75,
        );
        expect(map.padding.left, closeTo(200, 1e-9));
        expect(map.padding.right, 0);
      });

      testWidgets('the logo keeps clear of a panel on the left', (
        tester,
      ) async {
        await mount(tester, horizontalFocus: 0.75, bottomInset: 50);
        expect(last('logoViewMargins'), [208, 58]);
        expect(last('attributionButtonMargins'), [8, 58]);
      });

      testWidgets('the attribution keeps clear of a panel on the right '
          '(right to left)', (tester) async {
        await mount(
          tester,
          horizontalFocus: 0.25,
          direction: TextDirection.rtl,
        );
        expect(last('logoViewMargins'), [8, 8]);
        expect(last('attributionButtonMargins'), [208, 8]);
      });

      testWidgets('centred, the margins are unchanged', (tester) async {
        await mount(tester);
        expect(last('logoViewMargins'), [8, 8]);
        expect(last('attributionButtonMargins'), [8, 8]);
      });

      testWidgets('a new focus moves the margins', (tester) async {
        final session = NavigationSession(fixes: _Fixes())..start();
        addTearDown(session.dispose);
        await mount(tester, session: session);
        await mount(tester, session: session, horizontalFocus: 0.75);
        await tester.pump();
        expect(last('logoViewMargins'), [208, 8]);
      });
    });
  });
}
