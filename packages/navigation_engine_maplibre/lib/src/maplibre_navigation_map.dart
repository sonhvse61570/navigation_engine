import 'dart:async';
import 'dart:math' show Point, max;

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

/// The paint of the symbol layers of the bubbles and the search pins: the
/// image named by each feature's `image`, anchored at its bottom, drawn in
/// the source's order (the last on top).
const _symbolProperties = SymbolLayerProperties(
  iconImage: [Expressions.get, 'image'],
  iconAnchor: 'bottom',
  iconSize: 1,
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
  symbolZOrder: 'source',
);

/// A GeoJSON feature collection of one point feature per entry of [points],
/// its id and `index` property the entry's index, its `image` property
/// from [image].
Map<String, dynamic> _pointFeatures(
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

/// [NavigationMap], [VehicleMarkerMap], [RoutePreviewMap],
/// [AlternateRoutesMap], [SearchPinsMap] and [DestinationPinMap] on top of
/// maplibre_gl.
///
/// Wire [onMapCreated] and [onStyleLoaded] to the `MapLibreMap` callbacks.
/// Camera updates are dropped until the controller exists; the route line,
/// the vehicle and the route options are kept and drawn once the style has
/// loaded (and again after a style reload).
///
/// The source, layer and image ids are reserved (see [drivenSource],
/// [aheadSource], [vehicleSource], [vehicleImageId], every id starting
/// with `navigation_engine_option_`, `navigation_engine_alternate`,
/// `navigation_engine_search` or `navigation_engine_destination`): do not
/// reuse them.
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
/// layers take no taps. A tap on a line or label the style still holds
/// from an older list, which stands for another route than the option now
/// at its index, is ignored. [fitRoutes] needs the controller and
/// [viewportSize]; called earlier, it is kept and applied once both exist.
/// Fits account for [padding], the camera insets the adapter sets.
///
/// ## Alternate routes
///
/// [showAlternates] draws the alternates as the line features of one
/// GeoJSON source and line layer, [alternatesSource] and [alternatesLayer],
/// below the session's route, in [alternateColor] and 70 % as wide as the
/// route. A line is the alternate's own part ([alternateLinePoints]): from
/// 40 m before it leaves the route to 40 m after it rejoins it, so a tap on
/// the route where the two share the road is a map tap, as on every
/// adapter. An empty list is [clearAlternates]. With [alternateLabel] set, each gets a bubble (image
/// [alternateLabelImage], rendered like the route option labels in
/// [fasterLabelColors] or [slowerLabelColors]) in the symbol source and
/// layer [alternateLabels], at the middle of the part that differs (from
/// the divergence to the rejoin, else the end) but at most
/// [alternateLabelLead] metres past the divergence
/// ([alternateLabelDistance]), so always on its line. A tap on a line or a
/// bubble calls the `onTap` given to [showAlternates]. Until the new lines
/// and bubbles are drawn the old ones stay, but a tap on one that stands
/// for another route than the alternate now at its index is ignored. A
/// failed bubble render removes the bubbles (the lines stay) and is
/// reported through [FlutterError].
///
/// ## Search pins and the destination pin
///
/// [showSearchPins] draws one pin per place (the images [searchPinImage]
/// and [searchPinFocusedImage], rendered by [pinPainter] in [pinColor]) in
/// the symbol source and layer [searchPins], the focused one last (on
/// top); a tap on one calls `onTap` with its place. [showDestinationPin]
/// draws the shared red pin of [paintDestinationPin] (image
/// [destinationImage]) in the symbol source and layer [destination]. Both
/// are anchored at their tip. A failed render removes the pins and is
/// reported through [FlutterError]; a newer call drops a render still
/// pending.
///
/// The symbol layers sit above the route and below the vehicle, bottom to
/// top: [alternateLabels], [optionLabels], [destination], [searchPins].
/// Every line, bubble and pin is kept and drawn again after a style
/// reload.
///
/// ## Taps on the map's own features
///
/// A tap on a feature the map draws (a route option or its label, an
/// alternate or its bubble, a search pin or the destination pin) drops the
/// one map tap of its gesture, should the platform report one too: the
/// view's `onMapTap` does not get a map tap that comes in the same frame
/// after such a tap, nor one that such a tap follows in the same turn of
/// the event loop. The SDK itself reports no map click for a tap an
/// interactive layer took (`featureTapsTriggersMapClick` is false).
class MapLibreNavigationMap
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
  RouteLabelColors _labelColors = MapDefaultColors.routeLabels;

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

  // The routes the drawn option sources and labels stand for, by index: a
  // tap is reported only while the option at its index is still that route.
  final _drawnOptionRoutes = <int, NavRoute>{};
  List<NavRoute>? _drawnLabelRoutes;
  bool _labelSourceDrawn = false;
  bool _labelLayerDrawn = false;

  // The sources and layers of the alternates, the pins and the destination
  // the current style holds. Emptied with the route options'.
  final _extraSources = <String>{};
  final _extraLayers = <String>{};

  // Style updates (route options, alternates, pins) run one at a time, in
  // order.
  Future<void> _optionQueue = Future.value();

  // Drops the map tap of a gesture a feature the map draws took (see
  // [dispatchMapTap]).
  final _tapGuard = MapTapGuard();

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
    _restyleAlternates();
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
    // The new style has none of the route options, the alternates and the
    // pins: draw them again.
    await _enqueueOptions(_syncOptions);
    await _enqueueOptions(_syncAlternates);
    await _enqueueOptions(_syncDestination);
    await _enqueueOptions(_syncPins);
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
    _forgetDrawnOptions();
  }

  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    switch (layerId) {
      case alternatesLayer:
        _tapGuard.featureTapped();
        _tapAlternate(_featureIndex(id), _drawnAlternateLines);
      case alternateLabels:
        _tapGuard.featureTapped();
        _tapAlternate(_featureIndex(id), _drawnAlternateBubbles);
      case searchPins:
        _tapGuard.featureTapped();
        _tapPin(_featureIndex(id), _drawnPins);
      case destination:
        _tapGuard.featureTapped();
      default:
        if (!layerId.startsWith(optionPrefix)) return;
        _tapGuard.featureTapped();
        _tapOption(id, layerId);
    }
  }

  // A tap on a route option line or label: reported only while the route
  // it was drawn for is still the option at its index.
  void _tapOption(String id, String layerId) {
    final routes = _shownRoutes;
    final onTap = onRouteOptionTap;
    if (routes == null || onTap == null) return;
    final index = _tappedIndex(id, layerId);
    if (index == null || index < 0 || index >= routes.length) return;
    final drawnThere = layerId == optionLabels
        ? _drawnLabelRoutes?.elementAtOrNull(index)
        : _drawnOptionRoutes[index];
    if (!identical(drawnThere, routes[index])) return;
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

  /// The index of a tapped point or line feature, from its id (the SDK may
  /// report a number as a double).
  static int? _featureIndex(String id) => num.tryParse(id)?.toInt();

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
    _drawnOptionRoutes.clear();
    _drawnLabelRoutes = null;
    _labelSourceDrawn = false;
    _labelLayerDrawn = false;
    _extraSources.clear();
    _extraLayers.clear();
    _drawnAlternateLines = null;
    _drawnAlternateBubbles = null;
    _drawnPins = null;
  }

  /// The layer the symbol layer [id] goes below: the lowest of those above
  /// it in [_symbolOrder] the style holds, else the vehicle's.
  String _symbolBelow(String id) {
    for (final above in _symbolOrder.skip(_symbolOrder.indexOf(id) + 1)) {
      final drawn = above == optionLabels
          ? _labelLayerDrawn
          : _extraLayers.contains(above);
      if (drawn) return above;
    }
    return vehicleLayer;
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
    _drawnOptionRoutes.removeWhere((i, _) => i >= routes.length);
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
      _drawnOptionRoutes[i] = routes[i];
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
      _drawnLabelRoutes = null;
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
    _drawnLabelRoutes = labels.routes;
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
        belowLayerId: _symbolBelow(optionLabels),
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

  void _reportError(Object e, StackTrace st, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'navigation_engine_maplibre',
        context: ErrorDescription('while $what'),
      ),
    );
  }

  /// Removes the layer [layer] and the source [source] (of the alternates,
  /// the pins or the destination) when the style holds them. Returns false
  /// when the style or the controller changed meanwhile.
  Future<bool> _removeExtra(
    MapLibreMapController c,
    bool Function() current,
    String layer,
    String source,
  ) async {
    if (_extraLayers.contains(layer)) {
      await c.removeLayer(layer);
      if (!current()) return false;
      _extraLayers.remove(layer);
    }
    if (_extraSources.contains(source)) {
      await c.removeSource(source);
      if (!current()) return false;
      _extraSources.remove(source);
    }
    return true;
  }

  /// Adds the source [id] with [data], or sets its data. Returns false when
  /// the style or the controller changed meanwhile.
  Future<bool> _putExtraSource(
    MapLibreMapController c,
    bool Function() current,
    String id,
    Map<String, dynamic> data,
  ) async {
    await _putSource(
      c,
      id,
      data,
      exists: _extraSources.contains(id),
      promoteId: 'index',
    );
    if (!current()) return false;
    _extraSources.add(id);
    return true;
  }

  /// Adds the interactive symbol layer [id] on the source [id] in its place
  /// of [_symbolOrder], unless the style holds it.
  Future<void> _putSymbolLayer(
    MapLibreMapController c,
    bool Function() current,
    String id, {
    SymbolLayerProperties properties = _symbolProperties,
  }) async {
    if (_extraLayers.contains(id)) return;
    await _tolerant(
      () => c.addSymbolLayer(
        id,
        id,
        properties,
        belowLayerId: _symbolBelow(id),
        enableInteraction: true,
      ),
    );
    if (!current()) return;
    _extraLayers.add(id);
  }

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

  // The routes the drawn alternate lines and bubbles stand for, by index;
  // null while the style holds none.
  List<NavRoute>? _drawnAlternateLines;
  List<NavRoute>? _drawnAlternateBubbles;

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

  LineLayerProperties _alternatePaint() =>
      _lineProperties(_alternateColor, max(1, _routeColors.aheadWidth * 0.7));

  // Restyles the drawn alternate line after a colour or width change.
  void _restyleAlternates() {
    if (_shownAlternates == null || !_styleReady) return;
    _fireOptions(() async {
      final c = _controller;
      if (c == null || !_styleReady) return;
      if (!_extraLayers.contains(alternatesLayer)) return;
      await c.setLayerProperties(alternatesLayer, _alternatePaint());
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
    _alternateBubbles = _AlternateBubbles.of(alternates, images);
    _fireOptions(_syncAlternates);
  }

  /// Makes the style hold the shown alternates: the line source and layer,
  /// and the bubbles when rendered.
  Future<void> _syncAlternates() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final generation = _styleGeneration;
    bool current() =>
        generation == _styleGeneration && identical(c, _controller);
    final shown = _shownAlternates;
    if (shown == null || shown.isEmpty) {
      if (!await _removeExtra(c, current, alternatesLayer, alternatesSource)) {
        return;
      }
      _drawnAlternateLines = null;
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
      if (!await _putExtraSource(c, current, alternatesSource, lines)) return;
      _drawnAlternateLines = routes;
      if (!_extraLayers.contains(alternatesLayer)) {
        await _tolerant(
          () => c.addLineLayer(
            alternatesSource,
            alternatesLayer,
            _alternatePaint(),
            belowLayerId: drivenLayer,
            enableInteraction: true,
          ),
        );
        if (!current()) return;
        _extraLayers.add(alternatesLayer);
      }
    }
    final bubbles = shown == null ? null : _alternateBubbles;
    if (bubbles == null) {
      if (await _removeExtra(c, current, alternateLabels, alternateLabels)) {
        _drawnAlternateBubbles = null;
      }
      return;
    }
    for (final (id, png) in bubbles.images) {
      await c.addImage(id, png);
      if (!current()) return;
    }
    if (!await _putExtraSource(c, current, alternateLabels, bubbles.features)) {
      return;
    }
    _drawnAlternateBubbles = bubbles.routes;
    await _putSymbolLayer(c, current, alternateLabels);
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

  // The rendered pins, and the ones the style holds (for taps).
  _Pins? _pins;
  _Pins? _drawnPins;

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
    _pins = _Pins(places, focusedId, onTap, images[0], images[1]);
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
    final c = _controller;
    if (c == null || !_styleReady) return;
    final generation = _styleGeneration;
    bool current() =>
        generation == _styleGeneration && identical(c, _controller);
    final pins = _pins;
    if (pins == null) {
      if (await _removeExtra(c, current, searchPins, searchPins)) {
        _drawnPins = null;
      }
      return;
    }
    await c.addImage(searchPinImage, pins.png);
    if (!current()) return;
    await c.addImage(searchPinFocusedImage, pins.focusedPng);
    if (!current()) return;
    if (!await _putExtraSource(c, current, searchPins, pins.features)) return;
    _drawnPins = pins;
    await _putSymbolLayer(c, current, searchPins);
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
  ({GeoPoint point, Uint8List png})? _destinationPin;

  /// Pins the trip's destination at [point] (the shared red pin, anchored
  /// at its tip), replacing the one shown; null removes it. The pin is
  /// rendered asynchronously at the pixel ratio, once per ratio; a newer
  /// call drops a render still pending. When the render fails, the pin is
  /// removed and the error is reported through [FlutterError]. A tap on the
  /// pin does nothing.
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
    final Uint8List png;
    try {
      png = await _destinationPng(_pixelRatio);
    } on Object catch (e, st) {
      if (generation != _destinationGeneration) return;
      _destinationPin = null;
      _fireOptions(_syncDestination);
      _reportError(e, st, 'rendering the destination pin');
      return;
    }
    if (generation != _destinationGeneration) return;
    _destinationPin = (point: point, png: png);
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
    final c = _controller;
    if (c == null || !_styleReady) return;
    final generation = _styleGeneration;
    bool current() =>
        generation == _styleGeneration && identical(c, _controller);
    final pin = _destinationPin;
    if (pin == null) {
      await _removeExtra(c, current, destination, destination);
      return;
    }
    await c.addImage(destinationImage, pin.png);
    if (!current()) return;
    if (!await _putExtraSource(
      c,
      current,
      destination,
      _pointFeatures([(0, pin.point, destinationImage)]),
    )) {
      return;
    }
    await _putSymbolLayer(
      c,
      current,
      destination,
      properties: const SymbolLayerProperties(
        iconImage: destinationImage,
        iconAnchor: 'bottom',
        iconSize: 1,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );
  }
}

/// A drawn option line layer.
typedef _OptionLine = ({String id, int index, bool casing, bool selected});

/// The key of a cached label image.
typedef _LabelKey = (String, bool, double, RouteLabelColors);

/// The rendered labels of the shown route options.
class _Labels {
  _Labels(this.routes, this.images, this.features);

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
    );
  }

  /// The routes the labels stand for, by index.
  final List<NavRoute> routes;

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

