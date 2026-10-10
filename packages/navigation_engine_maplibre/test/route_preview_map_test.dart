// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';
import 'package:navigation_engine_maplibre/src/maplibre_navigation_map.dart'
    show toCameraPosition;

import 'support/recording_platform.dart';

typedef _Map = MapLibreNavigationMap;

const _viewport = Size(400, 800);
const _padding = EdgeInsets.fromLTRB(10, 20, 30, 300);
const _alternative = Color(0xFF9AA0A6);

const _driven = _Map.drivenLayer;
const _ahead = _Map.aheadLayer;
const _vehicle = _Map.vehicleLayer;
const _labels = 'navigation_engine_option_labels';

String _line(int i) => 'navigation_engine_option_$i';
String _casing(int i) => 'navigation_engine_option_casing_$i';
String _source(int i) => 'navigation_engine_option_$i';
String _image(int i, {required bool selected}) =>
    'navigation_engine_option_label_${i}_${selected ? 'sel' : 'alt'}';

/// Three parallel east-west routes, about 330 m apart.
NavRoute _route(double lat) => NavRoute.fromPoints([
  GeoPoint(lat, 106.690),
  GeoPoint(lat, 106.695),
  GeoPoint(lat, 106.700),
]);
final _south = _route(10.767);
final _west = _route(10.770);
final _north = _route(10.773);
final _routes = [_west, _north];
final _three = [_south, _west, _north];

String _label(NavRoute r) => identical(r, _south)
    ? 'south'
    : identical(r, _west)
    ? 'west'
    : 'north';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

final _selectedCasing = Color.lerp(
  const RouteColors().ahead,
  const Color(0xFF000000),
  0.35,
)!;
final _mutedCasing = Color.lerp(_alternative, const Color(0xFFFFFFFF), 0.5)!;

/// Lets the adapter's pending work run: the fake platform answers through
/// futures, not timers, so a fixed number of event-loop turns is enough (no
/// wall-clock wait).
Future<void> _settle() => pumpEventQueue();

/// A painter that returns `<text>/<sel|alt>` as bytes and records each call.
class _Painter {
  final calls = <(String, bool, double, RouteLabelColors)>[];

  /// When set, renders wait for this before they finish.
  Completer<void>? gate;

  Future<Uint8List> call(
    String text, {
    required bool selected,
    required double pixelRatio,
    required RouteLabelColors colors,
  }) async {
    calls.add((text, selected, pixelRatio, colors));
    final g = gate;
    if (g != null) await g.future;
    return bytesOf(text, selected: selected);
  }

  static Uint8List bytesOf(String text, {required bool selected}) =>
      Uint8List.fromList('$text/${selected ? 'sel' : 'alt'}'.codeUnits);
}

/// A map on a fresh platform with its style loaded.
Future<(MapLibreNavigationMap, RecordingPlatform)> _loaded({
  List<String>? log,
  _Painter? painter,
  bool labels = false,
}) async {
  final platform = RecordingPlatform();
  final map = MapLibreNavigationMap()
    ..log = (log ?? <String>[]).add
    ..onMapCreated(controllerOn(platform));
  if (labels) {
    map
      ..routeLabel = _label
      ..labelPainter = (painter ?? _Painter()).call;
  }
  await map.onStyleLoaded();
  await _settle();
  return (map, platform);
}

List<String> _optionLayerIds(RecordingPlatform p) => [
  for (final id in p.layerIds)
    if (id.startsWith('navigation_engine_option_')) id,
];

List<String> _optionSourceIds(RecordingPlatform p) => [
  for (final id in p.sources.keys)
    if (id.startsWith('navigation_engine_option_')) id,
];

List<Map<String, dynamic>> _labelFeatures(RecordingPlatform p) =>
    (p.sources[_labels]!['features'] as List).cast<Map<String, dynamic>>();

/// The `(layerId, properties)` of each setLayerProperties call.
Map<String, Map<String, dynamic>> _restyles(RecordingPlatform p) => {
  for (final a in p.argsOf('setLayerProperties').cast<(String, Object?)>())
    a.$1: a.$2! as Map<String, dynamic>,
};

