// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart'
    as mla;
import 'package:navigation_engine_maplibre/src/maplibre_navigation_map.dart'
    as src;

const _target = CameraTarget(
  position: GeoPoint(10.77, 106.69),
  bearing: 42,
  zoom: 17.5,
  tilt: 50,
);

const _a = GeoPoint(10, 106);
const _b = GeoPoint(10.001, 106.001);

/// A platform that records what the controller sends and can be told to
/// fail or to hold a call back. Only the calls the adapter makes are
/// implemented.
class RecordingPlatform extends ml.MapLibrePlatform {
  final calls = <(String, Object?)>[];
  final _sources = <String>{};

  /// Held back until completed; consumed by the first addImage call.
  Completer<void>? addImageGate;

  /// Methods that throw once, by name.
  final failOnce = <String>{};

  // Everything not overridden below is not expected to be called.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Iterable<String> get names => calls.map((c) => c.$1);
  Iterable<Object?> argsOf(String name) =>
      calls.where((c) => c.$1 == name).map((c) => c.$2);

  Future<void> _record(String name, Object? arg) async {
    calls.add((name, arg));
    if (failOnce.remove(name)) throw StateError('$name failed');
  }

  @override
  Future<void> updateContentInsets(EdgeInsets insets, bool animated) =>
      _record('updateContentInsets', insets);

  @override
  Future<void> addImage(
    String name,
    Uint8List bytes, [
    bool sdf = false,
  ]) async {
    final gate = addImageGate;
    addImageGate = null;
    await _record('addImage', bytes);
    if (gate != null) await gate.future;
  }

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson, {
    String? promoteId,
  }) async {
    await _record('addGeoJsonSource', sourceId);
    if (!_sources.add(sourceId)) {
      throw PlatformException(code: 'sourceAlreadyExists');
    }
  }

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) => _record('setGeoJsonSource', (sourceId, geojson));

  @override
  Future<void> addLineLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) => _record('addLineLayer', (layerId, properties));

  @override
  Future<void> setLayerProperties(
    String layerId,
    Map<String, dynamic> properties,
  ) => _record('setLayerProperties', (layerId, properties));

  @override
  Future<void> addSymbolLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) => _record('addSymbolLayer', properties);

  @override
  Future<bool?> moveCamera(ml.CameraUpdate cameraUpdate) async {
    await _record('moveCamera', cameraUpdate);
    return true;
  }
}

ml.MapLibreMapController _controller(RecordingPlatform platform) =>
    ml.MapLibreMapController(
      maplibrePlatform: platform,
      annotationOrder: const [],
      annotationConsumeTapEvents: const [],
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue, reason: 'timed out waiting');
}

/// The width of a PNG, from its IHDR chunk.
int _pngWidth(Uint8List png) => ByteData.sublistView(png).getUint32(16);

(mla.MapLibreNavigationMap, RecordingPlatform) _mapOnPlatform({
  VehicleImageBuilder? vehicleImage,
  RouteColors routeColors = const RouteColors(),
  List<String>? log,
}) {
  final platform = RecordingPlatform();
  final map =
      mla.MapLibreNavigationMap(
          vehicleImage: vehicleImage,
          routeColors: routeColors,
        )
        // error-path tests must not print
        ..log = (log ?? <String>[]).add
        ..onMapCreated(_controller(platform));
  return (map, platform);
}

