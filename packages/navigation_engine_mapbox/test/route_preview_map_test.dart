// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';
import 'package:navigation_engine_mapbox/src/mapbox_navigation_map.dart'
    show MapboxNavigationMapTesting;
import 'package:navigation_engine_mapbox/src/mapbox_navigation_view.dart'
    show dayNightStyle;

import 'support/recording_backend.dart';

typedef _Map = MapboxNavigationMap;

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

final _selectedCasing = Color.lerp(
  const RouteColors().ahead,
  const Color(0xFF000000),
  0.35,
)!;
final _mutedCasing = Color.lerp(_alternative, const Color(0xFFFFFFFF), 0.5)!;

/// Lets the adapter and the fake backend finish their pending work.
///
/// The fake backend answers each call after a zero-delay timer, so a chain of
/// calls needs one event-loop turn per link. Counting turns, not wall-clock
/// time, makes this independent of machine load: a stalled loop only runs the
/// same turns later.
Future<void> _settle() async {
  for (var turn = 0; turn < 200; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

/// A map on a fresh backend with its style loaded.
Future<(MapboxNavigationMap, RecordingBackend)> _loaded({
  List<String>? log,
  _Painter? painter,
  bool labels = false,
}) async {
  final backend = RecordingBackend();
  final map = MapboxNavigationMap()
    ..log = (log ?? <String>[]).add
    ..attachBackend(backend);
  if (labels) {
    map
      ..routeLabel = _label
      ..labelPainter = (painter ?? _Painter()).call;
  }
  await map.onStyleLoaded();
  await _settle();
  return (map, backend);
}

List<String> _optionLayerIds(RecordingBackend b) => [
  for (final id in b.layerIds)
    if (id.startsWith('navigation_engine_option_')) id,
];

List<String> _optionSourceIds(RecordingBackend b) => [
  for (final id in b.sources.keys)
    if (id.startsWith('navigation_engine_option_')) id,
];

List<Map<String, dynamic>> _labelFeatures(RecordingBackend b) =>
    ((b.sources[_labels]! as Map)['features'] as List)
        .cast<Map<String, dynamic>>();

mb.LineLayer _lineOf(RecordingBackend b, String id) =>
    b.layer(id).layer as mb.LineLayer;

/// The bytes of the image [id] in the style.
Uint8List _bytes(RecordingBackend b, String id) =>
    (b.images[id]!.$2 as mb.StyleImageBytes).bytes;

/// The line layers sent with updateLayer, by id.
Map<String, mb.LineLayer> _restyles(RecordingBackend b) => {
  for (final l in b.argsOf('updateLayer').cast<mb.LineLayer>()) l.id: l,
};

void _expectFitted(Object? options, CameraTarget fitted, EdgeInsets padding) {
  final o = options! as mb.CameraOptions;
  expect(o.center!.coordinates.lat, closeTo(fitted.position.lat, 1e-9));
  expect(o.center!.coordinates.lng, closeTo(fitted.position.lng, 1e-9));
  // Mapbox's world is 512 px tiles: one zoom level less than the 256 dp
  // world of fitCameraToBounds.
  expect(o.zoom, closeTo(fitted.zoom - 1, 1e-9));
  expect(o.bearing, 0);
  expect(o.pitch, 0);
  expect(
    (o.padding!.top, o.padding!.left, o.padding!.bottom, o.padding!.right),
    (padding.top, padding.left, padding.bottom, padding.right),
  );
}

List<GeoPoint> _allPoints(List<NavRoute> routes) => [
  for (final r in routes) ...r.points,
];

void main() {
  group('sources and layers', () {
    test('each option gets a source, a casing and a line, below the session '
        'route: muted casings, muted lines, then the selected pair', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_three, 1);
      await _settle();

      expect(backend.layerIds, [
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
          final layer = backend.layer(id);
          expect(layer.layer, isA<mb.LineLayer>(), reason: id);
          expect((layer.layer as mb.LineLayer).sourceId, _source(i));
          expect(layer.below, _driven, reason: id);
          expect(backend.taps, contains(id), reason: id);
        }
        final features =
            (backend.sources[_source(i)]! as Map)['features'] as List;
        final geometry = (features.single as Map)['geometry'] as Map;
        expect(geometry['type'], 'LineString');
        expect(geometry['coordinates'], [
          for (final p in _three[i].points) [p.lng, p.lat],
        ]);
      }
      expect(_optionSourceIds(backend), [_source(0), _source(1), _source(2)]);
      // The session's own layers take no taps.
      for (final id in [_driven, _ahead, _vehicle]) {
        expect(backend.taps, isNot(contains(id)), reason: id);
      }
    });

    test('the paint follows the route colours', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();

      final selected = _lineOf(backend, _line(0));
      expect(selected.lineColor, const RouteColors().ahead.toARGB32());
      expect(selected.lineWidth, 8);
      expect(selected.lineCap, mb.LineCap.ROUND);
      expect(selected.lineJoin, mb.LineJoin.ROUND);
      final selectedCasing = _lineOf(backend, _casing(0));
      expect(selectedCasing.lineColor, _selectedCasing.toARGB32());
      expect(selectedCasing.lineWidth, 12);
      final muted = _lineOf(backend, _line(1));
      expect(muted.lineColor, _alternative.toARGB32());
      expect(muted.lineWidth, 8);
      final mutedCasing = _lineOf(backend, _casing(1));
      expect(mutedCasing.lineColor, _mutedCasing.toARGB32());
      expect(mutedCasing.lineWidth, 12);
    });

    test('another selection redraws the layers in the new order', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.showRouteOptions(_routes, 1);
      await _settle();

      expect(_optionLayerIds(backend), [
        _casing(0),
        _line(0),
        _casing(1),
        _line(1),
      ]);
      expect(
        _lineOf(backend, _line(1)).lineColor,
        const RouteColors().ahead.toARGB32(),
      );
      expect(_lineOf(backend, _line(0)).lineColor, _alternative.toARGB32());
      // The sources are reused: their data is replaced, not added again.
      expect(
        backend.argsOf('addGeoJsonSource').where((s) => s == _source(0)),
        hasLength(1),
      );
      // Each layer's tap interaction is added once.
      expect(
        backend.argsOf('addTapInteraction').where((id) => id == _line(0)),
        hasLength(1),
      );
    });

    test('fewer routes remove the extra layers and sources', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_three, 0);
      await _settle();
      map.showRouteOptions([_north], 0);
      await _settle();

      expect(_optionLayerIds(backend), [_casing(0), _line(0)]);
      expect(_optionSourceIds(backend), [_source(0)]);
      final features =
          (backend.sources[_source(0)]! as Map)['features'] as List;
      final geometry = (features.single as Map)['geometry'] as Map;
      expect((geometry['coordinates'] as List).first, [106.690, 10.773]);
    });

    test(
      'options shown before the style loads are drawn once it has',
      () async {
        final backend = RecordingBackend();
        final map = MapboxNavigationMap()
          ..log = <String>[].add
          ..attachBackend(backend);
        map.showRouteOptions(_routes, 1);
        await _settle();
        expect(_optionLayerIds(backend), isEmpty);
        expect(backend.calls, isEmpty);

        await map.onStyleLoaded();
        expect(_optionLayerIds(backend), [
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
      final (map, backend) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_three, 1);
      await _settle();

      backend.tapFeature(_line(2));
      backend.tapFeature(_casing(0));
      backend.tapFeature(_line(1), id: 'whatever');
      expect(taps, [2, 0, 1]);
    });

    test('a tap on a label selects its route', () async {
      final (map, backend) = await _loaded(labels: true);
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_three, 0);
      await _settle();

      expect(backend.taps, contains(_labels));
      // The index property; the feature id when there is none.
      backend.tapFeature(
        _labels,
        id: '0',
        properties: {'index': 2, 'image': _image(2, selected: false)},
      );
      backend.tapFeature(_labels, id: '1');
      expect(taps, [2, 1]);
    });

    test('taps on non-option layers are ignored', () async {
      final (map, backend) = await _loaded(labels: true);
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();

      // Only the option and label layers take taps.
      expect(
        backend.taps.keys,
        unorderedEquals([_casing(0), _line(0), _casing(1), _line(1), _labels]),
      );
      // The session's own route and vehicle, and an app's layer, with
      // feature ids that look like route indices.
      for (final layer in [_driven, _ahead, _vehicle, 'poi-label', 'roads']) {
        backend.tapFeature(layer, id: '0', properties: {'index': 0});
        backend.tapFeature(layer, id: '1', properties: {'index': 1});
        backend.tapFeature(layer);
      }
      // Ids that are not a shown option.
      backend.tapFeature(_line(5));
      backend.tapFeature(_casing(2));
      backend.tapFeature('navigation_engine_option_x');
      backend.tapFeature('navigation_engine_option_label_0_sel');
      backend.tapFeature(_labels);
      backend.tapFeature(_labels, id: '7');
      backend.tapFeature(_labels, properties: {'index': 7});
      expect(taps, isEmpty);
    });

    test('taps after clearRouteOptions are ignored', () async {
      final (map, backend) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      backend.tapFeature(_line(0));
      expect(taps, isEmpty);
    });

    test('a new map takes over the taps', () async {
      final (map, first) = await _loaded();
      final taps = <int>[];
      map
        ..onRouteOptionTap = taps.add
        ..showRouteOptions(_routes, 0);
      await _settle();
      final second = RecordingBackend();
      map.attachBackend(second);
      await map.onStyleLoaded();
      await _settle();
      first.tapFeature(_line(1));
      expect(taps, isEmpty);
      second.tapFeature(_line(1));
      expect(taps, [1]);
    });
  });

  group('labels', () {
    test('label images are added and the symbol layer shows them', () async {
      final painter = _Painter();
      final (map, backend) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_three, 1);
      await _settle();

      expect(_bytes(backend, _image(0, selected: false)), [
        ..._Painter.bytesOf('south', selected: false),
      ]);
      expect(_bytes(backend, _image(1, selected: true)), [
        ..._Painter.bytesOf('west', selected: true),
      ]);
      expect(_bytes(backend, _image(2, selected: false)), [
        ..._Painter.bytesOf('north', selected: false),
      ]);
      // Rendered at the pixel ratio (3 by default): the same scale.
      expect(backend.images[_image(1, selected: true)]!.$1, 3);

      final features = _labelFeatures(backend);
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

      final layer = backend.layer(_labels).layer as mb.SymbolLayer;
      expect(layer.sourceId, _labels);
      expect(backend.taps, contains(_labels));
      expect(layer.iconImageExpression, ['get', 'image']);
      expect(layer.iconAnchor, mb.IconAnchor.BOTTOM);
      expect(layer.iconAllowOverlap, isTrue);
      expect(layer.iconIgnorePlacement, isTrue);
      expect(layer.symbolZOrder, mb.SymbolZOrder.SOURCE);
      // Above the session route and the options, below the vehicle.
      expect(backend.layer(_labels).below, _vehicle);
      expect(backend.layerIds.sublist(backend.layerIds.length - 3), [
        _ahead,
        _labels,
        _vehicle,
      ]);
    });

    test('labels are painted at the pixel ratio in labelColors', () async {
      const colors = RouteLabelColors(selectedFill: Color(0xFF00FF00));
      final painter = _Painter();
      final (map, backend) = await _loaded(labels: true, painter: painter);
      map
        ..pixelRatio = 2
        ..labelColors = colors
        ..showRouteOptions(_routes, 0);
      await _settle();
      expect(painter.calls, [
        ('west', true, 2.0, colors),
        ('north', false, 2.0, colors),
      ]);
      expect(backend.images[_image(0, selected: true)]!.$1, 2);
    });

    test('the default painter renders a PNG at the pixel ratio', () async {
      final backend = RecordingBackend();
      final map = MapboxNavigationMap()
        ..log = <String>[].add
        ..attachBackend(backend)
        ..routeLabel = _label
        ..pixelRatio = 2;
      await map.onStyleLoaded();
      final expected = await paintRouteLabel(
        'west',
        selected: true,
        pixelRatio: 2,
      );
      map.showRouteOptions(_routes, 0);
      // The real renderer is asynchronous: wait for the image to reach the
      // style (a signal, not a delay), failing after a generous timeout.
      await backend
          .imageAdded(_image(0, selected: true))
          .timeout(const Duration(seconds: 10));
      final png = _bytes(backend, _image(0, selected: true));
      expect(png, expected);
    });

    test('a superseded label render is dropped', () async {
      final painter = _Painter()..gate = Completer<void>();
      final (map, backend) = await _loaded(labels: true, painter: painter);
      final firstGate = painter.gate!;
      // No label shared with the second render (renders are cached).
      map.showRouteOptions([_south], 0);
      await _settle();
      painter.gate = null;
      map.showRouteOptions(_routes, 1);
      await _settle();
      expect(_labelFeatures(backend), hasLength(2));
      final images = List.of(backend.imageAdds);

      firstGate.complete();
      await _settle();
      // Nothing from the first render: no images, the features unchanged.
      expect(backend.imageAdds, images);
      expect(
        [for (final f in _labelFeatures(backend)) f['properties']],
        [
          {'index': 0, 'image': _image(0, selected: false)},
          {'index': 1, 'image': _image(1, selected: true)},
        ],
      );
    });

    test('clearRouteOptions drops a pending label render', () async {
      final painter = _Painter()..gate = Completer<void>();
      final (map, backend) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      painter.gate!.complete();
      await _settle();
      expect(backend.imageAdds, isNot(contains(_image(0, selected: true))));
      expect(backend.sources, isNot(contains(_labels)));
      expect(backend.layerIds, isNot(contains(_labels)));
    });

    test('no routeLabel, no label images or layer', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      expect(backend.imageAdds, [_Map.vehicleImageId]);
      expect(backend.sources, isNot(contains(_labels)));
      expect(backend.layerIds, isNot(contains(_labels)));
    });

    test('a failing painter adds no labels and does not throw', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final (map, backend) = await _loaded();
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
        expect(backend.layerIds, isNot(contains(_labels)));
        expect(_optionLayerIds(backend), hasLength(4));
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
      final (map, backend) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_routes, 0);
      await _settle();
      backend.calls.clear();
      const colors = RouteLabelColors(fill: Color(0xFF000000));
      map.labelColors = colors;
      await _settle();
      expect(painter.calls.skip(2).map((c) => c.$4), [colors, colors]);
      expect(backend.argsOf('addImage'), hasLength(2));
      // The lines are left alone.
      expect(backend.names, isNot(contains('removeLayer')));
    });

    test('a new selection removes the label images no longer used', () async {
      final (map, backend) = await _loaded(labels: true);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.showRouteOptions(_routes, 1);
      await _settle();
      expect(
        backend.images.keys,
        unorderedEquals([
          _Map.vehicleImageId,
          _image(0, selected: false),
          _image(1, selected: true),
        ]),
      );
    });
  });

  group('style reload', () {
    test('options survive a style change, re-added after it loads', () async {
      final painter = _Painter();
      final (map, backend) = await _loaded(labels: true, painter: painter);
      map.showRouteOptions(_three, 1);
      await _settle();
      final layers = List.of(backend.layerIds);
      final sources = Map.of(backend.sources);
      final images = Map.of(backend.images);
      expect(layers, contains(_labels));

      map.changeStyle('mapbox://styles/x');
      backend.resetStyle();
      await _settle();
      expect(backend.layerIds, isEmpty);

      await map.onStyleLoaded();
      await _settle();
      expect(backend.layerIds, layers);
      expect(backend.sources, sources);
      expect(backend.images.keys, unorderedEquals(images.keys));
      for (final id in images.keys) {
        expect(
          (backend.images[id]!.$2 as mb.StyleImageBytes).bytes,
          (images[id]!.$2 as mb.StyleImageBytes).bytes,
          reason: id,
        );
      }
      // The labels are not painted again.
      expect(painter.calls, hasLength(3));
      // The taps still reach the options.
      final taps = <int>[];
      map.onRouteOptionTap = taps.add;
      backend.tapFeature(_line(2));
      expect(taps, [2]);
    });

    test(
      'options changed while the style reloads are drawn as last shown',
      () async {
        final (map, backend) = await _loaded();
        map.showRouteOptions(_three, 1);
        await _settle();
        map.onStyleChanging();
        backend.resetStyle();
        map.showRouteOptions(_routes, 0);
        await _settle();
        expect(backend.layerIds, isEmpty);

        await map.onStyleLoaded();
        await _settle();
        expect(_optionLayerIds(backend), [
          _casing(1),
          _line(1),
          _casing(0),
          _line(0),
        ]);
        expect(_optionSourceIds(backend), [_source(0), _source(1)]);
      },
    );

    test('after a failed style change the old style keeps its options and '
        'takes new ones', () async {
      final log = <String>[];
      final (map, backend) = await _loaded(log: log);
      map.showRouteOptions(_three, 1);
      await _settle();
      backend.failOnce.add('loadStyleURI');
      map.changeStyle('mapbox://styles/x');
      map.showRouteOptions(_routes, 1);
      await _settle();

      // The old style is still there: its options are brought up to date.
      expect(_optionLayerIds(backend), [
        _casing(0),
        _line(0),
        _casing(1),
        _line(1),
      ]);
      expect(_optionSourceIds(backend), [_source(0), _source(1)]);
      expect(log, [contains('loadStyleURI failed')]);
    });

    test('options cleared while the style reloads are not drawn', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.onStyleChanging();
      backend.resetStyle();
      map.clearRouteOptions();
      await map.onStyleLoaded();
      await _settle();
      expect(_optionLayerIds(backend), isEmpty);
      expect(_optionSourceIds(backend), isEmpty);
    });
  });

  group('clearRouteOptions', () {
    test('removes the sources, layers and images, layers first', () async {
      final (map, backend) = await _loaded(labels: true);
      map.showRouteOptions(_three, 1);
      await _settle();
      backend.calls.clear();

      map.clearRouteOptions();
      await _settle();
      expect(_optionLayerIds(backend), isEmpty);
      expect(_optionSourceIds(backend), isEmpty);
      expect(backend.layerIds, [_driven, _ahead, _vehicle]);
      // The fake throws when a source still in use is removed.
      expect(backend.argsOf('removeSource'), hasLength(4));
      expect(
        backend.argsOf('removeImage'),
        unorderedEquals([
          _image(0, selected: false),
          _image(1, selected: true),
          _image(2, selected: false),
        ]),
      );
      expect(backend.images.keys, [_Map.vehicleImageId]);
      expect(backend.argsOf('addImage'), isEmpty);
    });

    test('drops the pending fit', () async {
      final backend = RecordingBackend();
      final map = MapboxNavigationMap()
        ..log = <String>[].add
        ..attachBackend(backend);
      await map.fitRoutes(_routes, _padding);
      map.clearRouteOptions();
      map.viewportSize = _viewport;
      await _settle();
      expect(backend.names, isNot(contains('setCamera')));
      expect(backend.names, isNot(contains('easeTo')));
    });

    test('with nothing shown, does nothing', () async {
      final (map, backend) = await _loaded();
      backend.calls.clear();
      map.clearRouteOptions();
      await _settle();
      expect(backend.calls, isEmpty);
    });
  });

  group('fitRoutes', () {
    test(
      'eases to the fitted camera, with the padding as mapPadding',
      () async {
        final (map, backend) = await _loaded();
        const focus = EdgeInsets.only(top: 400, bottom: 80);
        map
          ..padding = focus
          ..viewportSize = _viewport;
        await map.fitRoutes(_routes, _padding);

        _expectFitted(
          backend.argsOf('easeTo').single,
          fitCameraToBounds(
            _allPoints(_routes),
            _viewport,
            _padding,
            mapPadding: focus,
          ),
          focus,
        );
      },
    );

    test(
      'a pending fit is applied once, with the padding set meanwhile',
      () async {
        final map = MapboxNavigationMap()..log = <String>[].add;
        await map.fitRoutes(_routes, _padding);
        const focus = EdgeInsets.only(top: 300);
        map.padding = focus;
        final backend = RecordingBackend();
        map.attachBackend(backend);
        await _settle();
        expect(backend.names, isNot(contains('setCamera')), reason: 'no size');

        map.viewportSize = _viewport;
        await _settle();
        _expectFitted(
          backend.argsOf('setCamera').single,
          fitCameraToBounds(
            _allPoints(_routes),
            _viewport,
            _padding,
            mapPadding: focus,
          ),
          focus,
        );

        map.viewportSize = const Size(300, 600);
        map.attachBackend(backend);
        await _settle();
        expect(backend.argsOf('setCamera'), hasLength(1));
        expect(backend.argsOf('easeTo'), isEmpty);
      },
    );

    test('a newer fit replaces a pending one', () async {
      final map = MapboxNavigationMap()..log = <String>[].add;
      await map.fitRoutes(_routes, _padding);
      await map.fitRoutes([_south], EdgeInsets.zero);
      final backend = RecordingBackend();
      map
        ..attachBackend(backend)
        ..viewportSize = _viewport;
      await _settle();
      _expectFitted(
        backend.argsOf('setCamera').single,
        fitCameraToBounds(_south.points, _viewport, EdgeInsets.zero),
        EdgeInsets.zero,
      );
    });

    test('no routes, no fit', () async {
      final (map, backend) = await _loaded();
      map.viewportSize = _viewport;
      await map.fitRoutes(const [], _padding);
      await _settle();
      expect(backend.names, isNot(contains('easeTo')));
    });

    test('a camera error is logged, not thrown', () async {
      final log = <String>[];
      final (map, backend) = await _loaded(log: log);
      map.viewportSize = _viewport;
      backend.failOnce.add('easeTo');
      await map.fitRoutes(_routes, _padding);
      expect(log, [contains('easeTo failed')]);
    });

    test('a pending fit is dropped on dispose', () async {
      final map = MapboxNavigationMap()..log = <String>[].add;
      await map.fitRoutes(_routes, _padding);
      map.dispose();
      final backend = RecordingBackend();
      map
        ..attachBackend(backend)
        ..viewportSize = _viewport;
      await _settle();
      expect(backend.names, isNot(contains('setCamera')));
    });
  });

  group('colour changes while options are shown', () {
    test('alternativeColor updates the muted line paint', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_three, 1);
      await _settle();
      backend.calls.clear();

      const color = Color(0xFF123456);
      map.alternativeColor = color;
      await _settle();
      final sets = _restyles(backend);
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
      expect(sets[_line(0)]!.lineColor, color.toARGB32());
      expect(sets[_line(2)]!.lineColor, color.toARGB32());
      expect(
        sets[_casing(0)]!.lineColor,
        Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!.toARGB32(),
      );
      expect(sets[_line(1)]!.lineColor, const RouteColors().ahead.toARGB32());
      // Restyled in place: nothing is removed or added.
      expect(backend.names, isNot(contains('removeLayer')));
      expect(backend.names, isNot(contains('addLayer')));
    });

    test('routeColors update the selected line paint', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      backend.calls.clear();

      const ahead = Color(0xFFFF0000);
      map.routeColors = const RouteColors(ahead: ahead, aheadWidth: 10);
      await _settle();
      final sets = _restyles(backend);
      expect(sets[_line(0)]!.lineColor, ahead.toARGB32());
      expect(sets[_line(0)]!.lineWidth, 10);
      expect(
        sets[_casing(0)]!.lineColor,
        Color.lerp(ahead, const Color(0xFF000000), 0.35)!.toARGB32(),
      );
      expect(sets[_casing(0)]!.lineWidth, 14);
      expect(sets[_line(1)]!.lineColor, _alternative.toARGB32());
      // The session's own lines are restyled too.
      expect(sets[_ahead]!.lineColor, ahead.toARGB32());
    });

    test('the same colour does nothing', () async {
      final (map, backend) = await _loaded();
      map.showRouteOptions(_routes, 0);
      await _settle();
      backend.calls.clear();
      map.alternativeColor = _alternative;
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('nothing is drawn after clearRouteOptions', () async {
      final (map, backend) = await _loaded(labels: true);
      map.showRouteOptions(_routes, 0);
      await _settle();
      map.clearRouteOptions();
      await _settle();
      backend.calls.clear();
      map
        ..alternativeColor = const Color(0xFF123456)
        ..labelColors = const RouteLabelColors(fill: Color(0xFF000000));
      await _settle();
      expect(backend.calls, isEmpty);
    });
  });

  group('night', () {
    const custom = 'mapbox://styles/me/day';
    const customNight = 'mapbox://styles/me/night';

    test('the Standard style switches its light preset, other styles their '
        'night style', () {
      const standard = mb.MapboxStyles.STANDARD;
      expect(dayNightStyle(standard, null, night: false), (
        styleUri: standard,
        lightPreset: 'day',
      ));
      expect(dayNightStyle(standard, null, night: true), (
        styleUri: standard,
        lightPreset: 'night',
      ));
      // The Standard style never reloads for the night.
      expect(dayNightStyle(standard, customNight, night: true), (
        styleUri: standard,
        lightPreset: 'night',
      ));
      expect(dayNightStyle(custom, customNight, night: false), (
        styleUri: custom,
        lightPreset: null,
      ));
      expect(dayNightStyle(custom, customNight, night: true), (
        styleUri: customNight,
        lightPreset: null,
      ));
      // Without a night style the day style stays.
      expect(dayNightStyle(custom, null, night: true), (
        styleUri: custom,
        lightPreset: null,
      ));
    });

    test('Standard night sets lightPreset and does not reload the style: the '
        'options stay', () async {
      final (map, backend) = await _loaded(labels: true);
      map.showRouteOptions(_three, 1);
      await _settle();
      final layers = List.of(backend.layerIds);
      backend.calls.clear();

      map.lightPreset = dayNightStyle(
        mb.MapboxStyles.STANDARD,
        null,
        night: true,
      ).lightPreset;
      await _settle();
      expect(backend.calls, [
        ('setStyleImportConfigProperty', ('basemap', 'lightPreset', 'night')),
      ]);
      expect(backend.layerIds, layers);

      backend.calls.clear();
      map.lightPreset = 'day';
      await _settle();
      expect(backend.calls, [
        ('setStyleImportConfigProperty', ('basemap', 'lightPreset', 'day')),
      ]);
      // Still ready: drawing goes on in the same style.
      backend.calls.clear();
      map.showRouteOptions(_three, 0);
      await _settle();
      expect(backend.names, isNot(contains('loadStyleURI')));
      // Six lines, and the labels.
      expect(_optionLayerIds(backend), hasLength(7));
      expect(_optionLayerIds(backend).first, _casing(1));
    });

    test('the light preset is applied to each style that loads', () async {
      final backend = RecordingBackend();
      final map = MapboxNavigationMap()
        ..log = <String>[].add
        ..lightPreset = 'night'
        ..attachBackend(backend);
      await _settle();
      expect(backend.calls, isEmpty, reason: 'no style yet');

      await map.onStyleLoaded();
      expect(backend.config[('basemap', 'lightPreset')], 'night');

      map.changeStyle(mb.MapboxStyles.STANDARD);
      backend.resetStyle();
      await map.onStyleLoaded();
      expect(backend.config[('basemap', 'lightPreset')], 'night');
    });

    test('a style load sets the light preset first: a night start does not '
        'flash day (M10)', () async {
      final backend = RecordingBackend();
      final map = MapboxNavigationMap()
        ..log = <String>[].add
        ..lightPreset = 'night'
        ..attachBackend(backend);
      await map.onStyleLoaded();
      expect(backend.names.first, 'setStyleImportConfigProperty');
      expect(backend.names, contains('addImage'));
      expect(backend.names, contains('addLayer'));
      expect(
        backend.names.where((n) => n == 'setStyleImportConfigProperty'),
        hasLength(1),
      );
    });

    test('a light preset set while the style loads is applied once it has '
        'loaded', () async {
      final gate = Completer<void>();
      final backend = RecordingBackend()..addImageGate = gate;
      final map = MapboxNavigationMap()
        ..log = <String>[].add
        ..lightPreset = 'night'
        ..attachBackend(backend);
      final loading = map.onStyleLoaded();
      // The load waits on the vehicle image, the layers still to come.
      await backend.imageAdded(MapboxNavigationMap.vehicleImageId);
      expect(backend.config[('basemap', 'lightPreset')], 'night');
      map.lightPreset = 'day';
      gate.complete();
      await loading;
      await _settle();
      expect(backend.config[('basemap', 'lightPreset')], 'day');
    });

    test('no light preset, no import config', () async {
      final (map, backend) = await _loaded();
      map.lightPreset = null;
      await _settle();
      expect(backend.names, isNot(contains('setStyleImportConfigProperty')));
    });

    test('a light preset set while the style changes waits for it', () async {
      final (map, backend) = await _loaded();
      map.changeStyle(mb.MapboxStyles.STANDARD);
      backend.resetStyle();
      map.lightPreset = 'night';
      await _settle();
      expect(backend.names, isNot(contains('setStyleImportConfigProperty')));
      await map.onStyleLoaded();
      expect(backend.argsOf('setStyleImportConfigProperty'), [
        ('basemap', 'lightPreset', 'night'),
      ]);
    });

    test('a custom nightStyleUri reloads the style and re-adds the '
        'options', () async {
      final (map, backend) = await _loaded(labels: true);
      map.showRouteOptions(_three, 1);
      await _settle();
      final layers = List.of(backend.layerIds);
      final sources = Map.of(backend.sources);
      backend.calls.clear();

      final night = dayNightStyle(custom, customNight, night: true);
      map
        ..changeStyle(night.styleUri)
        ..lightPreset = night.lightPreset;
      await _settle();
      expect(backend.calls, [('loadStyleURI', customNight)]);

      backend.resetStyle();
      await map.onStyleLoaded();
      await _settle();
      expect(backend.layerIds, layers);
      expect(backend.sources, sources);
      expect(backend.names, isNot(contains('setStyleImportConfigProperty')));
    });
  });
}