/// The camera position an update moves to.
Map<String, dynamic> _cameraOf(Object? update) {
  final json = (update! as ml.CameraUpdate).toJson() as List;
  expect(json.first, 'newCameraPosition');
  return (json[1] as Map).cast<String, dynamic>();
}

void _expectFitted(Object? update, CameraTarget fitted) {
  final camera = _cameraOf(update);
  final expected = toCameraPosition(fitted);
  final target = camera['target'] as List;
  expect(target[0], closeTo(expected.target.latitude, 1e-9));
  expect(target[1], closeTo(expected.target.longitude, 1e-9));
  // MapLibre's world is 512 px tiles: one zoom level less than the 256 dp
  // world of fitCameraToBounds.
  expect(camera['zoom'], closeTo(fitted.zoom - 1, 1e-9));
  expect(camera['bearing'], 0);
  expect(camera['tilt'], 0);
}

List<GeoPoint> _allPoints(List<NavRoute> routes) => [
  for (final r in routes) ...r.points,
];

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

void main() {
  group('sources and layers', () {
    test('each option gets a source, a casing and a line, below the session '
        'route: muted casings, muted lines, then the selected pair', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_three, 1);
      await _settle();

      expect(platform.layerIds, [
        _casing(0),
        _casing(2),
        _line(0),
        _line(2),
        _casing(1),
        _line(1),
        _driven,
        _ahead,
        _vehicle,
      ]);
      for (var i = 0; i < 3; i++) {
        for (final id in [_casing(i), _line(i)]) {
          final layer = platform.layer(id);
          expect(layer.kind, 'line', reason: id);
          expect(layer.source, _source(i), reason: id);
          expect(layer.below, _driven, reason: id);
          expect(layer.interactive, isTrue, reason: id);
        }
        final features = platform.sources[_source(i)]!['features'] as List;
        final geometry = (features.single as Map)['geometry'] as Map;
        expect(geometry['type'], 'LineString');
        expect(geometry['coordinates'], [
          for (final p in _three[i].points) [p.lng, p.lat],
        ]);
      }
      expect(_optionSourceIds(platform), [_source(0), _source(1), _source(2)]);
      // The session's own layers stay out of taps.
      for (final id in [_driven, _ahead, _vehicle]) {
        expect(platform.layer(id).interactive, isFalse, reason: id);
      }
    });

    test('the paint follows the route colours', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();

      final selected = platform.layer(_line(0)).properties;
      expect(selected['line-color'], _hex(const RouteColors().ahead));
      expect(selected['line-width'], 8);
      final selectedCasing = platform.layer(_casing(0)).properties;
      expect(selectedCasing['line-color'], _hex(_selectedCasing));
      expect(selectedCasing['line-width'], 12);
      final muted = platform.layer(_line(1)).properties;
      expect(muted['line-color'], _hex(_alternative));
      expect(muted['line-width'], 8);
      final mutedCasing = platform.layer(_casing(1)).properties;
      expect(mutedCasing['line-color'], _hex(_mutedCasing));
      expect(mutedCasing['line-width'], 12);
    });

    test('another selection redraws the layers in the new order', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.showRouteOptions(_routes, 1);
      await _settle();

      expect(_optionLayerIds(platform), [
        _casing(0),
        _line(0),
        _casing(1),
        _line(1),
      ]);
      expect(
        platform.layer(_line(1)).properties['line-color'],
        _hex(const RouteColors().ahead),
      );
      expect(
        platform.layer(_line(0)).properties['line-color'],
        _hex(_alternative),
      );
      // The sources are reused: their data is replaced, not added again.
      expect(
        platform.argsOf('addGeoJsonSource').where((s) => s == _source(0)),
        hasLength(1),
      );
    });

    test('fewer routes remove the extra layers and sources', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_three, 0);
      await _settle();
      map.showRouteOptions([_north], 0);
      await _settle();

      expect(_optionLayerIds(platform), [_casing(0), _line(0)]);
      expect(_optionSourceIds(platform), [_source(0)]);
      final features = platform.sources[_source(0)]!['features'] as List;
      final geometry = (features.single as Map)['geometry'] as Map;
      expect((geometry['coordinates'] as List).first, [106.690, 10.773]);
    });

    test(
      'options shown before the style loads are drawn once it has',
      () async {
        final platform = RecordingPlatform();
        final map = MapLibreNavigationMap()
          ..log = <String>[].add
          ..onMapCreated(controllerOn(platform));
        map.showRouteOptions(_routes, 1);
        await _settle();
        expect(_optionLayerIds(platform), isEmpty);
        expect(platform.names, isNot(contains('addLineLayer')));

        await map.onStyleLoaded();
        expect(_optionLayerIds(platform), [
          _casing(0),
          _line(0),
          _casing(1),
          _line(1),
        ]);
      },
    );
  });

  group('taps', () {
    test('a tap on an option line or casing selects that route', () async {
      final (map, platform) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_three, 1);
      await _settle();

      platform.tapFeature(_line(2));
      platform.tapFeature(_casing(0));
      platform.tapFeature(_line(1), id: 'whatever');
      expect(taps, [2, 0, 1]);
    });

    test('a tap on a label selects its route', () async {
      final (map, platform) = await _loaded(labels: true);
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_three, 0);
      await _settle();

      // The SDK reports the feature id as a string.
      platform.tapFeature(_labels, id: '2');
      platform.tapFeature(_labels, id: 1);
      expect(taps, [2, 1]);
    });

    test('taps on non-option layers are ignored', () async {
      final (map, platform) = await _loaded(labels: true);
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();

      // The session's own route and vehicle, and an app's layer, with
      // feature ids that look like route indices.
      for (final layer in [_driven, _ahead, _vehicle, 'poi-label', 'roads']) {
        platform.tapFeature(layer, id: '0');
        platform.tapFeature(layer, id: '1');
        platform.tapFeature(layer);
      }
      // Ids that are not a shown option.
      platform.tapFeature(_line(5));
      platform.tapFeature(_casing(2));
      platform.tapFeature('navigation_engine_option_x');
      platform.tapFeature('navigation_engine_option_label_0_sel');
      platform.tapFeature(_labels);
      platform.tapFeature(_labels, id: '7');
      expect(taps, isEmpty);
    });

    test('taps after clearRouteOptions are ignored', () async {
      final (map, platform) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      platform.tapFeature(_line(0));
      expect(taps, isEmpty);
    });

    test('a new controller takes over the taps', () async {
      final (map, first) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      final second = RecordingPlatform();
      map.onMapCreated(controllerOn(second));
      // Taps count for what the style holds: the new style draws the lines.
      await map.onStyleLoaded();
      await _settle();
      first.tapFeature(_line(1));
      expect(taps, isEmpty);
      second.tapFeature(_line(1));
      expect(taps, [1]);
    });

    test('a tap on an option line or label drawn for an older list is '
        'ignored', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();
      // Another list, its labels still rendering: until the queue runs, the
      // style holds the old lines (index 1 is north) and labels.
      painter.gate = Completer<void>();
      map.showRouteOptions([_west, _south], 0);
      platform
        ..tapFeature(_line(1))
        ..tapFeature(_casing(1))
        ..tapFeature(_labels, id: 1);
      expect(taps, isEmpty);
      // The same route at index 0 still counts.
      platform.tapFeature(_line(0));
      expect(taps, [0]);
      await _settle();
      platform.tapFeature(_line(1));
      expect(taps, [0, 1]);
      painter.gate!.complete();
      await _settle();
      platform.tapFeature(_labels, id: 1);
      expect(taps, [0, 1, 1]);
    });
  });

  group('labels', () {
    test('label images are added and the symbol layer shows them', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_three, 1);
      await _settle();

      expect(platform.images[_image(0, selected: false)], [
        ..._Painter.bytesOf('south', selected: false),
      ]);
      expect(platform.images[_image(1, selected: true)], [
        ..._Painter.bytesOf('west', selected: true),
      ]);
      expect(platform.images[_image(2, selected: false)], [
        ..._Painter.bytesOf('north', selected: false),
      ]);

      final features = _labelFeatures(platform);
      // The selected label is last, so it is drawn on top.
      expect(
        [for (final f in features) f['properties']],
        [
          {'index': 0, 'image': _image(0, selected: false)},
          {'index': 2, 'image': _image(2, selected: false)},
          {'index': 1, 'image': _image(1, selected: true)},
        ],
      );
      for (final f in features) {
        final i = (f['properties'] as Map)['index'] as int;
        expect(f['id'], i);
        final mid = _three[i].pointAt(_three[i].length / 2);
        expect((f['geometry'] as Map)['type'], 'Point');
        expect((f['geometry'] as Map)['coordinates'], [mid.lng, mid.lat]);
      }

      final layer = platform.layer(_labels);
      expect(layer.kind, 'symbol');
      expect(layer.source, _labels);
      expect(layer.interactive, isTrue);
      expect(layer.properties['icon-image'], ['get', 'image']);
      expect(layer.properties['icon-anchor'], 'bottom');
      expect(layer.properties['icon-allow-overlap'], isTrue);
      expect(layer.properties['symbol-z-order'], 'source');
      // Above the session route and the options, below the vehicle.
      expect(platform.layerIds.sublist(platform.layerIds.length - 3), [
        _ahead,
        _labels,
        _vehicle,
      ]);
    });

    test('a selection change keeps the labels until the new ones are '
        'ready (no blink)', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      expect(platform.layerIds, contains(_labels));
      platform.calls.clear();

      painter.gate = Completer<void>();
      map.showRouteOptions(_routes, 1);
      await _settle();
      // The new labels are still rendering: the old ones stay drawn.
      expect(platform.layerIds, contains(_labels));
      expect(platform.sources.containsKey(_labels), isTrue);
      expect(platform.argsOf('removeLayer'), isNot(contains(_labels)));
      expect(platform.argsOf('removeSource'), isNot(contains(_labels)));

      painter.gate!.complete();
      await _settle();
      expect(
        [for (final f in _labelFeatures(platform)) f['properties']],
        [
          {'index': 0, 'image': _image(0, selected: false)},
          {'index': 1, 'image': _image(1, selected: true)},
        ],
      );
      expect(platform.argsOf('removeLayer'), isNot(contains(_labels)));
    });

    test('new routes drop the old labels at once', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      painter.gate = Completer<void>();
      map.showRouteOptions(_three, 0);
      await _settle();
      expect(platform.layerIds, isNot(contains(_labels)));
      painter.gate!.complete();
      await _settle();
      expect(_labelFeatures(platform), hasLength(3));
    });

    test('the label image cache evicts the least recently used', () async {
      final painter = _Painter();
      final (map, _) = await _loaded(labels: true, painter: painter);
      var text = 'keep';
      map.routeLabel = (_) => text;
      void show(String t) {
        text = t;
        map.showRouteOptions([_west], 0);
      }

      show('keep');
      // More new labels than the cache holds (32), with 'keep' used again
      // in between: it stays, the others go oldest first.
      for (var i = 0; i < 40; i++) {
        show('label $i');
        show('keep');
      }
      expect(painter.calls.where((c) => c.$1 == 'keep'), hasLength(1));
      show('label 0');
      expect(painter.calls.where((c) => c.$1 == 'label 0'), hasLength(2));
      await _settle();
    });

    test('labels are painted at the pixel ratio in labelColors', () async {
      const colors = RouteLabelColors(selectedFill: Color(0xFF00FF00));
      final painter = _Painter();
      final (map, _) = await _loaded(labels: true, painter: painter);
      map
        ..pixelRatio = 2
        ..labelColors = colors
        ..showRouteOptions(_routes, 0);
      await _settle();
      expect(painter.calls, [
        ('west', true, 2.0, colors),
        ('north', false, 2.0, colors),
      ]);
    });

    test('the default painter renders a PNG at the pixel ratio', () async {
      final platform = RecordingPlatform();
      final map = MapLibreNavigationMap()
        ..log = <String>[].add
        ..onMapCreated(controllerOn(platform))
        ..routeLabel = _label
        ..pixelRatio = 2;
      await map.onStyleLoaded();
      map.showRouteOptions(_routes, 0);
      // The real painter renders on the engine: wait for the image itself.
      await platform
          .imageAdded(_image(0, selected: true))
          .timeout(const Duration(seconds: 10));
      final png = platform.images[_image(0, selected: true)]!;
      final expected = await paintRouteLabel(
        'west',
        selected: true,
        pixelRatio: 2,
      );
      expect(png, expected);
    });

    test('a superseded label render is dropped', () async {
      final painter = _Painter()..gate = Completer<void>();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      final firstGate = painter.gate!;
      // No label shared with the second render (renders are cached).
      map.showRouteOptions([_south], 0);
      await _settle();
      painter.gate = null;
      map.showRouteOptions(_routes, 1);
      await _settle();
      expect(_labelFeatures(platform), hasLength(2));
      final images = List.of(platform.imageAdds);

      firstGate.complete();
      await _settle();
      // Nothing from the first render: no images, the features unchanged.
      expect(platform.imageAdds, images);
      expect(
        [for (final f in _labelFeatures(platform)) f['properties']],
        [
          {'index': 0, 'image': _image(0, selected: false)},
          {'index': 1, 'image': _image(1, selected: true)},
        ],
      );
    });

    test('clearRouteOptions drops a pending label render', () async {
      final painter = _Painter()..gate = Completer<void>();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      painter.gate!.complete();
      await _settle();
      expect(platform.imageAdds, isNot(contains(_image(0, selected: true))));
      expect(platform.sources, isNot(contains(_labels)));
      expect(platform.layerIds, isNot(contains(_labels)));
    });

    test('no routeLabel, no label images or layer', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      expect(platform.imageAdds, [_Map.vehicleImageId]);
      expect(platform.sources, isNot(contains(_labels)));
      expect(platform.layerIds, isNot(contains(_labels)));
    });

    test('a failing painter adds no labels and does not throw', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final (map, platform) = await _loaded();
        map
          ..routeLabel = _label
          ..labelPainter =
              (
                text, {
                required selected,
                required pixelRatio,
                required colors,
              }) async {
                throw StateError('no paint');
              }
          ..showRouteOptions(_routes, 0);
        await _settle();
        expect(platform.layerIds, isNot(contains(_labels)));
        expect(_optionLayerIds(platform), hasLength(4));
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
    });

    test('the same labels are not painted twice', () async {
      final painter = _Painter();
      final (map, _) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.showRouteOptions(_routes, 0);
      await _settle();
      expect(painter.calls, hasLength(2));
      map.showRouteOptions(_routes, 1);
      await _settle();
      expect(painter.calls, hasLength(4));
    });

    test('labelColors repaint the shown labels', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      platform.calls.clear();
      const colors = RouteLabelColors(fill: Color(0xFF000000));
      map.labelColors = colors;
      await _settle();
      expect(painter.calls.skip(2).map((c) => c.$4), [colors, colors]);
      expect(platform.argsOf('addImage'), hasLength(2));
      // The lines are left alone.
      expect(platform.names, isNot(contains('removeLayer')));
    });
  });

  group('style reload', () {
    test('options survive a style change, re-added after it loads', () async {
      final painter = _Painter();
      final (map, platform) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_three, 1);
      await _settle();
      final layers = List.of(platform.layerIds);
      final sources = Map.of(platform.sources);
      final images = Map.of(platform.images);
      expect(layers, contains(_labels));

      map.onStyleChanging();
      platform.reloadStyle();
      await _settle();
      expect(platform.layerIds, isEmpty);

      await map.onStyleLoaded();
      await _settle();
      expect(platform.layerIds, layers);
      expect(platform.sources, sources);
      expect(platform.images.keys, unorderedEquals(images.keys));
      for (final id in images.keys) {
        expect(platform.images[id], images[id], reason: id);
      }
      // The labels are not painted again.
      expect(painter.calls, hasLength(3));
    });

    for (final android in [false, true]) {
      test('a second style load on the same style keeps the options '
          '(${android ? 'Android: silent' : 'iOS: throwing'} duplicate '
          'sources)', () async {
        final painter = _Painter();
        final (map, platform) = await _loaded(labels: true, painter: painter);
        platform.silentDuplicateSources = android;
        map.showRouteOptions(_three, 1);
        await _settle();
        map.showRouteOptions(_three, 2);
        await _settle();
        final layers = List.of(platform.layerIds);
        final sources = Map.of(platform.sources);

        // The SDK reports the same style again (or the app retries).
        await map.onStyleLoaded();
        await _settle();
        expect(platform.layerIds, unorderedEquals(layers));
        expect(platform.sources, sources);
        expect(
          [for (final f in _labelFeatures(platform)) f['properties']].last,
          {'index': 2, 'image': _image(2, selected: true)},
        );
        // Still current after a change.
        map.showRouteOptions(_three, 0);
        await _settle();
        expect(
          [for (final f in _labelFeatures(platform)) f['properties']].last,
          {'index': 0, 'image': _image(0, selected: true)},
        );
      });
    }

    test(
      'options changed while the style reloads are drawn as last shown',
      () async {
        final (map, platform) = await _loaded();
        map.showRouteOptions(_three, 1);
        await _settle();
        map.onStyleChanging();
        platform.reloadStyle();
        map.showRouteOptions(_routes, 0);
        await _settle();
        expect(platform.layerIds, isEmpty);

        await map.onStyleLoaded();
        await _settle();
        expect(_optionLayerIds(platform), [
          _casing(1),
          _line(1),
          _casing(0),
          _line(0),
        ]);
        expect(_optionSourceIds(platform), [_source(0), _source(1)]);
      },
    );

    test('options cleared while the style reloads are not drawn', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.onStyleChanging();
      platform.reloadStyle();
      map.clearRouteOptions();
      await map.onStyleLoaded();
      await _settle();
      expect(_optionLayerIds(platform), isEmpty);
      expect(_optionSourceIds(platform), isEmpty);
    });
  });

  group('clearRouteOptions', () {
    test('removes the sources and layers, layers first', () async {
      final (map, platform) = await _loaded(labels: true);
      map.showRouteOptions(_three, 1);
      await _settle();
      platform.calls.clear();

      map.clearRouteOptions();
      await _settle();
      expect(_optionLayerIds(platform), isEmpty);
      expect(_optionSourceIds(platform), isEmpty);
      expect(platform.layerIds, [_driven, _ahead, _vehicle]);
      // The fake throws when a source still in use is removed.
      expect(platform.argsOf('removeSource'), hasLength(4));
      // maplibre_gl 0.27.1 cannot remove images: nothing refers to them any
      // more, and the next labels replace them by id.
      expect(platform.argsOf('addImage'), isEmpty);
    });

    test('drops the pending fit', () async {
      final platform = RecordingPlatform();
      final map = MapLibreNavigationMap()
        ..log = <String>[].add
        ..onMapCreated(controllerOn(platform));
      await map.fitRoutes(_routes, _padding);
      map.clearRouteOptions();
      map.viewportSize = _viewport;
      await _settle();
      expect(platform.names, isNot(contains('moveCamera')));
      expect(platform.names, isNot(contains('animateCamera')));
    });

    test('with nothing shown, does nothing', () async {
      final (map, platform) = await _loaded();
      platform.calls.clear();
      map.clearRouteOptions();
      await _settle();
      expect(platform.calls, isEmpty);
    });
  });

  group('fitRoutes', () {
    test(
      'animates to the fitted camera, with the padding as mapPadding',
      () async {
        final (map, platform) = await _loaded();
        const focus = EdgeInsets.only(top: 400, bottom: 80);
        map
          ..padding = focus
          ..viewportSize = _viewport;
        await map.fitRoutes(_routes, _padding);

        _expectFitted(
          platform.argsOf('animateCamera').single,
          fitCameraToBounds(
            _allPoints(_routes),
            _viewport,
            _padding,
            mapPadding: focus,
          ),
        );
      },
    );

    test(
      'a pending fit is applied once, with the padding set meanwhile',
      () async {
        final map = MapLibreNavigationMap()..log = <String>[].add;
        await map.fitRoutes(_routes, _padding);
        const focus = EdgeInsets.only(top: 300);
        map.padding = focus;
        final platform = RecordingPlatform();
        map.onMapCreated(controllerOn(platform));
        await _settle();
        expect(
          platform.names,
          isNot(contains('moveCamera')),
          reason: 'no size',
        );

        map.viewportSize = _viewport;
        await _settle();
        _expectFitted(
          platform.argsOf('moveCamera').single,
          fitCameraToBounds(
            _allPoints(_routes),
            _viewport,
            _padding,
            mapPadding: focus,
          ),
        );
        // The padding reaches the map before the camera does.
        expect(
          platform.names.toList().indexOf('updateContentInsets'),
          lessThan(platform.names.toList().indexOf('moveCamera')),
        );

        map.viewportSize = const Size(300, 600);
        map.onMapCreated(controllerOn(platform));
        await _settle();
        expect(platform.argsOf('moveCamera'), hasLength(1));
        expect(platform.argsOf('animateCamera'), isEmpty);
      },
    );

    test('a newer fit replaces a pending one', () async {
      final map = MapLibreNavigationMap()..log = <String>[].add;
      await map.fitRoutes(_routes, _padding);
      await map.fitRoutes([_south], EdgeInsets.zero);
      final platform = RecordingPlatform();
      map
        ..onMapCreated(controllerOn(platform))
        ..viewportSize = _viewport;
      await _settle();
      _expectFitted(
        platform.argsOf('moveCamera').single,
        fitCameraToBounds(_south.points, _viewport, EdgeInsets.zero),
      );
    });

    test('no routes, no fit', () async {
      final (map, platform) = await _loaded();
      map.viewportSize = _viewport;
      await map.fitRoutes(const [], _padding);
      await _settle();
      expect(platform.names, isNot(contains('animateCamera')));
    });

    test('a camera error is logged, not thrown', () async {
      final log = <String>[];
      final (map, platform) = await _loaded(log: log);
      map.viewportSize = _viewport;
      platform.failOnce.add('animateCamera');
      await map.fitRoutes(_routes, _padding);
      expect(log, [contains('animateCamera failed')]);
    });

    test('a pending fit is dropped on dispose', () async {
      final map = MapLibreNavigationMap()..log = <String>[].add;
      await map.fitRoutes(_routes, _padding);
      map.dispose();
      final platform = RecordingPlatform();
      map
        ..onMapCreated(controllerOn(platform))
        ..viewportSize = _viewport;
      await _settle();
      expect(platform.names, isNot(contains('moveCamera')));
    });
  });

  group('colour changes while options are shown', () {
    test('alternativeColor updates the muted line paint', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_three, 1);
      await _settle();
      platform.calls.clear();

      const color = Color(0xFF123456);
      map.alternativeColor = color;
      await _settle();
      final sets = _restyles(platform);
      expect(
        sets.keys,
        unorderedEquals([
          _casing(0),
          _line(0),
          _casing(2),
          _line(2),
          _casing(1),
          _line(1),
        ]),
      );
      expect(sets[_line(0)]!['line-color'], _hex(color));
      expect(sets[_line(2)]!['line-color'], _hex(color));
      expect(
        sets[_casing(0)]!['line-color'],
        _hex(Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!),
      );
      expect(sets[_line(1)]!['line-color'], _hex(const RouteColors().ahead));
      // Restyled in place: nothing is removed or added.
      expect(platform.names, isNot(contains('removeLayer')));
      expect(platform.names, isNot(contains('addLineLayer')));
    });

    test('routeColors update the selected line paint', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      platform.calls.clear();

      const ahead = Color(0xFFFF0000);
      map.routeColors = const RouteColors(ahead: ahead, aheadWidth: 10);
      await _settle();
      final sets = _restyles(platform);
      expect(sets[_line(0)]!['line-color'], _hex(ahead));
      expect(sets[_line(0)]!['line-width'], 10);
      expect(
        sets[_casing(0)]!['line-color'],
        _hex(Color.lerp(ahead, const Color(0xFF000000), 0.35)!),
      );
      expect(sets[_casing(0)]!['line-width'], 14);
      expect(sets[_line(1)]!['line-color'], _hex(_alternative));
      // The session's own lines are restyled too.
      expect(sets[_ahead]!['line-color'], _hex(ahead));
    });

    test('the same colour does nothing', () async {
      final (map, platform) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      platform.calls.clear();
      map.alternativeColor = _alternative;
      await _settle();
      expect(platform.calls, isEmpty);
    });

    test('nothing is drawn after clearRouteOptions', () async {
      final (map, platform) = await _loaded(labels: true);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      await _settle();
      platform.calls.clear();
      map
        ..alternativeColor = const Color(0xFF123456)
        ..labelColors = const RouteLabelColors(fill: Color(0xFF000000));
      await _settle();
      expect(platform.calls, isEmpty);
    });
  });

  group('the view', () {
    late RecordingPlatform platform;
    late ml.MapLibrePlatform Function() createInstance;

    setUp(() {
      platform = RecordingPlatform();
      createInstance = ml.MapLibrePlatform.createInstance;
      ml.MapLibrePlatform.createInstance = () => platform;
    });
    tearDown(() => ml.MapLibrePlatform.createInstance = createInstance);

    Future<(NavigationSession, MapLibreNavigationMap)> mount(
      WidgetTester tester, {
      bool night = false,
      String? nightStyleString,
      String Function(NavRoute)? routeLabel,
      void Function(int)? onRouteOptionTap,
      RouteLabelColors labelColors = const RouteLabelColors(),
      Color alternativeRouteColor = _alternative,
      NavigationSession? session,
    }) async {
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = session ?? (NavigationSession(fixes: _Fixes())..start());
      if (session == null) addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MapLibreNavigationView(
            session: s,
            styleString: 'day.json',
            nightStyleString: nightStyleString,
            night: night,
            initialCenter: _west.points.first,
            routeLabel: routeLabel,
            onRouteOptionTap: onRouteOptionTap,
            labelColors: labelColors,
            alternativeRouteColor: alternativeRouteColor,
            // Rendered without the engine, so the fake-async clock is
            // enough to load the style.
            vehicleImage: (_) async => Uint8List(4),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = s.map! as MapLibreNavigationMap;
      map.log = <String>[].add;
      return (s, map);
    }

    testWidgets('forwards its parameters to the adapter', (tester) async {
      const colors = RouteLabelColors(selectedFill: Color(0xFF00FF00));
      void onTap(int _) {}
      final (_, map) = await mount(
        tester,
        routeLabel: _label,
        onRouteOptionTap: onTap,
        labelColors: colors,
        alternativeRouteColor: const Color(0xFF123456),
      );
      expect(map.routeLabel, same(_label));
      expect(map.onRouteOptionTap, same(onTap));
      expect(map.labelColors, colors);
      expect(map.alternativeColor, const Color(0xFF123456));
      expect(map.viewportSize, _viewport);
      // The frame's focus padding: the vehicle sits at 70 % of the height.
      expect(map.padding.top - map.padding.bottom, closeTo(2 * 160, 1e-6));
    });

    testWidgets('the initial zoom 17 becomes SDK zoom 16', (tester) async {
      await mount(tester);
      final camera =
          platform.creationParams.first['initialCameraPosition'] as Map;
      expect(camera['zoom'], 16);
    });

    testWidgets('night with a night style reloads the style, options kept', (
      tester,
    ) async {
      final session = NavigationSession(fixes: _Fixes())..start();
      addTearDown(session.dispose);
      final (_, map) = await mount(
        tester,
        session: session,
        nightStyleString: 'night.json',
      );
      expect(platform.argsOf('buildView').first, 'day.json');
      unawaited(map.onStyleLoaded());
      await tester.pump();
      map.showRouteOptions(_routes, 0);
      await tester.pump();
      expect(_optionLayerIds(platform), hasLength(4));

      await mount(
        tester,
        session: session,
        night: true,
        nightStyleString: 'night.json',
      );
      expect(platform.argsOf('updateMapOptions').last, {
        'styleString': 'night.json',
      });
      // The style is changing: nothing is drawn until it has loaded.
      platform
        ..reloadStyle()
        ..calls.clear();
      map.showRouteOptions(_routes, 1);
      await tester.pump();
      expect(platform.calls, isEmpty);

      unawaited(map.onStyleLoaded());
      await tester.pump();
      await tester.pump();
      expect(_optionLayerIds(platform), [
        _casing(0),
        _line(0),
        _casing(1),
        _line(1),
      ]);

      await mount(tester, session: session, nightStyleString: 'night.json');
      expect(platform.argsOf('updateMapOptions').last, {
        'styleString': 'day.json',
      });
    });

    testWidgets('night without a night style keeps the day style', (
      tester,
    ) async {
      final session = NavigationSession(fixes: _Fixes())..start();
      addTearDown(session.dispose);
      final (_, map) = await mount(tester, session: session);
      unawaited(map.onStyleLoaded());
      await tester.pump();
      await mount(tester, session: session, night: true);
      expect(platform.names, isNot(contains('updateMapOptions')));
      // Still ready: options are drawn at once.
      map.showRouteOptions(_routes, 0);
      await tester.pump();
      expect(_optionLayerIds(platform), hasLength(4));
    });
  });
}
