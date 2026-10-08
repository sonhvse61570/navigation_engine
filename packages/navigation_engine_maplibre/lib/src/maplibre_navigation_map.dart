import 'dart:async';
import 'dart:math' show Point;

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

/// A [CameraTarget] zoom (the 256 dp world of Google Maps and flutter_map)
/// in MapLibre's scale: its 512 px tiles show the same scale one level
/// lower. Not part of the public API (hidden by the library export).
double toSdkZoom(double zoom) => zoom - 1;

/// The camera position a [CameraTarget] stands for, the zoom converted by
/// [toSdkZoom]. Not part of the public API (hidden by the library export).
CameraPosition toCameraPosition(CameraTarget t) => CameraPosition(
  target: toLatLng(t.position),
  zoom: toSdkZoom(t.zoom),
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

// How many label images are kept (see `_labelImages`).
const _labelImageLimit = 32;

/// [NavigationMap], [VehicleMarkerMap] and [RoutePreviewMap] on top of
/// maplibre_gl.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapLibreMap` callbacks.
/// Camera updates are dropped until the controller exists; the route line,
/// the vehicle and the route options are kept and drawn once the style has
/// loaded (and again after a style reload).
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
/// [labelPainter] in [labelColors] at [pixelRatio], and a point in the
/// source `navigation_engine_option_labels` (properties `index` and
/// `image`), drawn by the symbol layer of the same id, above the route and
/// below the vehicle. Labels are rendered asynchronously and appear
/// together; a newer [showRouteOptions] or [clearRouteOptions] drops renders
/// still pending.
///
/// A tap reaches [onRouteOptionTap] only through the option layers and the
/// label layer (the controller's `onFeatureTapped`); the session's own
/// layers take no taps. [fitRoutes] needs the controller and
/// [viewportSize]; called earlier, it is kept and applied once both exist.
/// Fits account for [padding], the camera insets the adapter sets.
class MapLibreNavigationMap
    implements NavigationMap, VehicleMarkerMap, RoutePreviewMap {
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
  // style (or the controller) is replaced.
  final _drawnLines = <_OptionLine>[];
  final _drawnSources = <String>{};
  bool _labelSourceDrawn = false;
  bool _labelLayerDrawn = false;

  // Route option updates run one at a time, in order.
  Future<void> _optionQueue = Future.value();

  Size? _viewportSize;
  _PendingFit? _pendingFit;

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

  /// The size of the map view, used by [fitRoutes]. Setting it applies a
  /// pending fit when the controller exists.
  Size? get viewportSize => _viewportSize;
  set viewportSize(Size? value) {
    _viewportSize = value;
    _applyPendingFit();
  }

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
    for (final (id, props) in [
      (drivenLayer, _lineProperties(value.driven, value.drivenWidth)),
      (aheadLayer, _lineProperties(value.ahead, value.aheadWidth)),
    ]) {
      _fire(() async {
        final c = _controller;
        if (c != null) await c.setLayerProperties(id, props);
      });
    }
    _restyleOptions();
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

  /// The controller of the map, from [onMapCreated]; null before.
  @visibleForTesting
  MapLibreMapController? get controller => _controller;

  /// Call from `MapLibreMap.onMapCreated`. Route option taps are read from
  /// this controller from now on.
  void onMapCreated(MapLibreMapController controller) {
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    _controller = controller;
    controller.onFeatureTapped.add(_onFeatureTapped);
    // A style load still running is for the old controller: drop it.
    _styleGeneration++;
    _styleReady = false;
    _forgetDrawnOptions();
    _fire(_applyPadding);
    _applyPendingFit();
  }

  /// Call when the style is about to be replaced (a new style string): the
  /// layers are gone until the SDK reports the new style via [onStyleLoaded].
  /// The route options are kept and drawn again then.
  void onStyleChanging() {
    _styleGeneration++;
    _styleReady = false;
    _forgetDrawnOptions();
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
    _forgetDrawnOptions();
    final puck = await _puck();
    if (generation != _styleGeneration) return;
    if (!await _addLayers(c, puck, generation)) return;
    _styleReady = true;
    await _pushRoute();
    await _pushVehicle();
    // The new style has none of the route options: draw them again.
    await _enqueueOptions(_syncOptions);
  }

  /// The camera insets (`setPadding`): the camera target sits at the centre
  /// of the view minus this padding. The view sets it from its focus
  /// padding; [fitRoutes] accounts for it (as `mapPadding`, see
  /// [fitCameraToBounds]).
  EdgeInsets get padding => _padding;

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
        vehicleLayer,
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
    final c = _controller;
    final size = _viewportSize;
    if (c == null || size == null) {
      _pendingFit = _PendingFit(points, padding);
      return;
    }
    _pendingFit = null;
    final update = _fitUpdate(points, size, padding);
    await _guard(() async {
      await c.animateCamera(update);
    });
  }

  void _applyPendingFit() {
    final c = _controller;
    final size = _viewportSize;
    final pending = _pendingFit;
    if (c == null || size == null || pending == null) return;
    _pendingFit = null;
    final update = _fitUpdate(pending.points, size, pending.padding);
    _fire(() async {
      await c.moveCamera(update);
    });
  }

  /// The camera that shows [points] inside [viewport] minus [padding], with
  /// the camera insets ([padding] of the adapter) as the map padding.
  CameraUpdate _fitUpdate(
    List<GeoPoint> points,
    Size viewport,
    EdgeInsets padding,
  ) {
    final target = fitCameraToBounds(
      points,
      viewport,
      padding,
      mapPadding: _padding,
    );
    // fitCameraToBounds uses a 256 dp world; MapLibre's tiles are 512 px.
    return CameraUpdate.newCameraPosition(
      CameraPosition(
        target: toLatLng(target.position),
        zoom: toSdkZoom(target.zoom),
      ),
    );
  }

  /// Stops reading taps and drops what is pending: label renders and a
  /// pending fit. The view calls it when it is disposed.
  void dispose() {
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    _controller = null;
    _styleReady = false;
    _styleGeneration++;
    _labelGeneration++;
    _shownRoutes = null;
    _labels = null;
    _pendingFit = null;
    _labelImages.clear();
    _forgetDrawnOptions();
  }

  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    final routes = _shownRoutes;
    final onTap = onRouteOptionTap;
    if (routes == null || onTap == null) return;
    final index = _tappedIndex(id, layerId);
    if (index != null && index >= 0 && index < routes.length) onTap(index);
  }

  /// The route index of a tapped feature: from the layer id for the option
  /// lines, from the feature id for the labels. Null for any other layer.
  static int? _tappedIndex(String id, String layerId) {
    if (layerId == optionLabels) return num.tryParse(id)?.toInt();
    const casing = '${optionPrefix}casing_';
    if (layerId.startsWith(casing)) {
      return int.tryParse(layerId.substring(casing.length));
    }
    if (layerId.startsWith(optionPrefix)) {
      return int.tryParse(layerId.substring(optionPrefix.length));
    }
    return null;
  }

  void _forgetDrawnOptions() {
    _drawnLines.clear();
    _drawnSources.clear();
    _labelSourceDrawn = false;
    _labelLayerDrawn = false;
  }

  Future<void> _enqueueOptions(Future<void> Function() op) =>
      _optionQueue = _optionQueue.then((_) => _guard(op));

  void _fireOptions(Future<void> Function() op) =>
      unawaited(_enqueueOptions(op));

  // Restyles the drawn option lines after a colour change, in place.
  void _restyleOptions() {
    if (_shownRoutes == null || !_styleReady) return;
    _fireOptions(() async {
      final c = _controller;
      if (c == null || !_styleReady || _shownRoutes == null) return;
      final generation = _styleGeneration;
      for (final line in List.of(_drawnLines)) {
        await c.setLayerProperties(line.id, _optionPaint(line));
        if (generation != _styleGeneration) return;
      }
    });
  }

  /// Makes the style hold what is shown: the option sources, their lines in
  /// the z-order of the selection, and the labels when rendered.
  Future<void> _syncOptions() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final generation = _styleGeneration;
    bool current() =>
        generation == _styleGeneration && identical(c, _controller);
    final routes = _shownRoutes ?? const <NavRoute>[];
    final selected = _shownSelected;

    // The lines are added again: a new selection changes their order.
    for (final line in List.of(_drawnLines.reversed)) {
      await c.removeLayer(line.id);
      if (!current()) return;
      _drawnLines.remove(line);
    }
    final wanted = {for (var i = 0; i < routes.length; i++) optionSource(i)};
    for (final id in _drawnSources.difference(wanted)) {
      await c.removeSource(id);
      if (!current()) return;
      _drawnSources.remove(id);
    }
    for (var i = 0; i < routes.length; i++) {
      final id = optionSource(i);
      await _putSource(
        c,
        id,
        lineFeatureCollection(routes[i].points),
        exists: _drawnSources.contains(id),
      );
      if (!current()) return;
      _drawnSources.add(id);
    }
    for (final line in _lineOrder(routes.length, selected)) {
      await _tolerant(
        () => c.addLineLayer(
          optionSource(line.index),
          line.id,
          _optionPaint(line),
          belowLayerId: drivenLayer,
          enableInteraction: true,
        ),
      );
      if (!current()) return;
      _drawnLines.add(line);
    }
    await _drawLabels(c, current);
  }

  Future<void> _syncLabels() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final generation = _styleGeneration;
    await _drawLabels(
      c,
      () => generation == _styleGeneration && identical(c, _controller),
    );
  }

  /// Adds the rendered labels (images, source, layer), or removes the label
  /// source and layer when there are none.
  Future<void> _drawLabels(
    MapLibreMapController c,
    bool Function() current,
  ) async {
    final labels = _shownRoutes == null ? null : _labels;
    if (labels == null) {
      if (_labelLayerDrawn) {
        await c.removeLayer(optionLabels);
        if (!current()) return;
        _labelLayerDrawn = false;
      }
      if (_labelSourceDrawn) {
        await c.removeSource(optionLabels);
        if (!current()) return;
        _labelSourceDrawn = false;
      }
      return;
    }
    for (final (id, png) in labels.images) {
      await c.addImage(id, png);
      if (!current()) return;
    }
    await _putSource(
      c,
      optionLabels,
      labels.features,
      exists: _labelSourceDrawn,
      promoteId: 'index',
    );
    if (!current()) return;
    _labelSourceDrawn = true;
    if (_labelLayerDrawn) return;
    await _tolerant(
      () => c.addSymbolLayer(
        optionLabels,
        optionLabels,
        const SymbolLayerProperties(
          iconImage: [Expressions.get, 'image'],
          iconAnchor: 'bottom',
          iconSize: 1,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          // The selected label is the last feature: drawn on top.
          symbolZOrder: 'source',
        ),
        belowLayerId: vehicleLayer,
        enableInteraction: true,
      ),
    );
    if (!current()) return;
    _labelLayerDrawn = true;
  }

  /// Adds the source [id], or sets its data when it is already there.
  /// [promoteId] makes a property the feature id on the web.
  Future<void> _putSource(
    MapLibreMapController c,
    String id,
    Map<String, dynamic> data, {
    required bool exists,
    String? promoteId,
  }) async {
    if (!exists) {
      try {
        await c.addGeoJsonSource(id, data, promoteId: promoteId);
        return;
      } on PlatformException catch (e) {
        if (e.code != 'sourceAlreadyExists') rethrow;
      }
    }
    await c.setGeoJsonSource(id, data);
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

  LineLayerProperties _optionPaint(_OptionLine line) {
    final width = _routeColors.aheadWidth;
    final color = line.selected ? _routeColors.ahead : _alternativeColor;
    if (!line.casing) return _lineProperties(color, width);
    final casing = line.selected
        ? Color.lerp(color, const Color(0xFF000000), 0.35)!
        : Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!;
    return _lineProperties(casing, width + 4);
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
    _labels = _Labels.of(routes, selected, images);
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
}

/// A drawn option line layer.
typedef _OptionLine = ({String id, int index, bool casing, bool selected});

/// The key of a cached label image.
typedef _LabelKey = (String, bool, double, RouteLabelColors);

/// The rendered labels of the shown route options.
class _Labels {
  _Labels(this.images, this.features);

  /// One label per route, at the middle of the route; the selected one last.
  factory _Labels.of(
    List<NavRoute> routes,
    int selected,
    List<Uint8List> pngs,
  ) {
    final order = [
      for (var i = 0; i < routes.length; i++)
        if (i != selected) i,
      if (selected >= 0 && selected < routes.length) selected,
    ];
    String image(int i) =>
        MapLibreNavigationMap.optionLabelImage(i, selected: i == selected);
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
    );
  }

  /// The image id and PNG of each label.
  final List<(String, Uint8List)> images;

  /// The GeoJSON of the label source.
  final Map<String, dynamic> features;
}

/// A [MapLibreNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}
