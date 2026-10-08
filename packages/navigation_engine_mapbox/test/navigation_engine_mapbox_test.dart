// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/src/mapbox_navigation_map.dart' as mba;

import 'support/recording_backend.dart';

const _target = CameraTarget(
  position: GeoPoint(10.77, 106.69),
  bearing: 42,
  zoom: 17.5,
  tilt: 50,
);

const _a = GeoPoint(10, 106);
const _b = GeoPoint(10.001, 106.001);

typedef _Map = mba.MapboxNavigationMap;

/// Lets the adapter and the fake backend finish their pending work.
///
/// The fake backend answers each call after a zero-delay timer, so a chain of
/// calls needs one event-loop turn per link. Counting turns, not wall-clock
/// time, makes this independent of machine load.
Future<void> _settle() async {
  for (var turn = 0; turn < 200; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Runs [body] and returns the errors that escaped it into the zone.
Future<List<Object>> _escaped(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      await body();
      done.complete();
    },
    (e, _) {
      errors.add(e);
      if (!done.isCompleted) done.complete();
    },
  );
  await done.future;
  await _settle();
  return errors;
}

/// The width of a PNG, from its IHDR chunk.
int _pngWidth(mb.StyleImage image) =>
    ByteData.sublistView((image as mb.StyleImageBytes).bytes).getUint32(16);

/// What the maps under test reported (their debug log goes here, so the
/// test output stays quiet).
final _logs = <String>[];

/// A map on [backend] (a fresh one by default) that logs into [_logs].
(_Map, RecordingBackend) _mapOnBackend({RecordingBackend? backend, _Map? map}) {
  backend ??= RecordingBackend();
  map ??= _Map();
  map
    ..log = _logs.add
    ..attachBackend(backend);
  return (map, backend);
}

