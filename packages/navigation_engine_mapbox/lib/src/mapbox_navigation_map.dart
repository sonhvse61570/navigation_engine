import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// Mapbox geometry for a [GeoPoint] (Mapbox positions are lng, lat).
Point toPoint(GeoPoint p) => Point(coordinates: Position(p.lng, p.lat));

// A CameraTarget zoom uses the 256 dp world of Google Maps and flutter_map;
// Mapbox's tiles are 512 px, so the same scale is one zoom level less.
double _sdkZoom(double zoom) => zoom - 1;

/// The camera options a [CameraTarget] stands for, with [padding] putting
/// the camera centre at the view's focus point. The zoom is converted to
/// Mapbox's scale: a [CameraTarget] zoom is in the 256 dp world of Google
/// Maps, and Mapbox's 512 px world shows it one level lower.
CameraOptions toCameraOptions(CameraTarget t, EdgeInsets padding) =>
    CameraOptions(
      center: toPoint(t.position),
      zoom: _sdkZoom(t.zoom),
      bearing: t.bearing,
      pitch: t.tilt,
      padding: MbxEdgeInsets(
        top: padding.top,
        left: padding.left,
        bottom: padding.bottom,
        right: padding.right,
      ),
    );

/// The first camera of a view at [center] and [zoom], the zoom converted
/// to Mapbox's scale as [toCameraOptions] does.
CameraViewportState toInitialViewport(GeoPoint center, double zoom) =>
    CameraViewportState(center: toPoint(center), zoom: _sdkZoom(zoom));

/// A tap on a feature: its id (null without one) and its properties.
typedef FeatureTap =
    void Function(String? featureId, Map<String, Object?> properties);

/// The few map calls [MapboxNavigationMap] makes. In an app they go to the
/// `MapboxMap` given to [MapboxNavigationMap.onMapCreated]; tests attach a
/// fake with `attachBackend`. Not exported from the package library and not
/// a stable API.
@visibleForTesting
abstract interface class MapboxBackend {
  Future<void> updateCompass(CompassSettings settings);
  Future<void> updateScaleBar(ScaleBarSettings settings);

  /// Applies [settings] to the Mapbox logo.
  Future<void> updateLogo(LogoSettings settings);

  /// Applies [settings] to the attribution button.
  Future<void> updateAttribution(AttributionSettings settings);

  /// Adds or replaces a style image.
  Future<void> addImage(String imageId, double scale, StyleImage image);

  /// Removes a style image.
  Future<void> removeImage(String imageId);

  /// Adds a GeoJSON source holding [data] (GeoJSON text).
  Future<void> addGeoJsonSource(String sourceId, String data);

  /// Removes a style source; no layer may use it any more.
  Future<void> removeSource(String sourceId);

  /// Adds [layer] on top, or right below the layer [below].
  Future<void> addLayer(Layer layer, {String? below});

  /// Replaces the properties of the existing layer with [layer]'s id.
  Future<void> updateLayer(Layer layer);

  /// Removes a style layer.
  Future<void> removeLayer(String layerId);
  Future<bool> styleSourceExists(String sourceId);
  Future<bool> styleLayerExists(String layerId);
  Future<void> setStyleSourceProperty(
    String sourceId,
    String property,
    Object value,
  );

  /// Sets a config property of the style import [importId] (such as the
  /// Standard style's `basemap` `lightPreset`) without reloading the style.
  Future<void> setStyleImportConfigProperty(
    String importId,
    String property,
    Object value,
  );

  /// Reports taps on the features of the layer [layerId] to [onTap]. It
  /// belongs to the map, not to the style: it stays through style reloads
  /// and while the layer is gone. Add it once per layer id.
  void addTapInteraction(String layerId, FeatureTap onTap);
  Future<void> setCamera(CameraOptions options);

  /// Animates the camera to [options].
  Future<void> easeTo(CameraOptions options);

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
  Future<void> updateLogo(LogoSettings settings) =>
      map.logo.updateSettings(settings);

