import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// Mapbox geometry for a [GeoPoint] (Mapbox positions are lng, lat).
Point toPoint(GeoPoint p) => Point(coordinates: Position(p.lng, p.lat));

/// The camera options a [CameraTarget] stands for, with [padding] putting
/// the camera centre at the view's focus point.
CameraOptions toCameraOptions(CameraTarget t, EdgeInsets padding) =>
    CameraOptions(
      center: toPoint(t.position),
      zoom: t.zoom,
      bearing: t.bearing,
      pitch: t.tilt,
      padding: MbxEdgeInsets(
        top: padding.top,
        left: padding.left,
        bottom: padding.bottom,
        right: padding.right,
      ),
    );

/// The few map calls [MapboxNavigationMap] makes. In an app they go to the
/// `MapboxMap` given to [MapboxNavigationMap.onMapCreated]; tests attach a
/// fake with `attachBackend`. Not exported from the package library and not
/// a stable API.
@visibleForTesting
abstract interface class MapboxBackend {
  Future<void> updateCompass(CompassSettings settings);
  Future<void> updateScaleBar(ScaleBarSettings settings);

  /// Adds or replaces a style image.
  Future<void> addImage(String imageId, double scale, StyleImage image);

  /// Adds a GeoJSON source holding [data] (GeoJSON text).
  Future<void> addGeoJsonSource(String sourceId, String data);
  Future<void> addLayer(Layer layer);

  /// Replaces the properties of the existing layer with [layer]'s id.
  Future<void> updateLayer(Layer layer);
  Future<bool> styleSourceExists(String sourceId);
  Future<bool> styleLayerExists(String layerId);
  Future<void> setStyleSourceProperty(
    String sourceId,
    String property,
    Object value,
  );
  Future<void> setCamera(CameraOptions options);

  /// Replaces the style; the SDK reports it loaded via onStyleLoaded.
  Future<void> loadStyleURI(String uri);
}

class _MapboxMapBackend implements MapboxBackend {
  _MapboxMapBackend(this.map);

  final MapboxMap map;

  @override
  Future<void> updateCompass(CompassSettings settings) =>
      map.compass.updateSettings(settings);

  @override
  Future<void> updateScaleBar(ScaleBarSettings settings) =>
      map.scaleBar.updateSettings(settings);

  @override
  Future<void> addImage(String imageId, double scale, StyleImage image) =>
      map.addImage(imageId, scale, image);

  @override
  Future<void> addGeoJsonSource(String sourceId, String data) =>
      map.addSource(GeoJsonSource(id: sourceId, data: data));

  @override
  Future<void> addLayer(Layer layer) => map.addLayer(layer);

  @override
  Future<void> updateLayer(Layer layer) => map.updateLayer(layer);

  @override
  Future<bool> styleSourceExists(String sourceId) =>
      map.styleSourceExists(sourceId);

  @override
  Future<bool> styleLayerExists(String layerId) =>
      map.styleLayerExists(layerId);

  @override
  Future<void> setStyleSourceProperty(
    String sourceId,
    String property,
    Object value,
  ) => map.setStyleSourceProperty(sourceId, property, value);

  @override
  Future<void> setCamera(CameraOptions options) => map.setCamera(options);

  @override
  Future<void> loadStyleURI(String uri) => map.loadStyleURI(uri);
}