void main() {
  group('maplibre', () {
    test('camera position', () {
      final p = src.toCameraPosition(_target);
      expect(p.target, const ml.LatLng(10.77, 106.69));
      expect((p.bearing, p.zoom, p.tilt), (42, 17.5, 50));
    });

    test('camera updates before the map exists are dropped, not thrown', () {
      expect(mla.MapLibreNavigationMap().moveCamera(_target), completes);
    });

    test(
      'padding set before the controller exists is sent on creation',
      () async {
        final map = mla.MapLibreNavigationMap()
          ..padding = const EdgeInsets.only(top: 100);
        final platform = RecordingPlatform();
        map.onMapCreated(_controller(platform));
        await _settle();
        expect(platform.argsOf('updateContentInsets'), [
          const EdgeInsets.only(top: 100),
        ]);
      },
    );

    test(
      'route and vehicle shown before the style loads are drawn after it',
      () async {
        final (map, platform) = _mapOnPlatform();
        await _settle();
        platform.calls.clear();

        map.showRoute(const [_a, _b], const [_b, _a]);
        map.showVehicle(_a, 90);
        await _settle();
        expect(platform.calls, isEmpty);

        await map.onStyleLoaded();
        expect(platform.names, [
          'addImage',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addLineLayer',
          'addLineLayer',
          'addSymbolLayer',
          'setGeoJsonSource',
          'setGeoJsonSource',
          'setGeoJsonSource',
        ]);
        final sets = platform
            .argsOf('setGeoJsonSource')
            .cast<(String, Object?)>();
        expect(sets.map((s) => s.$1), [
          mla.MapLibreNavigationMap.drivenSource,
          mla.MapLibreNavigationMap.aheadSource,
          mla.MapLibreNavigationMap.vehicleSource,
        ]);
        // the driven line has one point, the ahead line has one, the vehicle is
        // a point feature: none of them is the empty collection
        for (final s in sets) {
          final features = (s.$2! as Map<String, dynamic>)['features'] as List;
          expect(features, isNotEmpty, reason: s.$1);
        }
      },
    );

    test('the vehicle icon is registered at its natural size', () async {
      final (map, platform) = _mapOnPlatform();
      await map.onStyleLoaded();
      final props =
          platform.argsOf('addSymbolLayer').single! as Map<String, dynamic>;
      expect(props['icon-size'], 1);
    });

    test('the vehicle image is rendered at 3x by default', () async {
      final (map, platform) = _mapOnPlatform();
      await map.onStyleLoaded();
      expect(_pngWidth(platform.argsOf('addImage').single! as Uint8List), 132);
    });

    test('pixelRatio sets the size of the vehicle image', () async {
      final (map, platform) = _mapOnPlatform();
      map.pixelRatio = 2;
      await map.onStyleLoaded();
      expect(_pngWidth(platform.argsOf('addImage').single! as Uint8List), 88);
      final props =
          platform.argsOf('addSymbolLayer').single! as Map<String, dynamic>;
      expect(props['icon-size'], 1);
    });

    test('a ratio change once the style is ready re-adds the image', () async {
      final (map, platform) = _mapOnPlatform();
      await map.onStyleLoaded();
      map.pixelRatio = 2;
      await _settle();
      final widths = platform
          .argsOf('addImage')
          .map((b) => _pngWidth(b! as Uint8List));
      expect(widths, [132, 88]);
    });

    test('a ratio change before the style is ready adds nothing', () async {
      final (map, platform) = _mapOnPlatform();
      await _settle();
      platform.calls.clear();
      map.pixelRatio = 2;
      await _settle();
      expect(platform.calls, isEmpty);
    });

    test('a ratio change while the first image renders wins', () async {
      final (map, platform) = _mapOnPlatform();
      final load = map.onStyleLoaded();
      map.pixelRatio = 2;
      await load;
      expect(
        platform.argsOf('addImage').map((b) => _pngWidth(b! as Uint8List)),
        [88],
      );
    });

    test('vehicleImage renders the image of a custom CarPuck', () async {
      final (map, platform) = _mapOnPlatform(
        vehicleImage: vehicleImageFor(const CarPuck(size: 30)),
      );
      map.pixelRatio = 2;
      await map.onStyleLoaded();
      expect(_pngWidth(platform.argsOf('addImage').single! as Uint8List), 60);
    });

    test('vehicleImage is asked for the current pixel ratio', () async {
      final ratios = <double>[];
      final (map, platform) = _mapOnPlatform(
        vehicleImage: (r) {
          ratios.add(r);
          return CarPuck.toPngBytes(size: 10, pixelRatio: r);
        },
      );
      map.pixelRatio = 2.5;
      await map.onStyleLoaded();
      expect(ratios, [2.5]);
      expect(platform.argsOf('addImage'), hasLength(1));
    });

    test('line layers keep the alpha of the colour as line-opacity', () async {
      final (map, platform) = _mapOnPlatform(
        routeColors: const RouteColors(ahead: Color(0x80FF0000)),
      );
      await map.onStyleLoaded();
      final layers = {
        for (final a
            in platform.argsOf('addLineLayer').cast<(String, Object?)>())
          a.$1: a.$2! as Map<String, dynamic>,
      };
      final ahead = layers['${mla.MapLibreNavigationMap.aheadSource}-line']!;
      expect(ahead['line-color'], '#ff0000');
      expect(ahead['line-opacity'], closeTo(0.5, 0.01));
      final driven = layers['${mla.MapLibreNavigationMap.drivenSource}-line']!;
      expect(driven['line-opacity'], 1.0);
    });

    test(
      'routeColors set once the style is ready re-style the lines',
      () async {
        final (map, platform) = _mapOnPlatform();
        await map.onStyleLoaded();
        map.routeColors = const RouteColors(
          driven: Color(0xFF00FF00),
          ahead: Color(0x80FF0000),
          drivenWidth: 3,
          aheadWidth: 4,
        );
        await _settle();
        final sets = {
          for (final a
              in platform
                  .argsOf('setLayerProperties')
                  .cast<(String, Object?)>())
            a.$1: a.$2! as Map<String, dynamic>,
        };
        final ahead = sets['${mla.MapLibreNavigationMap.aheadSource}-line']!;
        expect(ahead['line-color'], '#ff0000');
        expect(ahead['line-width'], 4);
        expect(ahead['line-opacity'], closeTo(0.5, 0.01));
        // properties are not skipped when null: the cap and join are re-sent
        expect(ahead['line-cap'], 'round');
        expect(ahead['line-join'], 'round');
        final driven = sets['${mla.MapLibreNavigationMap.drivenSource}-line']!;
        expect(driven['line-color'], '#00ff00');
        expect(driven['line-width'], 3);
        expect(sets, hasLength(2));
      },
    );

    test(
      'routeColors set before the style is ready apply when it loads',
      () async {
        final (map, platform) = _mapOnPlatform();
        await _settle();
        map.routeColors = const RouteColors(ahead: Color(0xFFFF0000));
        await _settle();
        expect(platform.names, isNot(contains('setLayerProperties')));
        await map.onStyleLoaded();
        final ahead = platform
            .argsOf('addLineLayer')
            .cast<(String, Object?)>()
            .firstWhere(
              (a) => a.$1 == '${mla.MapLibreNavigationMap.aheadSource}-line',
            );
        expect((ahead.$2! as Map)['line-color'], '#ff0000');
      },
    );

    test('equal routeColors do not touch the layers', () async {
      final (map, platform) = _mapOnPlatform();
      await map.onStyleLoaded();
      map.routeColors = const RouteColors();
      await _settle();
      expect(platform.names, isNot(contains('setLayerProperties')));
    });

    test('a failing re-style does not escape', () async {
      final (map, platform) = _mapOnPlatform();
      await map.onStyleLoaded();
      platform.failOnce.add('setLayerProperties');
      map.routeColors = const RouteColors(ahead: Color(0xFFFF0000));
      await _settle();
      expect(platform.argsOf('setLayerProperties'), hasLength(2));
    });

    test(
      'a style reload starts over: nothing is drawn until it has loaded',
      () async {
        final (map, platform) = _mapOnPlatform();
        await map.onStyleLoaded();
        final firstPuck = platform.argsOf('addImage').single! as Uint8List;
        platform.calls.clear();

        map.onStyleChanging();
        map.showRoute(const [_a, _b], const []);
        map.showVehicle(_b, 10);
        await _settle();
        expect(platform.calls, isEmpty);

        platform.calls.clear();
        await map.onStyleLoaded();
        expect(platform.argsOf('setGeoJsonSource'), hasLength(3));
        // rendered once, reused
        expect(
          identical(platform.argsOf('addImage').single, firstPuck),
          isTrue,
        );
      },
    );

    test(
      'a stale onStyleLoaded does not draw or set the style ready',
      () async {
        final (map, platform) = _mapOnPlatform();
        map.showRoute(const [_a, _b], const []);
        final gate = Completer<void>();
        platform.addImageGate = gate;

        final first = map.onStyleLoaded();
        await _until(() => platform.names.contains('addImage'));
        final second = map.onStyleLoaded();
        await second;
        final before = List.of(platform.names);
        expect(before.where((n) => n == 'setGeoJsonSource'), hasLength(3));

        gate.complete();
        await first;
        expect(platform.names, before);
        expect(platform.argsOf('addGeoJsonSource'), hasLength(3));
        expect(platform.argsOf('setGeoJsonSource'), hasLength(3));
      },
    );

    test(
      'a failure while adding layers does not escape and is retried',
      () async {
        final errors = <Object>[];
        final log = <String>[];
        await runZonedGuarded(() async {
          final (map, platform) = _mapOnPlatform(log: log);
          map.showRoute(const [_a, _b], const []);
          platform.failOnce.add('addLineLayer');

          await map.onStyleLoaded();
          await _settle();
          // not ready: nothing was pushed
          expect(platform.argsOf('setGeoJsonSource'), isEmpty);

          // the next style load tolerates what is already there and finishes
          await map.onStyleLoaded();
          expect(platform.argsOf('setGeoJsonSource'), hasLength(3));
          expect(platform.argsOf('addSymbolLayer'), hasLength(1));
        }, (e, _) => errors.add(e));
        expect(errors, isEmpty);
        expect(log, [contains('addLineLayer failed')]);
      },
    );

    test('a failure while updating does not escape', () async {
      final errors = <Object>[];
      final log = <String>[];
      await runZonedGuarded(() async {
        final (map, platform) = _mapOnPlatform(log: log);
        await map.onStyleLoaded();
        platform.failOnce
          ..add('setGeoJsonSource')
          ..add('updateContentInsets');
        map.showRoute(const [_a, _b], const []);
        map.showVehicle(_a, 0);
        map.padding = const EdgeInsets.only(top: 10);
        await _settle();
        // later updates still go through
        platform.calls.clear();
        map.showVehicle(_b, 0);
        await _settle();
        expect(platform.argsOf('setGeoJsonSource'), hasLength(1));
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
      // one report per kind of error
      expect(log, hasLength(1));
    });
  });
}