void main() {
  setUp(_logs.clear);

  group('mapbox', () {
    test('camera options: lng/lat order and padding', () {
      final o = mba.toCameraOptions(_target, const EdgeInsets.only(top: 320));
      expect(o.center!.coordinates.lng, 106.69);
      expect(o.center!.coordinates.lat, 10.77);
      // One zoom level less: see the zoom scale test below.
      expect((o.bearing, o.zoom, o.pitch), (42, 16.5, 50));
      expect((o.padding!.top, o.padding!.bottom), (320, 0));
    });

    test('CameraTarget zoom 17 becomes SDK zoom 16', () {
      // CameraTarget zooms use the 256 dp world of Google Maps and
      // flutter_map; Mapbox's 512 px tiles show the same scale one level
      // lower.
      const target = CameraTarget(
        position: GeoPoint(10.77, 106.69),
        bearing: 0,
        zoom: 17,
        tilt: 0,
      );
      expect(mba.toCameraOptions(target, EdgeInsets.zero).zoom, 16);
    });

    test('the initial zoom 17 becomes SDK zoom 16', () {
      final v = mba.toInitialViewport(const GeoPoint(10.77, 106.69), 17);
      expect(v.zoom, 16);
      expect(v.center!.coordinates.lng, 106.69);
      expect(v.center!.coordinates.lat, 10.77);
    });

    test('updates before the map exists are kept, not thrown', () async {
      final map = _Map();
      await map.moveCamera(_target);
      map.showRoute(const [GeoPoint(10, 106)], const []);
      map.showVehicle(const GeoPoint(10, 106), 0);
      map.hideVehicle();
      map.clearRoute();
    });

    test('camera moves before the map exists send nothing; after it, the '
        'camera carries the padding', () async {
      final map = _Map()..padding = const EdgeInsets.only(top: 100);
      await map.moveCamera(_target);

      final (_, backend) = _mapOnBackend(map: map);
      await _settle();
      // attaching leaves the map's ornaments alone
      expect(backend.calls, isEmpty);

      await map.moveCamera(_target);
      final o = backend.argsOf('setCamera').cast<mb.CameraOptions>().single;
      expect(backend.names, ['setCamera']);
      expect(o.center!.coordinates.lng, 106.69);
      expect((o.bearing, o.zoom, o.pitch), (42, 16.5, 50));
      expect((o.padding!.top, o.padding!.bottom), (100, 0));
    });

    test('hideOrnaments turns the compass and the scale bar off', () async {
      final (map, backend) = _mapOnBackend();
      map.hideOrnaments();
      await _settle();
      expect(backend.names, ['updateCompass', 'updateScaleBar']);
      expect(
        backend
            .argsOf('updateCompass')
            .cast<mb.CompassSettings>()
            .single
            .enabled,
        isFalse,
      );
      expect(
        backend
            .argsOf('updateScaleBar')
            .cast<mb.ScaleBarSettings>()
            .single
            .enabled,
        isFalse,
      );
    });

    group('the logo and the attribution (I4)', () {
      List<double?> logoMargins(RecordingBackend backend) => [
        for (final s in backend.argsOf('updateLogo').cast<mb.LogoSettings>())
          s.marginBottom,
      ];
      List<double?> attributionMargins(RecordingBackend backend) => [
        for (final s
            in backend
                .argsOf('updateAttribution')
                .cast<mb.AttributionSettings>())
          s.marginBottom,
      ];

      test('placeOrnaments puts them 8 above bottomInset', () async {
        final map = _Map()..bottomInset = 100;
        final (_, backend) = _mapOnBackend(map: map);
        await _settle();
        expect(backend.calls, isEmpty, reason: 'only when placed');
        map.placeOrnaments();
        await _settle();
        expect(backend.names, ['updateLogo', 'updateAttribution']);
        expect(logoMargins(backend), [108]);
        expect(attributionMargins(backend), [108]);
      });

      test('a new bottomInset places them again', () async {
        final (map, backend) = _mapOnBackend();
        map.placeOrnaments();
        await _settle();
        expect(logoMargins(backend), [8]);
        map.bottomInset = 140;
        await _settle();
        expect(logoMargins(backend), [8, 148]);
        expect(attributionMargins(backend), [8, 148]);
        map.bottomInset = 140;
        await _settle();
        expect(logoMargins(backend), [8, 148], reason: 'no change');
      });

      test('before the map exists nothing is sent', () async {
        final map = _Map()
          ..bottomInset = 60
          ..placeOrnaments();
        final (_, backend) = _mapOnBackend(map: map);
        await _settle();
        expect(backend.calls, isEmpty);
      });

      test('a failing update does not escape', () async {
        late RecordingBackend backend;
        final errors = await _escaped(() async {
          final _Map map;
          (map, backend) = _mapOnBackend(
            backend: RecordingBackend()
              ..failOnce.addAll(['updateLogo', 'updateAttribution']),
          );
          map.placeOrnaments();
          await _settle();
        });
        expect(errors, isEmpty);
        expect(backend.names, ['updateLogo', 'updateAttribution']);
      });
    });

    test('hideOrnaments before the map exists does nothing', () async {
      final map = _Map()..hideOrnaments();
      final (_, backend) = _mapOnBackend(map: map);
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('a failing hideOrnaments does not escape', () async {
      late RecordingBackend backend;
      final errors = await _escaped(() async {
        final _Map map;
        (map, backend) = _mapOnBackend(
          backend: RecordingBackend()
            ..failOnce.addAll(['updateCompass', 'updateScaleBar']),
        );
        map.hideOrnaments();
        await _settle();
      });
      expect(errors, isEmpty);
      expect(backend.names, ['updateCompass', 'updateScaleBar']);
      expect(_logs, hasLength(1)); // one report per kind of error
    });

    test(
      'route and vehicle shown before the style loads are drawn after it',
      () async {
        final (map, backend) = _mapOnBackend();
        await _settle();
        backend.calls.clear();

        map.showRoute(const [_a, _b], const [_b, _a]);
        map.showVehicle(_a, 90);
        await _settle();
        expect(backend.calls, isEmpty);

        await map.onStyleLoaded();
        expect(backend.names, [
          'addImage',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addLayer',
          'addLayer',
          'addLayer',
          'setStyleSourceProperty',
          'setStyleSourceProperty',
          'setStyleSourceProperty',
        ]);

        final (imageId, scale, image) =
            backend.argsOf('addImage').single! as (String, double, Object);
        expect((imageId, scale), (_Map.vehicleImageId, 3));
        expect((image as mb.StyleImageBytes).bytes, isNotEmpty);

        expect(backend.argsOf('addGeoJsonSource'), [
          _Map.drivenSource,
          _Map.aheadSource,
          _Map.vehicleSource,
        ]);
        final layers = backend.argsOf('addLayer').cast<mb.Layer>().toList();
        expect(layers.map((l) => (l.runtimeType, l.id)), [
          (mb.LineLayer, '${_Map.drivenSource}-line'),
          (mb.LineLayer, '${_Map.aheadSource}-line'),
          (mb.SymbolLayer, '${_Map.vehicleSource}-symbol'),
        ]);
        const colors = RouteColors();
        final driven = layers[0] as mb.LineLayer;
        final ahead = layers[1] as mb.LineLayer;
        expect(
          (driven.lineColor, driven.lineWidth),
          (colors.driven.toARGB32(), 7),
        );
        expect(
          (ahead.lineColor, ahead.lineWidth),
          (colors.ahead.toARGB32(), 8),
        );
        final symbol = layers[2] as mb.SymbolLayer;
        expect(symbol.iconImage, _Map.vehicleImageId);
        expect(symbol.iconRotateExpression, ['get', 'bearing']);
        expect(symbol.iconRotationAlignment, mb.IconRotationAlignment.MAP);
        expect(symbol.iconAllowOverlap, isTrue);

        final pushes = backend
            .argsOf('setStyleSourceProperty')
            .cast<(String, String, Object)>()
            .toList();
        expect(pushes.map((p) => (p.$1, p.$2)), [
          (_Map.drivenSource, 'data'),
          (_Map.aheadSource, 'data'),
          (_Map.vehicleSource, 'data'),
        ]);
        expect(pushes.map((p) => jsonDecode(p.$3 as String)), [
          jsonDecode(jsonEncode(lineFeatureCollection(const [_a, _b]))),
          jsonDecode(jsonEncode(lineFeatureCollection(const [_b, _a]))),
          jsonDecode(jsonEncode(pointFeatureCollection(_a, bearing: 90))),
        ]);
      },
    );
    test(
      'a stale onStyleLoaded does not draw twice or set the style ready',
      () async {
        final (map, backend) = _mapOnBackend();
        await _settle();
        map.showRoute(const [_a, _b], const []);
        final gate = Completer<void>();
        backend.addImageGate = gate;

        final first = map.onStyleLoaded();
        await backend.addImageGateReached;
        await map.onStyleLoaded();
        final before = List.of(backend.names);
        expect(
          before.where((n) => n == 'setStyleSourceProperty'),
          hasLength(3),
        );

        gate.complete();
        await first;
        await _settle();
        expect(backend.names, before);
        expect(backend.argsOf('addGeoJsonSource'), hasLength(3));
      },
    );

    test(
      'a load overtaken by a style change does not set the style ready',
      () async {
        final (map, backend) = _mapOnBackend();
        await _settle();
        final gate = Completer<void>();
        backend.addImageGate = gate;

        final first = map.onStyleLoaded();
        await backend.addImageGateReached;
        map.onStyleChanging();
        gate.complete();
        await first;
        backend.calls.clear();

        // the new style has not loaded yet: nothing may be drawn
        map.showRoute(const [_a, _b], const []);
        map.showVehicle(_a, 0);
        await _settle();
        expect(backend.calls, isEmpty);
      },
    );

    test(
      'a style reload starts over: nothing is drawn until it has loaded',
      () async {
        final (map, backend) = _mapOnBackend();
        await map.onStyleLoaded();
        final (_, _, firstPuck) =
            backend.argsOf('addImage').single! as (String, double, Object);
        backend.calls.clear();

        map.onStyleChanging();
        backend.resetStyle();
        map.showRoute(const [_a, _b], const []);
        map.showVehicle(_b, 10);
        await _settle();
        expect(backend.calls, isEmpty);

        await map.onStyleLoaded();
        expect(backend.argsOf('addGeoJsonSource'), hasLength(3));
        expect(backend.argsOf('addLayer'), hasLength(3));
        expect(backend.argsOf('setStyleSourceProperty'), hasLength(3));
        // rendered once, reused
        final (_, _, secondPuck) =
            backend.argsOf('addImage').single! as (String, double, Object);
        expect(
          identical(
            (secondPuck as mb.StyleImageBytes).bytes,
            (firstPuck as mb.StyleImageBytes).bytes,
          ),
          isTrue,
        );
      },
    );

    test(
      'a failure while adding layers does not escape and is retried',
      () async {
        late RecordingBackend backend;
        final errors = await _escaped(() async {
          final _Map map;
          (map, backend) = _mapOnBackend();
          map.showRoute(const [_a, _b], const []);
          backend.failLayerOnce = '${_Map.aheadSource}-line';

          await map.onStyleLoaded();
          await _settle();
          // not ready: nothing was pushed
          expect(backend.argsOf('setStyleSourceProperty'), isEmpty);
          map.showVehicle(_a, 0);
          await _settle();
          expect(backend.argsOf('setStyleSourceProperty'), isEmpty);

          // the next style load tolerates what is already there and finishes
          await map.onStyleLoaded();
          await _settle();
        });
        expect(errors, isEmpty);
        expect(_logs, hasLength(1));
        expect(backend.argsOf('setStyleSourceProperty'), hasLength(3));
        expect(
          backend.argsOf('addLayer').cast<mb.Layer>().map((l) => l.id).toSet(),
          hasLength(3),
        );
      },
    );

    test('a failure while updating does not escape', () async {
      late RecordingBackend backend;
      final errors = await _escaped(() async {
        final _Map map;
        (map, backend) = _mapOnBackend(
          backend: RecordingBackend()..failOnce.add('setStyleSourceProperty'),
        );
        map.showRoute(const [_a, _b], const [_b, _a]);
        // the first push of the load fails; the other two still go out
        await map.onStyleLoaded();
        expect(backend.argsOf('setStyleSourceProperty'), hasLength(3));

        backend.failOnce.add('setStyleSourceProperty');
        map.showVehicle(_a, 0);
        await _settle();
        // later updates still go through
        backend.calls.clear();
        map.showVehicle(_b, 0);
        await _settle();
        expect(backend.argsOf('setStyleSourceProperty'), hasLength(1));
      });
      expect(errors, isEmpty);
      expect(backend.argsOf('setStyleSourceProperty'), hasLength(1));
      expect(_logs, hasLength(1)); // PlatformException, reported once
    });

    test(
      'while the style reloads, nothing is drawn into the old layers',
      () async {
        final (map, backend) = _mapOnBackend();
        await map.onStyleLoaded();
        final gate = Completer<void>();
        backend.addImageGate = gate;
        backend.calls.clear();

        // the SDK reports a reloaded style without onStyleChanging
        final reload = map.onStyleLoaded();
        await backend.addImageGateReached;
        map.showVehicle(_a, 0);
        await _settle();
        expect(backend.argsOf('setStyleSourceProperty'), isEmpty);

        gate.complete();
        await reload;
        expect(backend.argsOf('setStyleSourceProperty'), hasLength(3));
      },
    );

    test('a style load in flight at dispose stops there', () async {
      final (map, backend) = _mapOnBackend();
      await _settle();
      final gate = Completer<void>();
      backend.addImageGate = gate;

      final load = map.onStyleLoaded();
      await backend.addImageGateReached;
      map.dispose();
      gate.complete();
      await load;
      expect(backend.argsOf('addGeoJsonSource'), isEmpty);
    });

    test(
      'a style load for a replaced map does not make the new map ready',
      () async {
        final (map, old) = _mapOnBackend();
        await _settle();
        final gate = Completer<void>();
        old.addImageGate = gate;

        final load = map.onStyleLoaded();
        await old.addImageGateReached;
        final fresh = RecordingBackend();
        map.attachBackend(fresh);
        gate.complete();
        await load;

        // the new map's style has not loaded: nothing may be drawn there
        map.showVehicle(_a, 0);
        await _settle();
        expect(fresh.argsOf('setStyleSourceProperty'), isEmpty);
        expect(old.argsOf('addGeoJsonSource'), isEmpty);
      },
    );

    test(
      'changeStyle loads the new style; drawing resumes once it has loaded',
      () async {
        final (map, backend) = _mapOnBackend();
        map.showRoute(const [_a, _b], const [_b, _a]);
        await map.onStyleLoaded();
        backend.calls.clear();

        map.changeStyle('mapbox://styles/x');
        map.showVehicle(_a, 0);
        map.showRoute(const [_b, _a], const [_a, _b]);
        await _settle();
        expect(backend.calls, [('loadStyleURI', 'mapbox://styles/x')]);

        backend
          ..resetStyle()
          ..calls.clear();
        await map.onStyleLoaded();
        expect(backend.names, [
          'addImage',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addGeoJsonSource',
          'addLayer',
          'addLayer',
          'addLayer',
          'setStyleSourceProperty',
          'setStyleSourceProperty',
          'setStyleSourceProperty',
        ]);
        final pushes = backend
            .argsOf('setStyleSourceProperty')
            .cast<(String, String, Object)>()
            .map((p) => jsonDecode(p.$3 as String));
        expect(pushes, [
          jsonDecode(jsonEncode(lineFeatureCollection(const [_b, _a]))),
          jsonDecode(jsonEncode(lineFeatureCollection(const [_a, _b]))),
          jsonDecode(jsonEncode(pointFeatureCollection(_a, bearing: 0))),
        ]);
      },
    );

    test('changeStyle before the map exists does nothing', () async {
      final map = _Map()..changeStyle('mapbox://styles/x');
      final (_, backend) = _mapOnBackend(map: map);
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('a failing loadStyleURI does not escape', () async {
      late RecordingBackend backend;
      final errors = await _escaped(() async {
        final _Map map;
        (map, backend) = _mapOnBackend();
        await map.onStyleLoaded();
        backend.failOnce.add('loadStyleURI');
        map.changeStyle('mapbox://styles/x');
        await _settle();
        // a later style load still works
        backend.calls.clear();
        await map.onStyleLoaded();
      });
      expect(errors, isEmpty);
      expect(backend.argsOf('setStyleSourceProperty'), hasLength(3));
      expect(_logs, hasLength(1));
    });

    test('a failed changeStyle keeps drawing into the old style', () async {
      late RecordingBackend backend;
      final errors = await _escaped(() async {
        final _Map map;
        (map, backend) = _mapOnBackend();
        await map.onStyleLoaded();
        backend.failOnce.add('loadStyleURI');
        map.changeStyle('mapbox://styles/x');
        map.showVehicle(_a, 0); // dropped: the style is changing
        await _settle();
        backend.calls.clear();

        // the old style is still there: no onStyleLoaded will come
        map.showVehicle(_b, 0);
        await _settle();
      });
      expect(errors, isEmpty);
      expect(backend.argsOf('setStyleSourceProperty'), hasLength(1));
      expect(_logs, hasLength(1));
    });

    test('a failed changeStyle after the old style was not ready stays '
        'unready', () async {
      final (map, backend) = _mapOnBackend();
      await _settle();
      backend.failOnce.add('loadStyleURI');
      map.changeStyle('mapbox://styles/x');
      await _settle();
      backend.calls.clear();
      map.showVehicle(_b, 0);
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('a failed changeStyle does not undo a newer style change', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.failOnce.add('loadStyleURI');
      map.changeStyle('mapbox://styles/x');
      map.onStyleChanging(); // something newer took over
      await _settle();
      backend.calls.clear();
      map.showVehicle(_b, 0);
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('after dispose nothing is sent', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.calls.clear();

      map.dispose();
      await map.moveCamera(_target);
      map.showRoute(const [_a, _b], const []);
      map.showVehicle(_a, 0);
      await map.onStyleLoaded();
      await _settle();
      expect(backend.calls, isEmpty);
    });
  });

  group('vehicle image', () {
    test('rendered at 3x by default; the scale is the same 3', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      final (_, scale, image) =
          backend.argsOf('addImage').single! as (String, double, mb.StyleImage);
      expect(scale, 3);
      expect(_pngWidth(image), 132); // the default CarPuck is 44 logical px
    });

    test('a CarPuck(size: 30) at ratio 2: scale 2, PNG 60 px wide', () async {
      final (map, backend) = _mapOnBackend(
        map: _Map(vehicleImage: vehicleImageFor(const CarPuck(size: 30))),
      );
      map.pixelRatio = 2;
      await map.onStyleLoaded();
      final (_, scale, image) =
          backend.argsOf('addImage').single! as (String, double, mb.StyleImage);
      expect(scale, 2);
      expect(_pngWidth(image), 60);
    });

    test('a ratio change after the style is ready re-adds the image', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.calls.clear();

      map.pixelRatio = 2;
      await _settle();
      final (id, scale, image) =
          backend.argsOf('addImage').single! as (String, double, mb.StyleImage);
      expect((id, scale, _pngWidth(image)), (_Map.vehicleImageId, 2, 88));
    });

    test('a ratio change before the style is ready adds nothing', () async {
      final (map, backend) = _mapOnBackend();
      map.pixelRatio = 2;
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('an equal ratio does nothing', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.calls.clear();
      map.pixelRatio = 3;
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('a ratio change while the first image renders wins', () async {
      final gate = Completer<void>();
      final firstRender = Completer<void>();
      final ratios = <double>[];
      final (map, backend) = _mapOnBackend(
        map: _Map(
          vehicleImage: (r) async {
            ratios.add(r);
            if (ratios.length == 1) {
              firstRender.complete();
              await gate.future;
            }
            return CarPuck.toPngBytes(size: 10, pixelRatio: r);
          },
        ),
      );
      final load = map.onStyleLoaded();
      await firstRender.future;
      map.pixelRatio = 2;
      gate.complete();
      await load;
      final (_, scale, image) =
          backend.argsOf('addImage').single! as (String, double, mb.StyleImage);
      expect((scale, _pngWidth(image)), (2, 20));
      expect(ratios, [3, 2]);
    });
  });

  group('routeColors', () {
    const red = RouteColors(ahead: Color(0xFFFF0000), aheadWidth: 12);

    test('a change re-styles the lines of a ready style', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.calls.clear();

      map.routeColors = red;
      await _settle();
      final layers = backend.argsOf('updateLayer').cast<mb.LineLayer>();
      expect(layers.map((l) => l.id), [_Map.drivenLayer, _Map.aheadLayer]);
      final ahead = layers.last;
      expect((ahead.lineColor, ahead.lineWidth), (0xFFFF0000, 12));
      expect(layers.first.lineColor, const RouteColors().driven.toARGB32());
      expect(backend.names, ['updateLayer', 'updateLayer']);
    });

    test('a change before the style is ready applies when it loads', () async {
      final (map, backend) = _mapOnBackend();
      map.routeColors = red;
      await _settle();
      expect(backend.calls, isEmpty);

      await map.onStyleLoaded();
      final ahead = backend
          .argsOf('addLayer')
          .cast<mb.Layer>()
          .whereType<mb.LineLayer>()
          .last;
      expect((ahead.lineColor, ahead.lineWidth), (0xFFFF0000, 12));
    });

    test('equal colours do nothing', () async {
      final (map, backend) = _mapOnBackend();
      await map.onStyleLoaded();
      backend.calls.clear();
      map.routeColors = const RouteColors();
      await _settle();
      expect(backend.calls, isEmpty);
    });

    test('a failing re-style does not escape', () async {
      late RecordingBackend backend;
      final errors = await _escaped(() async {
        final _Map map;
        (map, backend) = _mapOnBackend();
        await map.onStyleLoaded();
        backend.failOnce.add('updateLayer');
        map.routeColors = red;
        await _settle();
      });
      expect(errors, isEmpty);
      expect(backend.argsOf('updateLayer'), hasLength(2));
      expect(_logs, hasLength(1));
    });
  });
}
