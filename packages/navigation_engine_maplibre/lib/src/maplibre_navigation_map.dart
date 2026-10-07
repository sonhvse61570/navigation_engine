import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// Not part of the public API (hidden by the library export).
LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The camera position a [CameraTarget] stands for. Not part of the public
/// API (hidden by the library export).
CameraPosition toCameraPosition(CameraTarget t) => CameraPosition(
  target: toLatLng(t.position),
  zoom: t.zoom,
  bearing: t.bearing,
  tilt: t.tilt,
);

/// The route line's paint. Every property is sent each time: a null would
/// reset it to the default when re-applied.
LineLayerProperties _lineProperties(Color color, double width) =>
    LineLayerProperties(
      lineColor: _hex(color),
      lineWidth: width,
      lineOpacity: color.a,
      lineCap: 'round',
      lineJoin: 'round',
    );

/// [NavigationMap] and [VehicleMarkerMap] on top of maplibre_gl.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapLibreMap` callbacks.
/// Camera updates are dropped until the controller exists; the route line
/// and the vehicle are kept and drawn once the style has loaded (and again
/// after a style reload).
///
/// The source, layer and image ids are reserved (see [drivenSource],
/// [aheadSource], [vehicleSource], [vehicleImageId]): do not reuse them.
class MapLibreNavigationMap implements NavigationMap, VehicleMarkerMap {
  /// [vehicleImage] renders the vehicle's PNG at a pixel ratio; the default
  /// is the default [CarPuck]. Use `vehicleImageFor(puck)` to render a
  /// `CarPuck` with its own size and colour.
  MapLibreNavigationMap({
    RouteColors routeColors = const RouteColors(),
    VehicleImageBuilder? vehicleImage,
  }) : _routeColors = routeColors,
       _vehicleImage = vehicleImage ?? vehicleImageFor(const CarPuck());

  static const drivenSource = 'navigation_engine_driven';
  static const aheadSource = 'navigation_engine_ahead';
  static const vehicleSource = 'navigation_engine_vehicle';
  static const drivenLayer = '$drivenSource-line';
  static const aheadLayer = '$aheadSource-line';
  static const vehicleImageId = 'navigation_engine_puck';

  /// Where debug reports go; defaults to `debugPrint`. Tests inject a sink.
  @visibleForTesting
  void Function(String message)? log;

  final VehicleImageBuilder _vehicleImage;
  RouteColors _routeColors;
  double _pixelRatio = 3;

  MapLibreMapController? _controller;
  bool _styleReady = false;
  int _styleGeneration = 0;
  Uint8List? _puckPng;
  EdgeInsets _padding = EdgeInsets.zero;
  List<GeoPoint> _driven = const [];
  List<GeoPoint> _ahead = const [];
  GeoPoint? _vehicle;
  double _vehicleBearing = 0;
  final _reportedErrors = <Type>{};

  RouteColors get routeColors => _routeColors;

  /// Re-styles the route lines when the style is ready; otherwise the new
  /// colours apply when the layers are added.
  set routeColors(RouteColors value) {
    final old = _routeColors;
    if (value.driven == old.driven &&
        value.ahead == old.ahead &&
        value.drivenWidth == old.drivenWidth &&
        value.aheadWidth == old.aheadWidth) {
      return;
    }
    _routeColors = value;
    if (!_styleReady) return;
    for (final (id, props) in [
      (drivenLayer, _lineProperties(value.driven, value.drivenWidth)),
      (aheadLayer, _lineProperties(value.ahead, value.aheadWidth)),
    ]) {
      _fire(() async {
        final c = _controller;
        if (c != null) await c.setLayerProperties(id, props);
      });
    }
  }

