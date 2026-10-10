import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// Mapbox geometry for a [GeoPoint] (Mapbox positions are lng, lat).
Point toPoint(GeoPoint p) => Point(coordinates: Position(p.lng, p.lat));

/// The [GeoPoint] of a Mapbox point (Mapbox positions are lng, lat). Not
/// part of the public API (hidden by the library export).
GeoPoint toGeoPoint(Point p) =>
    GeoPoint(p.coordinates.lat.toDouble(), p.coordinates.lng.toDouble());

/// A GeoJSON feature collection of one point feature per entry of [points],
/// its id and `index` property the entry's index, its `image` property
/// from [image].
Map<String, Object?> _pointFeatures(
  List<(int index, GeoPoint point, String image)> points,
) => {
  'type': 'FeatureCollection',
  'features': [
    for (final (index, point, image) in points)
      {
        'type': 'Feature',
        'id': index,
        'properties': {'index': index, 'image': image},
        'geometry': {
          'type': 'Point',
          'coordinates': [point.lng, point.lat],
        },
      },
  ],
};

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

  /// Adds [layer] on top.
  Future<void> addLayer(Layer layer);

  /// Moves the existing layer [layerId] right below the layer [below].
  Future<void> moveLayer(String layerId, {required String below});

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

  /// Reports taps ([onTap]) and long taps ([onLongTap]) on the map itself,
  /// with the place under the finger. A tap that an interaction on a layer
  /// took ([addTapInteraction]) is not reported. Like those interactions
  /// they belong to the map: add them once per map.
  void addMapTapInteractions({
    required void Function(GeoPoint point) onTap,
    required void Function(GeoPoint point) onLongTap,
  });
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
  // layer's JSON encoding is internal), so a layer is added on top and then
  // moved (see MapboxNavigationMap._addLayer).
  @override
  Future<void> addLayer(Layer layer) => map.addLayer(layer);

  @override
  Future<void> moveLayer(String layerId, {required String below}) =>
      map.moveStyleLayer(layerId, LayerPosition(below: below));

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

  // The map's own taps go to interactions with no target, which the SDK
  // calls only when no interaction on a layer stopped the tap (the layer
  // ones above stop it: `stopPropagation` defaults to true). These do not
  // stop it, so an app's own interaction on the map still gets it.
  @override
  void addMapTapInteractions({
    required void Function(GeoPoint point) onTap,
    required void Function(GeoPoint point) onLongTap,
  }) {
    map.addInteraction(
      TapInteraction.onMap(
        (context) => onTap(toGeoPoint(context.point)),
        stopPropagation: false,
      ),
      interactionID: 'navigation_engine_map_tap',
    );
    try {
      map.addInteraction(
        LongTapInteraction.onMap(
          (context) => onLongTap(toGeoPoint(context.point)),
          stopPropagation: false,
        ),
        interactionID: 'navigation_engine_map_long_tap',
      );
    } on UnsupportedError {
      // Mapbox GL JS (the web) has no long tap yet.
    }
  }

  @override
  Future<void> setCamera(CameraOptions options) => map.setCamera(options);

  @override
  Future<void> easeTo(CameraOptions options) => map.easeTo(options, null);

  @override
  Future<void> loadStyleURI(String uri) => map.loadStyleURI(uri);
}

// How many label images are kept (see `_labelImages`).
const _labelImageLimit = 32;