/// The rendered bubbles of the shown alternates.
class _AlternateBubbles {
  _AlternateBubbles(this.routes, this.images, this.features);

  /// One bubble per alternate, at most
  /// [MapLibreNavigationMap.alternateLabelLead] metres past its divergence
  /// and at most at the middle of the part that differs
  /// ([alternateLabelDistance]).
  factory _AlternateBubbles.of(
    List<AlternateRoute> alternates,
    List<Uint8List> pngs,
  ) {
    String image(int i) => MapLibreNavigationMap.alternateLabelImage(i);
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
                lead: MapLibreNavigationMap.alternateLabelLead,
              ),
            ),
            image(i),
          ),
      ]),
    );
  }

  /// The route each bubble stands for, by index.
  final List<NavRoute> routes;

  /// The image id and PNG of each bubble.
  final List<(String, Uint8List)> images;

  /// The GeoJSON of the bubble source.
  final Map<String, dynamic> features;
}

/// Rendered search pins.
class _Pins {
  _Pins(this.places, this.focusedId, this.onTap, this.png, this.focusedPng);

  final List<AlongRoutePlace> places;
  final String? focusedId;
  final void Function(AlongRoutePlace place)? onTap;
  final Uint8List png;
  final Uint8List focusedPng;

  /// One point per place, the focused one last (drawn on top).
  Map<String, dynamic> get features => _pointFeatures([
    for (var i = 0; i < places.length; i++)
      if (places[i].id != focusedId)
        (i, places[i].position, MapLibreNavigationMap.searchPinImage),
    for (var i = 0; i < places.length; i++)
      if (places[i].id == focusedId)
        (i, places[i].position, MapLibreNavigationMap.searchPinFocusedImage),
  ]);
}

/// Delivers a tap on [map] itself through [deliver], unless it belongs to
/// a tap on a feature the map draws (see the map's "Taps on the map's own
/// features"): one that came before it in the same frame, or one that comes
/// in the same turn of the event loop. [deliver] runs after that turn, and
/// not at all once the map is disposed. The view calls it from
/// `MapLibreMap.onMapClick`. Not part of the public API (hidden by the
/// library export).
void dispatchMapTap(MapLibreNavigationMap map, VoidCallback deliver) =>
    map._tapGuard.dispatch(deliver);