  /// The device pixel ratio the vehicle image is rendered at (default 3).
  /// A change re-adds the image once the style is ready.
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    _puckPng = null;
    if (_styleReady) _fire(_readdImage);
  }

  Future<void> _readdImage() async {
    final c = _controller;
    if (c == null) return;
    final generation = _styleGeneration;
    final png = await _puck();
    if (generation != _styleGeneration || !_styleReady) return;
    await c.addImage(vehicleImageId, png);
  }

  /// The vehicle PNG at the current ratio, rendered once per ratio.
  Future<Uint8List> _puck() async {
    for (;;) {
      final cached = _puckPng;
      if (cached != null) return cached;
      final ratio = _pixelRatio;
      final png = await _vehicleImage(ratio);
      if (ratio == _pixelRatio) return _puckPng = png;
    }
  }

  void onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _styleReady = false;
    _fire(_applyPadding);
  }

  /// Call when the style is about to be replaced (a new style string): the
  /// layers are gone until the SDK reports the new style via [onStyleLoaded].
  void onStyleChanging() {
    _styleGeneration++;
    _styleReady = false;
  }

  /// Adds the route and vehicle layers; call from `onStyleLoadedCallback`.
  ///
  /// Safe to call again (style reload, or a retry after a failure) and never
  /// throws: a platform error leaves the layers unready until the next call.
  Future<void> onStyleLoaded() => _guard(_loadStyle);

  Future<void> _loadStyle() async {
    final c = _controller;
    if (c == null) return;
    _styleReady = false;
    final generation = ++_styleGeneration;
    final puck = await _puck();
    if (generation != _styleGeneration) return;
    if (!await _addLayers(c, puck, generation)) return;
    _styleReady = true;
    await _pushRoute();
    await _pushVehicle();
  }

  /// Keeps the camera's focus point where the view wants it.
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    _fire(_applyPadding);
  }

  Future<void> _applyPadding() async {
    final c = _controller;
    if (c == null) return;
    await c.setPadding(
      left: _padding.left,
      top: _padding.top,
      right: _padding.right,
      bottom: _padding.bottom,
    );
  }

  /// Runs [f] without letting an error escape; a map update is best effort
  /// and the next one overwrites it. Reports each kind of error once in debug.
  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (kDebugMode && _reportedErrors.add(e.runtimeType)) {
        (log ?? debugPrint)('navigation_engine_maplibre: $e');
      }
    }
  }

  void _fire(Future<void> Function() f) => unawaited(_guard(f));

  /// A source or layer left over from an earlier attempt is not an error.
  Future<void> _tolerant(Future<void> Function() add) async {
    try {
      await add();
    } on PlatformException catch (e) {
      if (e.code != 'sourceAlreadyExists' && e.code != 'layerAlreadyExists') {
        rethrow;
      }
    }
  }

  /// Returns false when a newer style load has taken over.
  Future<bool> _addLayers(
    MapLibreMapController c,
    Uint8List puck,
    int generation,
  ) async {
    bool current() => generation == _styleGeneration;
    await c.addImage(vehicleImageId, puck);
    if (!current()) return false;
    for (final id in [drivenSource, aheadSource]) {
      await _tolerant(
        () => c.addGeoJsonSource(id, lineFeatureCollection(const [])),
      );
      if (!current()) return false;
    }
    await _tolerant(
      () => c.addGeoJsonSource(vehicleSource, pointFeatureCollection(null)),
    );
    if (!current()) return false;
    await _tolerant(
      () => c.addLineLayer(
        drivenSource,
        drivenLayer,
        _lineProperties(_routeColors.driven, _routeColors.drivenWidth),
        enableInteraction: false,
      ),
    );
    if (!current()) return false;
    await _tolerant(
      () => c.addLineLayer(
        aheadSource,
        aheadLayer,
        _lineProperties(_routeColors.ahead, _routeColors.aheadWidth),
        enableInteraction: false,
      ),
    );
    if (!current()) return false;
    // The PNG is registered at screen scale on iOS and at device density on
    // Android, so it is drawn at its natural size.
    await _tolerant(
      () => c.addSymbolLayer(
        vehicleSource,
        '$vehicleSource-symbol',
        const SymbolLayerProperties(
          iconImage: vehicleImageId,
          iconSize: 1,
          iconRotate: [Expressions.get, 'bearing'],
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: false,
      ),
    );
    return current();
  }

  @override
  Future<void> moveCamera(CameraTarget target) async {
    final c = _controller;
    if (c == null) return;
    await c.moveCamera(
      CameraUpdate.newCameraPosition(toCameraPosition(target)),
    );
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {
    _driven = driven;
    _ahead = ahead;
    _fire(_pushRoute);
  }

  @override
  void clearRoute() => showRoute(const [], const []);

  @override
  void showVehicle(GeoPoint position, double bearing) {
    _vehicle = position;
    _vehicleBearing = bearing;
    _fire(_pushVehicle);
  }

  @override
  void hideVehicle() {
    _vehicle = null;
    _fire(_pushVehicle);
  }

  Future<void> _pushRoute() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(drivenSource, lineFeatureCollection(_driven));
    await c.setGeoJsonSource(aheadSource, lineFeatureCollection(_ahead));
  }

  Future<void> _pushVehicle() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(
      vehicleSource,
      pointFeatureCollection(_vehicle, bearing: _vehicleBearing),
    );
  }
}