/// [NavigationMap], [VehicleMarkerMap], [RoutePreviewMap],
/// [AlternateRoutesMap], [SearchPinsMap] and [DestinationPinMap] on top of
/// mapbox_maps_flutter.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapWidget` callbacks, and
/// call [changeStyle] when you switch the style. Camera updates are dropped
/// until the map exists; the route line, the vehicle and the route options
/// are kept and drawn once the style has loaded (and again after a style
/// reload).
///
/// The source, layer and image ids are reserved (see [drivenSource],
/// [aheadSource], [vehicleSource], [vehicleImageId], every id starting
/// with `navigation_engine_option_`, `navigation_engine_alternate`,
/// `navigation_engine_search` or `navigation_engine_destination`, and the
/// interaction ids starting with `navigation_engine_`): do not reuse them.
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
/// A new selection of the same routes restyles the lines and moves them
/// into the new order in place (nothing is removed or added, so nothing
/// flickers); a move that fails is reported and done again on the next
/// update.
///
/// A tap reaches [onRouteOptionTap] only through the option layers and the
/// label layer (a tap interaction on each of them); the session's own
/// layers take no taps. So a tap on the vehicle where it sits over an
/// option line selects that option, as on MapLibre and flutter_map. A tap
/// on a line or a label drawn for other routes than the option now at its
/// index (a newer [showRouteOptions] not drawn yet) is ignored.
///
/// [fitRoutes] needs the map and [viewportSize]; called earlier, it is kept
/// and applied once both exist. Fits account for [padding], the camera
/// insets the view sets.
///
/// ## Alternate routes
///
/// [showAlternates] draws the alternates as the line features of one
/// GeoJSON source and line layer, [alternatesSource] and [alternatesLayer],
/// below the route options and the session's route, in [alternateColor]
/// and 70 % as wide as the route. A line is the alternate's own part
/// ([alternateLinePoints]): from 40 m before it leaves the route to 40 m
/// after it rejoins it, so a tap on the route where the two share the road
/// is a map tap, as on every adapter. An empty list is [clearAlternates].
/// With [alternateLabel] set, each gets a
/// bubble (image [alternateLabelImage], rendered like the route option
/// labels in [fasterLabelColors] or [slowerLabelColors]) in the symbol
/// source and layer [alternateLabels], at the middle of the part that
/// differs (from the divergence to the rejoin, else the end) but at most
/// [alternateLabelLead] metres past the divergence
/// ([alternateLabelDistance]), so always on its line. A tap on a
/// line or a bubble calls the `onTap` given to [showAlternates]. Until the
/// new lines and bubbles are drawn the old ones stay, but a tap on one that
/// stands for another route than the alternate now at its index is
/// ignored. A failed bubble render removes the bubbles (the lines stay) and
/// is reported through [FlutterError].
///
/// ## Search pins and the destination pin
///
/// [showSearchPins] draws one pin per place (the images [searchPinImage]
/// and [searchPinFocusedImage], rendered by [pinPainter] in [pinColor]) in
/// the symbol source and layer [searchPins], the focused one last (on
/// top). A tap on one calls the newest `onTap` with its place, only while
/// a place with that id is still shown. [showDestinationPin] draws the
/// shared red pin of [paintDestinationPin] (image [destinationImage]) in
/// the symbol source and layer [destination]. Both are anchored at their
/// tip. A failed render removes the pins and is reported through
/// [FlutterError]; a newer call drops a render still pending.
///
/// The symbol layers sit above the route and below the vehicle, bottom to
/// top: [alternateLabels], [optionLabels], [destination], [searchPins],
/// whatever order they are drawn in. Every line, bubble and pin is kept and
/// drawn again after a style reload.
///
/// ## Map taps
///
/// [onMapTap] and [onMapLongPress] get the taps and long taps on the map
/// itself (interactions on the map, with no target). A tap on a feature the
/// map draws (a route option or its label, an alternate or its bubble, a
/// search pin or the destination pin) is not a map tap: the SDK calls the
/// map's interaction only when no interaction on a layer stopped the tap,
/// and the map drops (with a [MapTapGuard]) a map tap that comes in the
/// same frame after such a tap, or that such a tap follows in the same turn
/// of the event loop. A map tap is delivered one turn of the event loop
/// after the SDK reports it. A long tap is always delivered (not on the
/// web, whose Mapbox GL JS has no long tap).
///
/// ## Night
///
/// [lightPreset] sets the Standard style's light (such as `night`) without
/// reloading the style; for other styles switch to a night style with
/// [changeStyle].
class MapboxNavigationMap
    implements
        NavigationMap,
        VehicleMarkerMap,
        RoutePreviewMap,
        AlternateRoutesMap,
        SearchPinsMap,
        DestinationPinMap {
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

  /// The GeoJSON source of the alternate routes: one line feature per
  /// alternate, its id and `index` property the alternate's index.
  static const alternatesSource = 'navigation_engine_alternates';

  /// The line layer of the alternate routes, on [alternatesSource].
  static const alternatesLayer = alternatesSource;

  /// The source and the symbol layer of the alternate routes' bubbles.
  static const alternateLabels = 'navigation_engine_alternate_labels';

  /// The bubble image of alternate [index].
  static String alternateLabelImage(int index) =>
      'navigation_engine_alternate_label_$index';

  /// How far past its divergence an alternate's bubble sits at most, in
  /// metres: the middle of a long alternate's own part is off screen at
  /// follow zoom.
  static const double alternateLabelLead = 400;

  /// The source and the symbol layer of the search pins: one point feature
  /// per place, its id and `index` property the place's index.
  static const searchPins = 'navigation_engine_search';

  /// The image of a search pin.
  static const searchPinImage = 'navigation_engine_search_pin';

  /// The image of the focused search pin.
  static const searchPinFocusedImage = 'navigation_engine_search_pin_focused';

  /// The source and the symbol layer of the destination pin.
  static const destination = 'navigation_engine_destination';

  /// The image of the destination pin.
  static const destinationImage = 'navigation_engine_destination_pin';

  // The symbol layers above the route, bottom to top (the vehicle is above
  // them all).
  static const _symbolOrder = [
    alternateLabels,
    optionLabels,
    destination,
    searchPins,
  ];

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

  /// Called with the place of a tap on the map itself, one turn of the
  /// event loop after the SDK reports it; read then. A tap on a feature the
  /// map draws is not one (see "Map taps" above).
  void Function(GeoPoint point)? onMapTap;

  /// Called with the place of a long tap on the map, wherever it is (also
  /// on a feature the map draws). Mapbox GL JS (the web) reports none.
  void Function(GeoPoint point)? onMapLongPress;

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
  RouteLabelColors _labelColors = MapDefaultColors.routeLabels;
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

  // Label images by (text, selected, pixel ratio, colours), least recently
  // used first. The futures are kept, so a render still running is shared
  // too.
  final _labelImages = <_LabelKey, Future<Uint8List>>{};

  // What the current style holds of the route options. Emptied when the
  // style (or the map) is replaced.
  var _drawn = _Drawn();

  // The layers with a tap interaction on the current map.
  final _tapLayers = <String>{};

  // Style updates (route options, alternates, pins) run one at a time, in
  // order.
  Future<void> _optionQueue = Future.value();

  // Drops the map tap of a gesture a feature the map draws took.
  final _tapGuard = MapTapGuard();

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
    _restyleAlternates();
  }

  /// The colour of the route options that are not selected. Changing it
  /// while options are shown restyles their lines.
  Color get alternativeColor => _alternativeColor;
  set alternativeColor(Color value) {
    if (value == _alternativeColor) return;
    _alternativeColor = value;
    _restyleOptions();
  }

  /// The colours of the label bubbles (see [labelPainter]), by default
  /// [MapDefaultColors.routeLabels], as on every adapter. Changing them
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

  /// The device pixel ratio the vehicle image, the route option labels,
  /// the alternates' bubbles and the pins are rendered at (default 3). A
  /// change re-adds the vehicle image once the style is ready; the labels,
  /// bubbles and pins use it from their next `show` call.
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
    try {
      backend.addMapTapInteractions(
        onTap: (point) => _onMapTapped(backend, point),
        onLongTap: (point) => _onMapLongTapped(backend, point),
      );
    } catch (e) {
      _report(e);
    }
    _applyPendingFit();
  }

  // A tap on the map itself, from [backend]'s map.
  void _onMapTapped(MapboxBackend backend, GeoPoint point) {
    if (!identical(backend, _backend) || onMapTap == null) return;
    // Not the map's side of a tap one of the map's features took; the
    // callback is read when the tap is delivered.
    _tapGuard.dispatch(() {
      if (identical(backend, _backend)) onMapTap?.call(point);
    });
  }

  void _onMapLongTapped(MapboxBackend backend, GeoPoint point) {
    if (identical(backend, _backend)) onMapLongPress?.call(point);
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

  /// The width of what the app shows over the left of the map (a side
  /// panel): [placeOrnaments] keeps the Mapbox logo (bottom left)
  /// [ornamentMargin] beside it. See [setSideInsets].
  double get leftInset => _leftInset;

  /// The width of what the app shows over the right of the map: the
  /// attribution button (bottom right) keeps [ornamentMargin] beside it.
  /// See [setSideInsets].
  double get rightInset => _rightInset;

  double _leftInset = 0;
  double _rightInset = 0;

  /// Sets [leftInset] and [rightInset] (physical sides, in both text
  /// directions). A change places the ornaments again once the map exists.
  void setSideInsets({required double left, required double right}) {
    if (left == _leftInset && right == _rightInset) return;
    _leftInset = left;
    _rightInset = right;
    if (_ornamentsPlaced) placeOrnaments();
  }

  /// The space between the logo or the attribution button and
  /// [bottomInset].
  static const double ornamentMargin = 8;

  /// Places the logo bottom left and the attribution button bottom right,
  /// [ornamentMargin] above [bottomInset] and beside [leftInset] (the logo)
  /// or [rightInset] (the attribution). The corners are set on every
  /// platform, so both keep clear of a side panel on either side.
  /// [MapboxNavigationView] calls it from its `onMapCreated`; changing
  /// [bottomInset] or the side insets then places them again. Does nothing
  /// before the map exists; never throws.
  void placeOrnaments() {
    final backend = _backend;
    if (backend == null) return;
    _ornamentsPlaced = true;
    final bottom = _bottomInset + ornamentMargin;
    _fire(
      () => backend.updateLogo(
        LogoSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: _leftInset + ornamentMargin,
          marginBottom: bottom,
        ),
      ),
    );
    _fire(
      () => backend.updateAttribution(
        AttributionSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: _rightInset + ornamentMargin,
          marginBottom: bottom,
        ),
      ),
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
          _fireOptions(_syncAlternates);
          _fireOptions(_syncDestination);
          _fireOptions(_syncPins);
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
    // The new style has none of the route options, the alternates and the
    // pins: draw them again.
    await _enqueueOptions(_syncOptions);
    await _enqueueOptions(_syncAlternates);
    await _enqueueOptions(_syncDestination);
    await _enqueueOptions(_syncPins);
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
  /// Adds [layer] on top; one left over from an earlier attempt is kept.
  /// The callers record the layer as drawn right after, before they move
  /// it into place: a failed move is not swallowed (it reaches [_guard],
  /// which reports it), and the layer is still known, so a clear removes
  /// it and the next update moves it again.
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
      _report(e);
    }
  }

  void _report(Object e) {
    if (kDebugMode && _reportedErrors.add(e.runtimeType.toString())) {
      (log ?? debugPrint)('navigation_engine_mapbox: $e');
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
    final sameRoutes = _sameRoutes(_shownRoutes, routes);
    _shownRoutes = routes;
    _shownSelected = selected;
    // The same routes (a selection change): the old labels stay drawn until
    // the new ones are ready, so they do not blink. Other routes: the old
    // labels would sit on routes no longer shown, so they go at once.
    if (!sameRoutes || routeLabel == null) _labels = null;
    _fireOptions(_syncOptions);
    if (routeLabel != null) {
      unawaited(_renderLabels(routes, selected, generation));
    }
  }

  static bool _sameRoutes(List<NavRoute>? a, List<NavRoute> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
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
    _alternateGeneration++;
    _shownAlternates = null;
    _alternateTap = null;
    _alternateTexts = null;
    _alternateBubbles = null;
    _pinGeneration++;
    _shownPins = null;
    _pins = null;
    _destinationGeneration++;
    _destinationPin = null;
    _destinationImage = null;
    _tapGuard.dispose();
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
    if (!identical(backend, _backend)) return;
    final drawn = _drawn;
    switch (layerId) {
      case alternatesLayer:
        _tapGuard.featureTapped();
        _tapAlternate(_featureIndex(id, properties), drawn.alternateLines);
      case alternateLabels:
        _tapGuard.featureTapped();
        _tapAlternate(_featureIndex(id, properties), drawn.alternateBubbles);
      case searchPins:
        _tapGuard.featureTapped();
        _tapPin(_featureIndex(id, properties), drawn.pins);
      case destination:
        _tapGuard.featureTapped();
      default:
        if (!layerId.startsWith(optionPrefix)) return;
        _tapGuard.featureTapped();
        _tapOption(layerId, id, properties, drawn);
    }
  }

  // A tap on a route option line or label: reported only while the route
  // it was drawn for is still the option at its index.
  void _tapOption(
    String layerId,
    String? id,
    Map<String, Object?> properties,
    _Drawn drawn,
  ) {
    final routes = _shownRoutes;
    final onTap = onRouteOptionTap;
    if (routes == null || onTap == null) return;
    final index = _tappedIndex(layerId, id, properties);
    if (index == null || index < 0 || index >= routes.length) return;
    final shownThere = layerId == optionLabels
        ? drawn.labelRoutes?.elementAtOrNull(index)
        : drawn.optionRoutes[optionSource(index)];
    if (!identical(shownThere, routes[index])) return;
    onTap(index);
  }

  /// The index of a tapped point or line feature: its `index` property, or
  /// else its id (which the SDK may report as a double).
  static int? _featureIndex(String? id, Map<String, Object?> properties) {
    final index = properties['index'];
    if (index is num) return index.toInt();
    return id == null ? null : num.tryParse(id)?.toInt();
  }

  // A tap on alternate [index] as drawn: [drawn] are the routes the drawn
  // features stand for. A feature drawn for an older list, which may stand
  // for another route than the alternate now at [index], is ignored.
  void _tapAlternate(int? index, List<NavRoute>? drawn) {
    final shown = _shownAlternates;
    final onTap = _alternateTap;
    if (index == null || drawn == null || shown == null || onTap == null) {
      return;
    }
    if (index < 0 || index >= drawn.length || index >= shown.length) return;
    if (!identical(drawn[index], shown[index].route)) return;
    onTap(index);
  }

  // A tap on search pin [index] as drawn ([drawn]): its place, with the
  // newest onTap, while a place with its id is still shown.
  void _tapPin(int? index, _Pins? drawn) {
    final shown = _shownPins;
    if (index == null || drawn == null || shown == null) return;
    if (index < 0 || index >= drawn.places.length) return;
    final id = drawn.places[index].id;
    for (final place in shown.places) {
      if (place.id == id) {
        shown.onTap?.call(place);
        return;
      }
    }
  }

  /// The layer the symbol layer [id] goes below: the lowest of those above
  /// it in [_symbolOrder] that [drawn] holds in place, else the vehicle's.
  String _symbolBelow(String id, _Drawn drawn) {
    for (final above in _symbolOrder.skip(_symbolOrder.indexOf(id) + 1)) {
      final placed = above == optionLabels
          ? drawn.labelLayerPlaced
          : drawn.placedLayers.contains(above);
      if (placed) return above;
    }
    return vehicleLayer;
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
    final order = _lineOrder(routes.length, selected);

    // The same lines (a new selection): restyled and reordered in place,
    // nothing removed or added, so nothing flickers.
    final inPlace =
        drawn.lines.isNotEmpty &&
        drawn.lines.length == order.length &&
        {
          for (final l in drawn.lines) l.id,
        }.containsAll([for (final l in order) l.id]);
    // A failing step does not stop the others: what is left is redone on
    // the next update, and the labels still follow (a clear removes them).
    // The first error is rethrown at the end, for [_guard] to report.
    final errors = <(Object, StackTrace)>[];
    Future<void> step(Future<void> Function() f) async {
      try {
        await f();
      } catch (e, st) {
        errors.add((e, st));
      }
    }

    if (!inPlace) {
      // Other lines: removed, then added in the new order.
      for (final line in List.of(drawn.lines.reversed)) {
        await step(() async {
          await backend.removeLayer(line.id);
          drawn.lines.remove(line);
        });
        if (!current()) return;
      }
    }
    final wanted = {for (var i = 0; i < routes.length; i++) optionSource(i)};
    for (final id in drawn.sources.difference(wanted)) {
      await step(() async {
        await backend.removeSource(id);
        drawn.sources.remove(id);
        drawn.optionRoutes.remove(id);
      });
      if (!current()) return;
    }
    await step(() async {
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
        drawn.optionRoutes[id] = routes[i];
      }
      if (inPlace) {
        await _reorderLines(backend, drawn, order, current);
        return;
      }
      for (final line in order) {
        await _addLayer(backend, _optionLayer(line));
        if (!current()) return;
        // Known before the move: a clear removes it whatever happens next.
        drawn.lines.add(line);
        _listenTaps(backend, line.id);
        await backend.moveLayer(line.id, below: drivenLayer);
        if (!current()) return;
      }
    });
    if (!current()) return;
    await step(() => _drawLabels(backend, drawn, current));
    if (errors.isNotEmpty) {
      Error.throwWithStackTrace(errors.first.$1, errors.first.$2);
    }
  }

  /// Restyles the drawn lines whose selection changed and moves each line
  /// into [order], from the top down (the top one right below the session's
  /// route). The drawn lines are updated once all moves are done; a failure
  /// leaves them as they were, so the next render does it all again.
  Future<void> _reorderLines(
    MapboxBackend backend,
    _Drawn drawn,
    List<_OptionLine> order,
    bool Function() current,
  ) async {
    final was = {for (final l in drawn.lines) l.id: l};
    var below = drivenLayer;
    for (final line in order.reversed) {
      if (was[line.id]?.selected != line.selected) {
        await backend.updateLayer(_optionLayer(line));
        if (!current()) return;
      }
      await backend.moveLayer(line.id, below: below);
      if (!current()) return;
      below = line.id;
    }
    drawn.lines
      ..clear()
      ..addAll(order);
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
      drawn.labelRoutes = null;
      if (drawn.labelLayer) {
        await backend.removeLayer(optionLabels);
        if (!current()) return;
        drawn.labelLayer = false;
        drawn.labelLayerPlaced = false;
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
    drawn.labelRoutes = labels.routes;
    await _removeImages(
      backend,
      drawn,
      current,
      keep: {for (final (id, _) in labels.images) id},
    );
    if (!current()) return;
    if (!drawn.labelLayer) {
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
      );
      if (!current()) return;
      // Known before the move: a clear removes it whatever happens next.
      drawn.labelLayer = true;
      _listenTaps(backend, optionLabels);
    }
    if (drawn.labelLayerPlaced) return;
    await backend.moveLayer(
      optionLabels,
      below: _symbolBelow(optionLabels, drawn),
    );
    if (!current()) return;
    drawn.labelLayerPlaced = true;
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
      // No labels for this generation (the old ones, of another selection,
      // go too); the lines are still shown.
      if (generation == _labelGeneration && _labels != null) {
        _labels = null;
        _fireOptions(_syncLabels);
      }
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
    final cached = _labelImages.remove(key);
    if (cached != null) {
      // Used again: it moves to the most recent end.
      _labelImages[key] = cached;
      return cached;
    }
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

  void _reportError(Object e, StackTrace st, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'navigation_engine_mapbox',
        context: ErrorDescription('while $what'),
      ),
    );
  }

  /// Removes the layer [layer], the source [source] and the images of the
  /// layer (see [_putImages]) of the alternates, the pins or the
  /// destination, when [drawn] holds them. Returns false when something
  /// newer took over meanwhile.
  Future<bool> _removeExtra(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current,
    String layer,
    String source,
  ) async {
    if (drawn.extraLayers.contains(layer)) {
      await backend.removeLayer(layer);
      if (!current()) return false;
      drawn.extraLayers.remove(layer);
      drawn.placedLayers.remove(layer);
    }
    if (drawn.extraSources.contains(source)) {
      await backend.removeSource(source);
      if (!current()) return false;
      drawn.extraSources.remove(source);
    }
    return _putImages(backend, drawn, current, layer, const [], 1);
  }

  /// Adds [images] (id and PNG, rendered at [ratio]) for the layer [layer]
  /// and removes the layer's images no longer among them. Returns false
  /// when something newer took over meanwhile.
  Future<bool> _putImages(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current,
    String layer,
    List<(String, Uint8List)> images,
    double ratio,
  ) async {
    final had = drawn.extraImages.putIfAbsent(layer, () => <String>{});
    for (final (id, png) in images) {
      await backend.addImage(id, ratio, StyleImage.bytes(png));
      if (!current()) return false;
      had.add(id);
    }
    final keep = {for (final (id, _) in images) id};
    for (final id in had.difference(keep)) {
      await backend.removeImage(id);
      if (!current()) return false;
      had.remove(id);
    }
    return true;
  }

  /// Adds the source [id] with [data], or sets its data. Returns false when
  /// something newer took over meanwhile.
  Future<bool> _putExtraSource(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current,
    String id,
    Map<String, Object?> data,
  ) async {
    await _putSource(
      backend,
      id,
      data,
      exists: drawn.extraSources.contains(id),
    );
    if (!current()) return false;
    drawn.extraSources.add(id);
    return true;
  }

  /// Adds [layer] (unless [drawn] holds it), with a tap interaction, and
  /// moves it below the layer [below] names (unless it was moved already).
  /// A failed move is done again on the next update.
  Future<void> _putExtraLayer(
    MapboxBackend backend,
    _Drawn drawn,
    bool Function() current,
    Layer layer,
    String Function() below,
  ) async {
    if (!drawn.extraLayers.contains(layer.id)) {
      await _addLayer(backend, layer);
      if (!current()) return;
      // Known before the move: a removal removes it whatever happens next.
      drawn.extraLayers.add(layer.id);
      _listenTaps(backend, layer.id);
    }
    if (drawn.placedLayers.contains(layer.id)) return;
    await backend.moveLayer(layer.id, below: below());
    if (!current()) return;
    drawn.placedLayers.add(layer.id);
  }

  /// A symbol layer on the source of the same [id]: the image named by each
  /// feature's `image`, anchored at its bottom, drawn in the source's order
  /// (the last on top).
  static SymbolLayer _symbolLayer(String id) => SymbolLayer(
    id: id,
    sourceId: id,
    iconImageExpression: ['get', 'image'],
    iconAnchor: IconAnchor.BOTTOM,
    iconSize: 1,
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
    symbolZOrder: SymbolZOrder.SOURCE,
  );

  // ---- Alternate routes ----

  // What showAlternates was last given; null when no alternates are shown.
  List<AlternateRoute>? _shownAlternates;
  void Function(int index)? _alternateTap;

  // Bumped by every showAlternates / clearAlternates (and bubble change); a
  // bubble render started under an older value is dropped.
  int _alternateGeneration = 0;

  // The texts of the bubbles last asked for; null when none.
  List<String>? _alternateTexts;

  // The rendered bubbles of the shown alternates; null until rendered.
  _AlternateBubbles? _alternateBubbles;

  String Function(AlternateRoute alternate)? _alternateLabel;

  /// The text of the bubble on each alternate, such as "2 min faster"; when
  /// null, [showAlternates] draws no bubbles. Setting it while alternates
  /// are shown paints their bubbles again when the texts change (such as a
  /// new language), and removes them when null.
  String Function(AlternateRoute alternate)? get alternateLabel =>
      _alternateLabel;
  set alternateLabel(String Function(AlternateRoute alternate)? value) {
    _alternateLabel = value;
    final shown = _shownAlternates;
    if (shown == null) return;
    if (value == null) {
      // Nothing drawn or rendering: nothing to remove (a view sets it on
      // every rebuild).
      if (_alternateTexts == null && _alternateBubbles == null) return;
      _alternateGeneration++;
      _alternateTexts = null;
      _alternateBubbles = null;
      _fireOptions(_syncAlternates);
      return;
    }
    if (listEquals([for (final a in shown) value(a)], _alternateTexts)) return;
    unawaited(_renderAlternateBubbles(shown, ++_alternateGeneration));
  }

  Color _alternateColor = MapDefaultColors.alternate;

  /// The colour of the alternate lines (by default
  /// [MapDefaultColors.alternate]); a change restyles them.
  Color get alternateColor => _alternateColor;
  set alternateColor(Color value) {
    if (value == _alternateColor) return;
    _alternateColor = value;
    _restyleAlternates();
  }

  RouteLabelColors _fasterLabelColors = MapDefaultColors.fasterLabels;
  RouteLabelColors _slowerLabelColors = MapDefaultColors.slowerLabels;

  /// The bubble colours of a faster alternate (by default
  /// [MapDefaultColors.fasterLabels], as on every adapter).
  RouteLabelColors get fasterLabelColors => _fasterLabelColors;

  /// The bubble colours of a slower (or as fast) alternate (by default
  /// [MapDefaultColors.slowerLabels]).
  RouteLabelColors get slowerLabelColors => _slowerLabelColors;

  /// Sets the bubble colours; bubbles shown are painted again.
  void setAlternateLabelColors({
    required RouteLabelColors faster,
    required RouteLabelColors slower,
  }) {
    if (faster == _fasterLabelColors && slower == _slowerLabelColors) return;
    _fasterLabelColors = faster;
    _slowerLabelColors = slower;
    final shown = _shownAlternates;
    if (shown != null && _alternateLabel != null) {
      unawaited(_renderAlternateBubbles(shown, ++_alternateGeneration));
    }
  }

  /// Draws [alternates] (see the class documentation); an empty list is
  /// [clearAlternates].
  @override
  void showAlternates(
    List<AlternateRoute> alternates, {
    required void Function(int index) onTap,
  }) {
    if (alternates.isEmpty) {
      clearAlternates();
      return;
    }
    final generation = ++_alternateGeneration;
    _shownAlternates = alternates;
    _alternateTap = onTap;
    if (_alternateLabel == null) {
      _alternateTexts = null;
      _alternateBubbles = null;
    }
    _fireOptions(_syncAlternates);
    if (_alternateLabel != null) {
      unawaited(_renderAlternateBubbles(alternates, generation));
    }
  }

  @override
  void clearAlternates() {
    _alternateGeneration++;
    _shownAlternates = null;
    _alternateTap = null;
    _alternateTexts = null;
    _alternateBubbles = null;
    _fireOptions(_syncAlternates);
  }

  LineLayer _alternatesLine() => _lineLayer(
    alternatesLayer,
    alternatesSource,
    _alternateColor,
    max(1.0, _routeColors.aheadWidth * 0.7),
  );

  // Restyles the drawn alternate line after a colour or width change.
  void _restyleAlternates() {
    if (_shownAlternates == null || !_styleReady) return;
    _fireOptions(() async {
      final backend = _backend;
      if (backend == null || !_styleReady) return;
      if (!_drawn.extraLayers.contains(alternatesLayer)) return;
      await backend.updateLayer(_alternatesLine());
    });
  }

  Future<void> _renderAlternateBubbles(
    List<AlternateRoute> alternates,
    int generation,
  ) async {
    final label = _alternateLabel;
    if (label == null) return;
    final ratio = _pixelRatio;
    final faster = _fasterLabelColors;
    final slower = _slowerLabelColors;
    final List<String> texts;
    final List<Uint8List> images;
    try {
      texts = [for (final a in alternates) label(a)];
      _alternateTexts = texts;
      images = await Future.wait([
        for (var i = 0; i < alternates.length; i++)
          _labelImage(
            texts[i],
            false,
            ratio,
            alternates[i].minutesDelta < 0 ? faster : slower,
          ),
      ]);
    } on Object catch (e, st) {
      // The lines stay; only the bubbles go, and only when this render is
      // still the latest.
      if (generation != _alternateGeneration) return;
      _alternateBubbles = null;
      _fireOptions(_syncAlternates);
      _reportError(e, st, 'rendering alternate route bubbles');
      return;
    }
    if (generation != _alternateGeneration) return;
    _alternateBubbles = _AlternateBubbles.of(alternates, images, ratio);
    _fireOptions(_syncAlternates);
  }

  /// Makes the style hold the shown alternates: the line source and layer
  /// (below the route options and the session's route), and the bubbles
  /// when rendered.
  Future<void> _syncAlternates() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    final generation = _styleGeneration;
    final drawn = _drawn;
    bool current() =>
        generation == _styleGeneration && identical(backend, _backend);
    final shown = _shownAlternates;
    if (shown == null || shown.isEmpty) {
      drawn.alternateLines = null;
      if (!await _removeExtra(
        backend,
        drawn,
        current,
        alternatesLayer,
        alternatesSource,
      )) {
        return;
      }
    } else {
      final routes = [for (final a in shown) a.route];
      final lines = {
        'type': 'FeatureCollection',
        'features': [
          for (var i = 0; i < shown.length; i++)
            {
              'type': 'Feature',
              'id': i,
              'properties': {'index': i},
              'geometry': {
                'type': 'LineString',
                // Only its own part: a tap where it shares the route is a
                // map tap.
                'coordinates': [
                  for (final p in alternateLinePoints(shown[i])) [p.lng, p.lat],
                ],
              },
            },
        ],
      };
      if (!await _putExtraSource(
        backend,
        drawn,
        current,
        alternatesSource,
        lines,
      )) {
        return;
      }
      drawn.alternateLines = routes;
      await _putExtraLayer(
        backend,
        drawn,
        current,
        _alternatesLine(),
        // Under the lowest route option, else under the session's route.
        () => drawn.lines.isEmpty ? drivenLayer : drawn.lines.first.id,
      );
      if (!current()) return;
    }
    final bubbles = shown == null ? null : _alternateBubbles;
    if (bubbles == null) {
      drawn.alternateBubbles = null;
      await _removeExtra(
        backend,
        drawn,
        current,
        alternateLabels,
        alternateLabels,
      );
      return;
    }
    if (!await _putImages(
      backend,
      drawn,
      current,
      alternateLabels,
      bubbles.images,
      bubbles.pixelRatio,
    )) {
      return;
    }
    if (!await _putExtraSource(
      backend,
      drawn,
      current,
      alternateLabels,
      bubbles.features,
    )) {
      return;
    }
    drawn.alternateBubbles = bubbles.routes;
    await _putExtraLayer(
      backend,
      drawn,
      current,
      _symbolLayer(alternateLabels),
      () => _symbolBelow(alternateLabels, drawn),
    );
  }

  // ---- Search pins ----

  Color _pinColor = MapDefaultColors.searchPin;

  /// The colour of the search pins (by default [MapDefaultColors.searchPin],
  /// as on every adapter); a change paints the pins shown again (same places, focus
  /// and taps).
  Color get pinColor => _pinColor;
  set pinColor(Color value) {
    if (value == _pinColor) return;
    _pinColor = value;
    final shown = _shownPins;
    if (shown != null) {
      unawaited(
        showSearchPins(
          shown.places,
          focusedId: shown.focusedId,
          onTap: shown.onTap,
        ),
      );
    }
  }

  /// Renders a search pin as PNG bytes. It defaults to [paintSearchPin];
  /// tests replace it.
  Future<Uint8List> Function({
    required bool focused,
    required double pixelRatio,
    required Color color,
  })?
  pinPainter;

  // What showSearchPins was last given; null when no pins are shown.
  ({
    List<AlongRoutePlace> places,
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  })?
  _shownPins;

  // Bumped by every showSearchPins / clearSearchPins; a pin render started
  // under an older value is dropped.
  int _pinGeneration = 0;

  // The rendered pins; null when none.
  _Pins? _pins;

  /// Pins [places] on the map, the one with [focusedId] larger and on top;
  /// a tap on a pin calls [onTap] (and does not move the camera). Pins are
  /// rendered asynchronously at the pixel ratio; a newer call or
  /// [clearSearchPins] drops a render still pending. When the render fails,
  /// the pins are cleared and the error is reported through [FlutterError].
  /// The future completes once the pins are drawn (or the style is not
  /// ready yet: they are drawn once it is), or were dropped.
  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) async {
    final generation = ++_pinGeneration;
    if (places.isEmpty) {
      _shownPins = null;
      _pins = null;
      await _enqueueOptions(_syncPins);
      return;
    }
    _shownPins = (places: places, focusedId: focusedId, onTap: onTap);
    final ratio = _pixelRatio;
    final color = _pinColor;
    final paint = pinPainter ?? paintSearchPin;
    final List<Uint8List> images;
    try {
      images = await Future.wait([
        Future.sync(
          () => paint(focused: false, pixelRatio: ratio, color: color),
        ),
        Future.sync(
          () => paint(focused: true, pixelRatio: ratio, color: color),
        ),
      ]);
    } on Object catch (e, st) {
      // The pins of an older search must not stand for this one.
      if (generation != _pinGeneration) return;
      _shownPins = null;
      _pins = null;
      _reportError(e, st, 'rendering search pins');
      await _enqueueOptions(_syncPins);
      return;
    }
    if (generation != _pinGeneration) return;
    _pins = _Pins(places, focusedId, images[0], images[1], ratio);
    await _enqueueOptions(_syncPins);
  }

  /// Removes the search pins, also those still being rendered.
  @override
  void clearSearchPins() {
    _pinGeneration++;
    _shownPins = null;
    _pins = null;
    _fireOptions(_syncPins);
  }

  Future<void> _syncPins() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    final generation = _styleGeneration;
    final drawn = _drawn;
    bool current() =>
        generation == _styleGeneration && identical(backend, _backend);
    final pins = _pins;
    if (pins == null) {
      drawn.pins = null;
      await _removeExtra(backend, drawn, current, searchPins, searchPins);
      return;
    }
    if (!await _putImages(backend, drawn, current, searchPins, [
      (searchPinImage, pins.png),
      (searchPinFocusedImage, pins.focusedPng),
    ], pins.pixelRatio)) {
      return;
    }
    if (!await _putExtraSource(
      backend,
      drawn,
      current,
      searchPins,
      pins.features,
    )) {
      return;
    }
    drawn.pins = pins;
    await _putExtraLayer(
      backend,
      drawn,
      current,
      _symbolLayer(searchPins),
      () => _symbolBelow(searchPins, drawn),
    );
  }

  // ---- Destination pin ----

  /// Renders the destination pin as PNG bytes. It defaults to
  /// [paintDestinationPin]; tests replace it.
  Future<Uint8List> Function({required double pixelRatio})?
  destinationPinPainter;

  // Bumped by every showDestinationPin; a render started under an older
  // value is dropped.
  int _destinationGeneration = 0;

  // The destination pin image and the pixel ratio it was rendered at.
  ({double ratio, Future<Uint8List> png})? _destinationImage;

  // The pin shown, once rendered; null when none.
  ({GeoPoint point, Uint8List png, double ratio})? _destinationPin;

  /// Pins the trip's destination at [point] (the shared red pin, anchored
  /// at its tip), replacing the one shown; null removes it. The pin is
  /// rendered asynchronously at the pixel ratio, once per ratio; a newer
  /// call drops a render still pending. When the render fails, the pin is
  /// removed and the error is reported through [FlutterError]. A tap on the
  /// pin does nothing (it is no map tap).
  @override
  void showDestinationPin(GeoPoint? point) {
    final generation = ++_destinationGeneration;
    if (point == null) {
      _destinationPin = null;
      _fireOptions(_syncDestination);
      return;
    }
    unawaited(_showDestination(point, generation));
  }

  Future<void> _showDestination(GeoPoint point, int generation) async {
    final ratio = _pixelRatio;
    final Uint8List png;
    try {
      png = await _destinationPng(ratio);
    } on Object catch (e, st) {
      if (generation != _destinationGeneration) return;
      _destinationPin = null;
      _fireOptions(_syncDestination);
      _reportError(e, st, 'rendering the destination pin');
      return;
    }
    if (generation != _destinationGeneration) return;
    _destinationPin = (point: point, png: png, ratio: ratio);
    _fireOptions(_syncDestination);
  }

  // The pin image at [ratio], rendered once; a failed render is not kept.
  Future<Uint8List> _destinationPng(double ratio) {
    final cached = _destinationImage;
    if (cached != null && cached.ratio == ratio) return cached.png;
    final paint = destinationPinPainter;
    final png = Future.sync(
      () => paint != null
          ? paint(pixelRatio: ratio)
          : paintDestinationPin(pixelRatio: ratio),
    );
    final entry = (ratio: ratio, png: png);
    _destinationImage = entry;
    png.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_destinationImage, entry)) _destinationImage = null;
      },
    );
    return png;
  }

  Future<void> _syncDestination() async {
    final backend = _backend;
    if (backend == null || !_styleReady) return;
    final generation = _styleGeneration;
    final drawn = _drawn;
    bool current() =>
        generation == _styleGeneration && identical(backend, _backend);
    final pin = _destinationPin;
    if (pin == null) {
      await _removeExtra(backend, drawn, current, destination, destination);
      return;
    }
    if (!await _putImages(backend, drawn, current, destination, [
      (destinationImage, pin.png),
    ], pin.ratio)) {
      return;
    }
    if (!await _putExtraSource(
      backend,
      drawn,
      current,
      destination,
      _pointFeatures([(0, pin.point, destinationImage)]),
    )) {
      return;
    }
    await _putExtraLayer(
      backend,
      drawn,
      current,
      SymbolLayer(
        id: destination,
        sourceId: destination,
        iconImage: destinationImage,
        iconAnchor: IconAnchor.BOTTOM,
        iconSize: 1,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      () => _symbolBelow(destination, drawn),
    );
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

/// What a style holds of the route options, the alternates and the pins.
class _Drawn {
  final lines = <_OptionLine>[];
  final sources = <String>{};
  final images = <String>{};
  bool labelSource = false;
  bool labelLayer = false;

  /// Whether the label layer was moved into place (a failed move is done
  /// again on the next update).
  bool labelLayerPlaced = false;

  /// The route each option source holds, by source id.
  final optionRoutes = <String, NavRoute>{};

  /// The routes the option labels stand for, by index; null when none.
  List<NavRoute>? labelRoutes;

  /// The sources and layers of the alternates, the pins and the
  /// destination; the layers moved into place; the images by layer.
  final extraSources = <String>{};
  final extraLayers = <String>{};
  final placedLayers = <String>{};
  final extraImages = <String, Set<String>>{};

  /// The routes the alternate lines and bubbles stand for, by index; null
  /// when none.
  List<NavRoute>? alternateLines;
  List<NavRoute>? alternateBubbles;

  /// The search pins drawn; null when none.
  _Pins? pins;
}

/// The rendered labels of the shown route options.
class _Labels {
  _Labels(this.routes, this.images, this.features, this.pixelRatio);

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
      routes,
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

  /// The route each label stands for, by index.
  final List<NavRoute> routes;

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

/// The rendered bubbles of the shown alternates.
class _AlternateBubbles {
  _AlternateBubbles(this.routes, this.images, this.features, this.pixelRatio);

  /// One bubble per alternate, at most
  /// [MapboxNavigationMap.alternateLabelLead] metres past its divergence
  /// and at most at the middle of the part that differs
  /// ([alternateLabelDistance]).
  factory _AlternateBubbles.of(
    List<AlternateRoute> alternates,
    List<Uint8List> pngs,
    double pixelRatio,
  ) {
    String image(int i) => MapboxNavigationMap.alternateLabelImage(i);
    return _AlternateBubbles(
      [for (final a in alternates) a.route],
      [for (var i = 0; i < alternates.length; i++) (image(i), pngs[i])],
      _pointFeatures([
        for (var i = 0; i < alternates.length; i++)
          (
            i,
            alternates[i].route.pointAt(
              alternateLabelDistance(
                alternates[i],
                lead: MapboxNavigationMap.alternateLabelLead,
              ),
            ),
            image(i),
          ),
      ]),
      pixelRatio,
    );
  }

  /// The route each bubble stands for, by index.
  final List<NavRoute> routes;

  /// The image id and PNG of each bubble.
  final List<(String, Uint8List)> images;

  /// The GeoJSON of the bubble source.
  final Map<String, Object?> features;

  /// The pixel ratio the PNGs were rendered at: their style image scale.
  final double pixelRatio;
}

/// Rendered search pins.
class _Pins {
  _Pins(
    this.places,
    this.focusedId,
    this.png,
    this.focusedPng,
    this.pixelRatio,
  );

  final List<AlongRoutePlace> places;
  final String? focusedId;
  final Uint8List png;
  final Uint8List focusedPng;
  final double pixelRatio;

  /// One point per place, the focused one last (drawn on top).
  Map<String, Object?> get features => _pointFeatures([
    for (var i = 0; i < places.length; i++)
      if (places[i].id != focusedId)
        (i, places[i].position, MapboxNavigationMap.searchPinImage),
    for (var i = 0; i < places.length; i++)
      if (places[i].id == focusedId)
        (i, places[i].position, MapboxNavigationMap.searchPinFocusedImage),
  ]);
}