  @override
  Future<void> updateAttribution(AttributionSettings settings) =>
      map.attribution.updateSettings(settings);

  @override
  Future<void> addImage(String imageId, double scale, StyleImage image) =>
      map.addImage(imageId, scale, image);

  @override
  Future<void> removeImage(String imageId) => map.removeStyleImage(imageId);

  @override
  Future<void> addGeoJsonSource(String sourceId, String data) =>
      map.addSource(GeoJsonSource(id: sourceId, data: data));

  @override
  Future<void> removeSource(String sourceId) => map.removeStyleSource(sourceId);

  // `MapboxMap.addLayer` ignores its position argument in 3.0.0 (and the
  // layer's JSON encoding is internal), so the layer is added on top and
  // then moved below [below].
  @override
  Future<void> addLayer(Layer layer, {String? below}) async {
    await map.addLayer(layer);
    if (below != null) {
      await map.moveStyleLayer(layer.id, LayerPosition(below: below));
    }
  }

  @override
  Future<void> updateLayer(Layer layer) => map.updateLayer(layer);

  @override
  Future<void> removeLayer(String layerId) => map.removeStyleLayer(layerId);

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
  Future<void> setStyleImportConfigProperty(
    String importId,
    String property,
    Object value,
  ) => map.setStyleImportConfigProperty(importId, property, value);

  @override
  void addTapInteraction(String layerId, FeatureTap onTap) =>
      map.addInteraction(
        TapInteraction(
          FeaturesetDescriptor(layerId: layerId),
          (feature, _) => onTap(feature.id?.id, feature.properties),
        ),
        interactionID: 'navigation_engine_tap_$layerId',
      );

  @override
  Future<void> setCamera(CameraOptions options) => map.setCamera(options);

  @override
  Future<void> easeTo(CameraOptions options) => map.easeTo(options, null);

  @override
  Future<void> loadStyleURI(String uri) => map.loadStyleURI(uri);
}

// How many label images are kept (see `_labelImages`).
const _labelImageLimit = 32;