/// [NavigationMap] and [VehicleMarkerMap] on top of mapbox_maps_flutter.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapWidget` callbacks, and
/// call [onStyleChanging] when you switch the style. Camera updates are
/// dropped until the map exists; the route line and the vehicle are kept and
/// drawn once the style has loaded (and again after a style reload).
///
/// The source, layer and image ids are reserved (see [drivenSource],
/// [aheadSource], [vehicleSource], [vehicleImageId]): do not reuse them.
class MapboxNavigationMap implements NavigationMap, VehicleMarkerMap {
  /// [vehicleImage] renders the vehicle's PNG at a pixel ratio; the default
  /// is the default [CarPuck]. Use `vehicleImageFor(puck)` to render a
  /// `CarPuck` with its own size and colour.
  MapboxNavigationMap({
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
    for (final layer in [_drivenLayer(), _aheadLayer()]) {
      _fire(() async {
        final backend = _backend;
        if (backend != null) await backend.updateLayer(layer);
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
    final backend = _backend;
    if (backend == null) return;
    final generation = _styleGeneration;
    final (png, ratio) = await _puck();
    if (generation != _styleGeneration || !_styleReady) return;
    await backend.addImage(vehicleImageId, ratio, StyleImage.bytes(png));
  }

  /// The vehicle PNG at the current ratio (rendered once per ratio), and
  /// that ratio. A ratio change while rendering renders again.
  Future<(Uint8List, double)> _puck() async {
    for (;;) {
      final ratio = _pixelRatio;
      final cached = _puckPng;
      if (cached != null) return (cached, ratio);
      final png = await _vehicleImage(ratio);
      if (ratio == _pixelRatio) _puckPng = png;
    }
  }

  /// Applied with every camera update (set by the view).
  EdgeInsets padding = EdgeInsets.zero;

  MapboxBackend? _backend;
  bool _styleReady = false;
  int _styleGeneration = 0;
  Uint8List? _puckPng;
  List<GeoPoint> _driven = const [];
  List<GeoPoint> _ahead = const [];
  GeoPoint? _vehicle;
  double _vehicleBearing = 0;
  final _reportedErrors = <String>{};

  /// Call from `MapWidget.onMapCreated`.
  void onMapCreated(MapboxMap map) => _attach(_MapboxMapBackend(map));

  void _attach(MapboxBackend backend) {
    _backend = backend;
    _styleGeneration++;
    _styleReady = false;
  }

  /// Turns the compass and the scale bar off. [MapboxNavigationView] calls
  /// it from its `onMapCreated`; with your own `MapWidget` call it yourself
  /// if you want the same. Does nothing before the map exists; never throws.
  void hideOrnaments() {
    final backend = _backend;
    if (backend == null) return;
    _fire(() => backend.updateCompass(CompassSettings(enabled: false)));
    _fire(() => backend.updateScaleBar(ScaleBarSettings(enabled: false)));
  }

  /// Marks the route and vehicle layers as gone: nothing is drawn until the
  /// next [onStyleLoaded]. It does not load a style; to switch styles use
  /// [changeStyle]. Call it yourself only if you replace the style some
  /// other way (e.g. `loadStyleJson` on the `MapboxMap`).
  void onStyleChanging() {
    _styleGeneration++;
    _styleReady = false;
  }

  /// Switches the map to the style at [uri] (`MapWidget.styleUri` is only
  /// read when the map is created). The route and the vehicle are drawn
  /// again once the SDK reports the new style via [onStyleLoaded]. Does
  /// nothing before the map exists; never throws.
  void changeStyle(String uri) {
    final backend = _backend;
    if (backend == null) return;
    final wasReady = _styleReady;
    onStyleChanging();
    final generation = _styleGeneration;
    _fire(() async {
      try {
        await backend.loadStyleURI(uri);
      } catch (_) {
        // The old style is still loaded: draw into it again, unless
        // something newer (a style load, a new map) has taken over.
        if (wasReady && generation == _styleGeneration) {
          _styleReady = true;
          _styleGeneration++;
        }
        rethrow;
      }
    });
  }

  /// Adds the route and vehicle layers; call from `onStyleLoadedListener`.
  ///
  /// Safe to call again (style reload, or a retry after a failure) and never
  /// throws: a platform error leaves the layers unready until the next call.
  Future<void> onStyleLoaded() => _guard(_loadStyle);

  Future<void> _loadStyle() async {
    final backend = _backend;
    if (backend == null) return;
    _styleReady = false;
    final generation = ++_styleGeneration;
    final (puck, ratio) = await _puck();
    if (generation != _styleGeneration) return;
    if (!await _addLayers(backend, puck, ratio, generation)) return;
    _styleReady = true;
    await _pushRoute();
    await _pushVehicle();
  }

  /// Returns false when a newer style load (or a new map) has taken over.
  Future<bool> _addLayers(
    MapboxBackend backend,
    Uint8List puck,
    double ratio,
    int generation,
  ) async {
    bool current() => generation == _styleGeneration;
    // The PNG is rendered at [ratio]x; the scale gives it its logical size.
    // addImage replaces an existing image.
    await backend.addImage(vehicleImageId, ratio, StyleImage.bytes(puck));
    if (!current()) return false;
    for (final id in [drivenSource, aheadSource]) {
      await _addSource(backend, id, lineFeatureCollection(const []));
      if (!current()) return false;
    }
    await _addSource(backend, vehicleSource, pointFeatureCollection(null));
    if (!current()) return false;
    final layers = <Layer>[
      _drivenLayer(),
      _aheadLayer(),
      SymbolLayer(
        id: '$vehicleSource-symbol',
        sourceId: vehicleSource,
        iconImage: vehicleImageId,
        iconRotateExpression: ['get', 'bearing'],
        iconRotationAlignment: IconRotationAlignment.MAP,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    ];
    for (final layer in layers) {
      await _addLayer(backend, layer);
      if (!current()) return false;
    }
    return true;
  }

  LineLayer _drivenLayer() => LineLayer(
    id: drivenLayer,
    sourceId: drivenSource,
    lineColor: _routeColors.driven.toARGB32(),
    lineWidth: _routeColors.drivenWidth,
    lineCap: LineCap.ROUND,
    lineJoin: LineJoin.ROUND,
  );

  LineLayer _aheadLayer() => LineLayer(
    id: aheadLayer,
    sourceId: aheadSource,
    lineColor: _routeColors.ahead.toARGB32(),
    lineWidth: _routeColors.aheadWidth,
    lineCap: LineCap.ROUND,
    lineJoin: LineJoin.ROUND,
  );

  /// A source left over from an earlier attempt on the same style is not an
  /// error. The SDK reports it only as a message, so ask whether it exists.
  Future<void> _addSource(
    MapboxBackend backend,
    String id,
    Map<String, Object> geojson,
  ) async {
    try {
      await backend.addGeoJsonSource(id, jsonEncode(geojson));
    } catch (_) {
      if (!await backend.styleSourceExists(id)) rethrow;
    }
  }

  /// Same as [_addSource], for layers.
  Future<void> _addLayer(MapboxBackend backend, Layer layer) async {
    try {
      await backend.addLayer(layer);
    } catch (_) {
      if (!await backend.styleLayerExists(layer.id)) rethrow;
    }
  }

  /// Runs [f] without letting an error escape; a map update is best effort
  /// and the next one overwrites it. Reports each kind of error once in debug.
  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (kDebugMode && _reportedErrors.add(e.runtimeType.toString())) {
        (log ?? debugPrint)('navigation_engine_mapbox: $e');
      }
    }
  }

  void _fire(Future<void> Function() f) => unawaited(_guard(f));

  @override
  Future<void> moveCamera(CameraTarget target) async {
    final backend = _backend;
    if (backend == null) return;
    await backend.setCamera(toCameraOptions(target, padding));
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {
    _driven = driven;
    _ahead = ahead;
    unawaited(_pushRoute());
  }

  @override
  void clearRoute() => showRoute(const [], const []);

  @override
  void showVehicle(GeoPoint position, double bearing) {
    _vehicle = position;
    _vehicleBearing = bearing;
    unawaited(_pushVehicle());
  }

  @override
  void hideVehicle() {
    _vehicle = null;
    unawaited(_pushVehicle());
  }

  /// Sends [geojson] to [source] once the layers are there; never throws.
  Future<void> _setData(String source, Map<String, Object> geojson) => _guard(
    () async {
      final backend = _backend;
      if (backend == null || !_styleReady) return;
      await backend.setStyleSourceProperty(source, 'data', jsonEncode(geojson));
    },
  );

  Future<void> _pushRoute() async {
    await _setData(drivenSource, lineFeatureCollection(_driven));
    await _setData(aheadSource, lineFeatureCollection(_ahead));
  }

  Future<void> _pushVehicle() => _setData(
    vehicleSource,
    pointFeatureCollection(_vehicle, bearing: _vehicleBearing),
  );

  /// Stops all map calls; an in-flight style load is dropped.
  void dispose() {
    _backend = null;
    _styleGeneration++;
    _styleReady = false;
  }
}

/// Test seam: attaches a fake [MapboxBackend] instead of a `MapboxMap`, as
/// [MapboxNavigationMap.onMapCreated] would. Hidden from the package library.
@visibleForTesting
extension MapboxNavigationMapTesting on MapboxNavigationMap {
  void attachBackend(MapboxBackend backend) => _attach(backend);
}