/// [NavigationMap], [VehicleMarkerMap] and [RoutePreviewMap] on top of
/// mapbox_maps_flutter.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapWidget` callbacks, and
/// call [changeStyle] when you switch the style. Camera updates are dropped
/// until the map exists; the route line, the vehicle and the route options
/// are kept and drawn once the style has loaded (and again after a style
/// reload).
///
/// The source, layer and image ids are reserved (see [drivenSource],
/// [aheadSource], [vehicleSource], [vehicleImageId], and every id starting
/// with `navigation_engine_option_`): do not reuse them.
///
/// ## Route options
///
/// [showRouteOptions] adds, per route `i`, a GeoJSON source
/// `navigation_engine_option_<i>` and two line layers on it,
/// `navigation_engine_option_casing_<i>` and `navigation_engine_option_<i>`,
/// below the session's route layers. Bottom to top: the casings of the
/// muted routes, their lines, then the selected casing and line; the
/// selected route is drawn in the route colour, the others in
/// [alternativeColor].
///
/// With [routeLabel] set, each route also gets a label bubble at its middle:
/// an image `navigation_engine_option_label_<i>_<sel|alt>` rendered with
/// [labelPainter] in [labelColors] at the pixel ratio, and a point in the
/// source `navigation_engine_option_labels` (properties `index` and
/// `image`), drawn by the symbol layer of the same id, above the route and
/// below the vehicle. Labels are rendered asynchronously and appear
/// together; a newer [showRouteOptions] or [clearRouteOptions] drops renders
/// still pending.
///
/// A tap reaches [onRouteOptionTap] only through the option layers and the
/// label layer (a tap interaction on each of them); the session's own
/// layers take no taps. [fitRoutes] needs the map and [viewportSize];
/// called earlier, it is kept and applied once both exist. Fits account
/// for [padding], the camera insets the view sets.
///
/// ## Night
///
/// [lightPreset] sets the Standard style's light (such as `night`) without
/// reloading the style; for other styles switch to a night style with
/// [changeStyle].
class MapboxNavigationMap
    implements NavigationMap, VehicleMarkerMap, RoutePreviewMap {
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

  /// The symbol layer of the vehicle.
  static const vehicleLayer = '$vehicleSource-symbol';

  /// The prefix of every source, layer and image id of the route options.
  static const optionPrefix = 'navigation_engine_option_';

  /// The source and the symbol layer of the route option labels.
  static const optionLabels = '${optionPrefix}labels';

  /// The GeoJSON source of route option [index].
  static String optionSource(int index) => '$optionPrefix$index';

  /// The line layer of route option [index].
  static String optionLayer(int index) => '$optionPrefix$index';

  /// The casing line layer of route option [index].
  static String optionCasingLayer(int index) => '${optionPrefix}casing_$index';

  /// The label image of route option [index].
  static String optionLabelImage(int index, {required bool selected}) =>
      '${optionPrefix}label_${index}_${selected ? 'sel' : 'alt'}';

  /// The style import of the Standard style that [lightPreset] configures.
  static const basemapImport = 'basemap';

  /// Where debug reports go; defaults to `debugPrint`. Tests inject a sink.
  @visibleForTesting
  void Function(String message)? log;

  final VehicleImageBuilder _vehicleImage;
  RouteColors _routeColors;
  double _pixelRatio = 3;

  /// The text of the label bubble of a route option, such as its duration.
  /// When null, [showRouteOptions] adds no labels. It is read when the
  /// options are shown.
  String Function(NavRoute route)? routeLabel;

  /// Called with the route index when a route option, or its label, is
  /// tapped.
  void Function(int index)? onRouteOptionTap;

  /// Renders a label bubble as PNG bytes in [labelColors] (passed as
  /// `colors`). It defaults to [paintRouteLabel]; tests replace it to control
  /// when (and whether) a render finishes.
  Future<Uint8List> Function(
    String text, {
    required bool selected,
    required double pixelRatio,
    required RouteLabelColors colors,
  })?
  labelPainter;

  Color _alternativeColor = const Color(0xFF9AA0A6);
  RouteLabelColors _labelColors = const RouteLabelColors();
  String? _lightPreset;

  // What showRouteOptions was last given; null when no options are shown.
  List<NavRoute>? _shownRoutes;
  int _shownSelected = 0;

  // Bumped by every showRouteOptions / clearRouteOptions / labelColors
  // change; a label render started under an older value is dropped.
  int _labelGeneration = 0;

  // The rendered labels of the shown options, kept to re-add them after a
  // style reload; null until they are rendered.
  _Labels? _labels;

  // Label images by (text, selected, pixel ratio, colours), oldest first.
  // The futures are kept, so a render still running is shared too.
  final _labelImages = <_LabelKey, Future<Uint8List>>{};

  // What the current style holds of the route options. Emptied when the
  // style (or the map) is replaced.
  var _drawn = _Drawn();

  // The layers with a tap interaction on the current map.
  final _tapLayers = <String>{};

  // Route option updates run one at a time, in order.
  Future<void> _optionQueue = Future.value();

  Size? _viewportSize;
  _PendingFit? _pendingFit;

  /// The colours and widths of the session's route; the selected route
  /// option is drawn in [RouteColors.ahead] at [RouteColors.aheadWidth].
  RouteColors get routeColors => _routeColors;

  /// Re-styles the route lines (and the shown route options) when the style
  /// is ready; otherwise the new colours apply when the layers are added.
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
    _restyleOptions();
  }

  /// The colour of the route options that are not selected. Changing it
  /// while options are shown restyles their lines.
  Color get alternativeColor => _alternativeColor;
  set alternativeColor(Color value) {
    if (value == _alternativeColor) return;
    _alternativeColor = value;
    _restyleOptions();
  }

  /// The colours of the label bubbles (see [labelPainter]). Changing them
  /// while options are shown renders the labels again; the old bubbles stay
  /// until the new ones are ready.
  RouteLabelColors get labelColors => _labelColors;
  set labelColors(RouteLabelColors value) {
    if (value == _labelColors) return;
    _labelColors = value;
    final routes = _shownRoutes;
    if (routes != null && routeLabel != null) {
      unawaited(_renderLabels(routes, _shownSelected, ++_labelGeneration));
    }
  }

  /// The Standard style's `lightPreset` (`day`, `dawn`, `dusk` or `night`),
  /// set on its [basemapImport] import: at once when the style is ready
  /// (no reload: everything drawn stays), and after every style load. Null
  /// leaves the style's light alone; keep it null for other styles.
  String? get lightPreset => _lightPreset;
  set lightPreset(String? value) {
    if (value == _lightPreset) return;
    _lightPreset = value;
    if (value != null && _styleReady) _fire(_applyLightPreset);
  }

  Future<void> _applyLightPreset() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    await _setLightPreset(backend);
  }

  Future<void> _setLightPreset(MapboxBackend backend) async {
    final preset = _lightPreset;
    if (preset == null) return;
    await backend.setStyleImportConfigProperty(
      basemapImport,
      'lightPreset',
      preset,
    );
  }

  /// The size of the map view, used by [fitRoutes]. Setting it applies a
  /// pending fit when the map exists.
  Size? get viewportSize => _viewportSize;
  set viewportSize(Size? value) {
    _viewportSize = value;
    _applyPendingFit();
  }

  /// The device pixel ratio the vehicle image and the route option labels
  /// are rendered at (default 3). A change re-adds the vehicle image once
  /// the style is ready; labels use it from the next [showRouteOptions].
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

  /// Applied with every camera update (set by the view). [fitRoutes]
  /// accounts for it (as `mapPadding`, see [fitCameraToBounds]).
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

  /// Call from `MapWidget.onMapCreated`. Route option taps are read from
  /// this map from now on.
  void onMapCreated(MapboxMap map) => _attach(_MapboxMapBackend(map));

  void _attach(MapboxBackend backend) {
    _backend = backend;
    // A new map has its ornaments where the SDK puts them.
    _ornamentsPlaced = false;
    _styleGeneration++;
    _styleReady = false;
    _drawn = _Drawn();
    _tapLayers.clear();
    _applyPendingFit();
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

  /// The height of what the app shows over the bottom of the map (a panel,
  /// a footer). [placeOrnaments] keeps the Mapbox logo and the attribution
  /// button [ornamentMargin] above it, as Mapbox's terms require them to
  /// stay visible. A change places them again once the map exists.
  double get bottomInset => _bottomInset;
  set bottomInset(double value) {
    if (value == _bottomInset) return;
    _bottomInset = value;
    if (_ornamentsPlaced) placeOrnaments();
  }

  double _bottomInset = 0;
  bool _ornamentsPlaced = false;

  /// The space between the logo or the attribution button and
  /// [bottomInset].
  static const double ornamentMargin = 8;

  /// Places the logo and the attribution button [ornamentMargin] above
  /// [bottomInset], in their own corner. [MapboxNavigationView] calls it
  /// from its `onMapCreated`; changing [bottomInset] then places them again.
  /// Does nothing before the map exists; never throws.
  void placeOrnaments() {
    final backend = _backend;
    if (backend == null) return;
    _ornamentsPlaced = true;
    final bottom = _bottomInset + ornamentMargin;
    _fire(() => backend.updateLogo(LogoSettings(marginBottom: bottom)));
    _fire(
      () =>
          backend.updateAttribution(AttributionSettings(marginBottom: bottom)),
    );
  }

  /// Marks the route and vehicle layers (and the route options) as gone:
  /// nothing is drawn until the next [onStyleLoaded], which draws them all
  /// again. It does not load a style; to switch styles use [changeStyle].
  /// Call it yourself only if you replace the style some other way (e.g.
  /// `loadStyleJson` on the `MapboxMap`).
  void onStyleChanging() {
    _styleGeneration++;
    _styleReady = false;
    _drawn = _Drawn();
  }

  /// Switches the map to the style at [uri] (`MapWidget.styleUri` is only
  /// read when the map is created). The route, the vehicle and the route
  /// options are drawn again once the SDK reports the new style via
  /// [onStyleLoaded]. Does nothing before the map exists; never throws.
  void changeStyle(String uri) {
    final backend = _backend;
    if (backend == null) return;
    final wasReady = _styleReady;
    final drawn = _drawn;
    onStyleChanging();
    final generation = _styleGeneration;
    _fire(() async {
      try {
        await backend.loadStyleURI(uri);
      } catch (_) {
        // The old style is still loaded: draw into it again, unless
        // something newer (a style load, a new map) has taken over. It
        // still holds the options drawn before; bring them up to date.
        if (wasReady && generation == _styleGeneration) {
          _styleReady = true;
          _styleGeneration++;
          _drawn = drawn;
          _fireOptions(_syncOptions);
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
    _drawn = _Drawn();
    // The light first: a style that loads at night does not show day while
    // the route and the vehicle are added.
    final preset = _lightPreset;
    await _guard(() => _setLightPreset(backend));
    if (generation != _styleGeneration) return;
    final (puck, ratio) = await _puck();
    if (generation != _styleGeneration) return;
    if (!await _addLayers(backend, puck, ratio, generation)) return;
    _styleReady = true;
    // A preset set while the layers were added waited for the style.
    if (_lightPreset != preset) await _guard(_applyLightPreset);
    await _pushRoute();
    await _pushVehicle();
    // The new style has none of the route options: draw them again.
    await _enqueueOptions(_syncOptions);
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
        id: vehicleLayer,
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

  LineLayer _drivenLayer() => _lineLayer(
    drivenLayer,
    drivenSource,
    _routeColors.driven,
    _routeColors.drivenWidth,
  );

  LineLayer _aheadLayer() => _lineLayer(
    aheadLayer,
    aheadSource,
    _routeColors.ahead,
    _routeColors.aheadWidth,
  );

  static LineLayer _lineLayer(
    String id,
    String source,
    Color color,
    double width,
  ) => LineLayer(
    id: id,
    sourceId: source,
    lineColor: color.toARGB32(),
    lineWidth: width,
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
  Future<void> _addLayer(
    MapboxBackend backend,
    Layer layer, {
    String? below,
  }) async {
    try {
      await backend.addLayer(layer, below: below);
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

  @override
  void showRouteOptions(List<NavRoute> routes, int selected) {
    final generation = ++_labelGeneration;
    _shownRoutes = routes;
    _shownSelected = selected;
    _labels = null;
    _fireOptions(_syncOptions);
    if (routeLabel != null) {
      unawaited(_renderLabels(routes, selected, generation));
    }
  }

  @override
  void clearRouteOptions() {
    _labelGeneration++;
    _shownRoutes = null;
    _labels = null;
    _pendingFit = null;
    _fireOptions(_syncOptions);
  }

  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {
    final points = [for (final r in routes) ...r.points];
    if (points.isEmpty) return;
    final backend = _backend;
    final size = _viewportSize;
    if (backend == null || size == null) {
      _pendingFit = _PendingFit(points, padding);
      return;
    }
    _pendingFit = null;
    final options = _fitOptions(points, size, padding);
    await _guard(() => backend.easeTo(options));
  }

  void _applyPendingFit() {
    final backend = _backend;
    final size = _viewportSize;
    final pending = _pendingFit;
    if (backend == null || size == null || pending == null) return;
    _pendingFit = null;
    final options = _fitOptions(pending.points, size, pending.padding);
    _fire(() => backend.setCamera(options));
  }

  /// The camera that shows [points] inside [viewport] minus [fitPadding],
  /// with the camera insets ([padding] of the adapter) as the map padding.
  /// [toCameraOptions] converts the zoom of [fitCameraToBounds] (a 256 dp
  /// world) to Mapbox's 512 px world: one level less, applied once there.
  CameraOptions _fitOptions(
    List<GeoPoint> points,
    Size viewport,
    EdgeInsets fitPadding,
  ) => toCameraOptions(
    fitCameraToBounds(points, viewport, fitPadding, mapPadding: padding),
    padding,
  );

  /// Stops all map calls and drops what is pending: an in-flight style
  /// load, label renders and a pending fit. The view calls it when it is
  /// disposed.
  void dispose() {
    _backend = null;
    _styleGeneration++;
    _styleReady = false;
    _labelGeneration++;
    _shownRoutes = null;
    _labels = null;
    _pendingFit = null;
    _labelImages.clear();
    _drawn = _Drawn();
    _tapLayers.clear();
  }

  /// Adds a tap interaction on [layerId], once per map.
  void _listenTaps(MapboxBackend backend, String layerId) {
    if (!_tapLayers.add(layerId)) return;
    backend.addTapInteraction(
      layerId,
      (id, properties) => _onFeatureTapped(backend, layerId, id, properties),
    );
  }

  void _onFeatureTapped(
    MapboxBackend backend,
    String layerId,
    String? id,
    Map<String, Object?> properties,
  ) {
    final routes = _shownRoutes;
    final onTap = onRouteOptionTap;
    if (!identical(backend, _backend) || routes == null || onTap == null) {
      return;
    }
    final index = _tappedIndex(layerId, id, properties);
    if (index != null && index >= 0 && index < routes.length) onTap(index);
  }

  /// The route index of a tapped feature: from the layer id for the option
  /// lines, from the `index` property (or else the feature id) for the
  /// labels. Null for any other layer.
  static int? _tappedIndex(
    String layerId,
    String? id,
    Map<String, Object?> properties,
  ) {
    if (layerId == optionLabels) {
      final index = properties['index'];
      if (index is num) return index.toInt();
      return id == null ? null : num.tryParse(id)?.toInt();
    }
    const casing = '${optionPrefix}casing_';
    if (layerId.startsWith(casing)) {
      return int.tryParse(layerId.substring(casing.length));
    }
    if (layerId.startsWith(optionPrefix)) {
      return int.tryParse(layerId.substring(optionPrefix.length));
    }
    return null;
  }

  Future<void> _enqueueOptions(Future<void> Function() op) =>
      _optionQueue = _optionQueue.then((_) => _guard(op));

  void _fireOptions(Future<void> Function() op) =>
      unawaited(_enqueueOptions(op));

  // Restyles the drawn option lines after a colour change, in place.
  void _restyleOptions() {
    if (_shownRoutes == null || !_styleReady) return;
    _fireOptions(() async {
      final backend = _backend;
      if (backend == null || !_styleReady || _shownRoutes == null) return;
      final generation = _styleGeneration;
      for (final line in List.of(_drawn.lines)) {
        await backend.updateLayer(_optionLayer(line));
        if (generation != _styleGeneration) return;
      }
    });
  }

  /// Makes the style hold what is shown: the option sources, their lines in
  /// the z-order of the selection, and the labels when rendered.
  Future<void> _syncOptions() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    final generation = _styleGeneration;
    final drawn = _drawn;
    bool current() =>
        generation == _styleGeneration && identical(backend, _backend);
    final routes = _shownRoutes ?? const <NavRoute>[];
    final selected = _shownSelected;

    // The lines are added again: a new selection changes their order.
    for (final line in List.of(drawn.lines.reversed)) {
      await backend.removeLayer(line.id);
      if (!current()) return;
      drawn.lines.remove(line);
    }
    final wanted = {for (var i = 0; i < routes.length; i++) optionSource(i)};
    for (final id in drawn.sources.difference(wanted)) {
      await backend.removeSource(id);
      if (!current()) return;
      drawn.sources.remove(id);
    }
    for (var i = 0; i < routes.length; i++) {
      final id = optionSource(i);
      await _putSource(
        backend,
        id,
        lineFeatureCollection(routes[i].points),
        exists: drawn.sources.contains(id),
      );
      if (!current()) return;
      drawn.sources.add(id);
    }
    for (final line in _lineOrder(routes.length, selected)) {
      await _addLayer(backend, _optionLayer(line), below: drivenLayer);
      if (!current()) return;
      drawn.lines.add(line);
      _listenTaps(backend, line.id);
    }
    await _drawLabels(backend, drawn, current);
  }

  Future<void> _syncLabels() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    final generation = _styleGeneration;
    await _drawLabels(
      backend,
      _drawn,
      () => generation == _styleGeneration && identical(backend, _backend),
    );
  }

  /// Adds the rendered labels (images, source, layer), or removes the label
  /// layer, source and images when there are none. Label images no longer
  /// used are removed.
  Future<void> _drawLabels(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current,
  ) async {
    final labels = _shownRoutes == null ? null : _labels;
    if (labels == null) {
      if (drawn.labelLayer) {
        await backend.removeLayer(optionLabels);
        if (!current()) return;
        drawn.labelLayer = false;
      }
      if (drawn.labelSource) {
        await backend.removeSource(optionLabels);
        if (!current()) return;
        drawn.labelSource = false;
      }
      await _removeImages(backend, drawn, current, keep: const {});
      return;
    }
    for (final (id, png) in labels.images) {
      await backend.addImage(id, labels.pixelRatio, StyleImage.bytes(png));
      if (!current()) return;
      drawn.images.add(id);
    }
    await _putSource(
      backend,
      optionLabels,
      labels.features,
      exists: drawn.labelSource,
    );
    if (!current()) return;
    drawn.labelSource = true;
    await _removeImages(
      backend,
      drawn,
      current,
      keep: {for (final (id, _) in labels.images) id},
    );
    if (!current() || drawn.labelLayer) return;
    await _addLayer(
      backend,
      SymbolLayer(
        id: optionLabels,
        sourceId: optionLabels,
        iconImageExpression: ['get', 'image'],
        iconAnchor: IconAnchor.BOTTOM,
        iconSize: 1,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // The selected label is the last feature: drawn on top.
        symbolZOrder: SymbolZOrder.SOURCE,
      ),
      below: vehicleLayer,
    );
    if (!current()) return;
    drawn.labelLayer = true;
    _listenTaps(backend, optionLabels);
  }

  /// Removes the drawn label images not in [keep].
  Future<void> _removeImages(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current, {
    required Set<String> keep,
  }) async {
    for (final id in drawn.images.difference(keep)) {
      await backend.removeImage(id);
      if (!current()) return;
      drawn.images.remove(id);
    }
  }

  /// Adds the source [id], or sets its data when it is already there.
  Future<void> _putSource(
    MapboxBackend backend,
    String id,
    Map<String, Object?> data, {
    required bool exists,
  }) async {
    final json = jsonEncode(data);
    if (!exists) {
      try {
        await backend.addGeoJsonSource(id, json);
        return;
      } catch (_) {
        // Left over from an earlier attempt: its data is replaced below.
        if (!await backend.styleSourceExists(id)) rethrow;
      }
    }
    await backend.setStyleSourceProperty(id, 'data', json);
  }

  /// The option lines, bottom to top, as the z-order of the Google adapter:
  /// all muted casings, all muted lines, then the selected casing and line.
  static List<_OptionLine> _lineOrder(int count, int selected) {
    final muted = [
      for (var i = 0; i < count; i++)
        if (i != selected) i,
    ];
    _OptionLine line(int i, {required bool casing}) => (
      id: casing ? optionCasingLayer(i) : optionLayer(i),
      index: i,
      casing: casing,
      selected: i == selected,
    );
    return [
      for (final i in muted) line(i, casing: true),
      for (final i in muted) line(i, casing: false),
      if (selected >= 0 && selected < count) ...[
        line(selected, casing: true),
        line(selected, casing: false),
      ],
    ];
  }

  LineLayer _optionLayer(_OptionLine line) {
    final width = _routeColors.aheadWidth;
    final color = line.selected ? _routeColors.ahead : _alternativeColor;
    final source = optionSource(line.index);
    if (!line.casing) return _lineLayer(line.id, source, color, width);
    final casing = line.selected
        ? Color.lerp(color, const Color(0xFF000000), 0.35)!
        : Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!;
    return _lineLayer(line.id, source, casing, width + 4);
  }

  Future<void> _renderLabels(
    List<NavRoute> routes,
    int selected,
    int generation,
  ) async {
    final label = routeLabel;
    if (label == null) return;
    final ratio = _pixelRatio;
    final colors = _labelColors;
    final List<Uint8List> images;
    try {
      images = await Future.wait([
        for (var i = 0; i < routes.length; i++)
          _labelImage(label(routes[i]), i == selected, ratio, colors),
      ]);
    } on Object {
      // No labels for this generation; the lines are still shown.
      return;
    }
    if (generation != _labelGeneration) return;
    _labels = _Labels.of(routes, selected, images, ratio);
    _fireOptions(_syncLabels);
  }

  Future<Uint8List> _labelImage(
    String text,
    bool selected,
    double ratio,
    RouteLabelColors colors,
  ) {
    final key = (text, selected, ratio, colors);
    final cached = _labelImages[key];
    if (cached != null) return cached;
    final paint = labelPainter;
    final image = Future.sync(
      () => paint != null
          ? paint(text, selected: selected, pixelRatio: ratio, colors: colors)
          : paintRouteLabel(
              text,
              selected: selected,
              pixelRatio: ratio,
              colors: colors,
            ),
    );
    _labelImages[key] = image;
    if (_labelImages.length > _labelImageLimit) {
      _labelImages.remove(_labelImages.keys.first);
    }
    // A failed render is not kept: the next showRouteOptions tries again.
    image.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_labelImages[key], image)) _labelImages.remove(key);
      },
    );
    return image;
  }
}

/// Test seam: attaches a fake [MapboxBackend] instead of a `MapboxMap`, as
/// [MapboxNavigationMap.onMapCreated] would. Hidden from the package library.
@visibleForTesting
extension MapboxNavigationMapTesting on MapboxNavigationMap {
  void attachBackend(MapboxBackend backend) => _attach(backend);
}

/// A drawn option line layer.
typedef _OptionLine = ({String id, int index, bool casing, bool selected});

/// The key of a cached label image.
typedef _LabelKey = (String, bool, double, RouteLabelColors);

/// What a style holds of the route options.
class _Drawn {
  final lines = <_OptionLine>[];
  final sources = <String>{};
  final images = <String>{};
  bool labelSource = false;
  bool labelLayer = false;
}

/// The rendered labels of the shown route options.
class _Labels {
  _Labels(this.images, this.features, this.pixelRatio);

  /// One label per route, at the middle of the route; the selected one last.
  factory _Labels.of(
    List<NavRoute> routes,
    int selected,
    List<Uint8List> pngs,
    double pixelRatio,
  ) {
    final order = [
      for (var i = 0; i < routes.length; i++)
        if (i != selected) i,
      if (selected >= 0 && selected < routes.length) selected,
    ];
    String image(int i) =>
        MapboxNavigationMap.optionLabelImage(i, selected: i == selected);
    return _Labels(
      [for (var i = 0; i < routes.length; i++) (image(i), pngs[i])],
      {
        'type': 'FeatureCollection',
        'features': [
          for (final i in order)
            {
              'type': 'Feature',
              'id': i,
              'properties': {'index': i, 'image': image(i)},
              'geometry': {
                'type': 'Point',
                'coordinates': [
                  routes[i].pointAt(routes[i].length / 2).lng,
                  routes[i].pointAt(routes[i].length / 2).lat,
                ],
              },
            },
        ],
      },
      pixelRatio,
    );
  }

  /// The image id and PNG of each label.
  final List<(String, Uint8List)> images;

  /// The GeoJSON of the label source.
  final Map<String, Object?> features;

  /// The pixel ratio the PNGs were rendered at: their style image scale.
  final double pixelRatio;
}

/// A [MapboxNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}
