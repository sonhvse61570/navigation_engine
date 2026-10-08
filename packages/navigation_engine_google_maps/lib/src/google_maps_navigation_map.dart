import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'fit_camera.dart';
import 'ui/google_style_colors.dart';
import 'ui/route_label.dart';

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// The camera position a [CameraTarget] stands for.
CameraPosition toCameraPosition(CameraTarget t) => CameraPosition(
  target: toLatLng(t.position),
  zoom: t.zoom,
  bearing: t.bearing,
  tilt: t.tilt,
);

/// The two route polylines (driven, ahead) for [driven] / [ahead].
Set<Polyline> routePolylines(
  List<GeoPoint> driven,
  List<GeoPoint> ahead,
  RouteColors colors,
) => {
  if (driven.length >= 2)
    Polyline(
      polylineId: const PolylineId('navigation_engine_driven'),
      points: driven.map(toLatLng).toList(),
      color: colors.driven,
      width: colors.drivenWidth.round(),
      zIndex: 1,
    ),
  if (ahead.length >= 2)
    Polyline(
      polylineId: const PolylineId('navigation_engine_ahead'),
      points: ahead.map(toLatLng).toList(),
      color: colors.ahead,
      width: colors.aheadWidth.round(),
      zIndex: 2,
    ),
};

// How many label images are kept (see `_labelImages`).
const _labelImageLimit = 32;

/// The casing and line polylines of route option [index].
///
/// Ids are `navigation_engine_option_casing_<index>` and
/// `navigation_engine_option_<index>`; a tap on either calls [onTap].
Set<Polyline> _optionPolylines(
  int index,
  NavRoute route, {
  required bool selected,
  required Color lineColor,
  required Color casingColor,
  required int width,
  required VoidCallback onTap,
}) {
  final points = route.points.map(toLatLng).toList();
  return {
    Polyline(
      polylineId: PolylineId('navigation_engine_option_casing_$index'),
      points: points,
      color: casingColor,
      width: width + 4,
      zIndex: selected ? 5 : 3,
      consumeTapEvents: true,
      onTap: onTap,
    ),
    Polyline(
      polylineId: PolylineId('navigation_engine_option_$index'),
      points: points,
      color: lineColor,
      width: width,
      zIndex: selected ? 6 : 4,
      consumeTapEvents: true,
      onTap: onTap,
    ),
  };
}

/// [NavigationMap], [VehicleMarkerMap] and [RoutePreviewMap] on top of
/// google_maps_flutter.
///
/// ## Route options
///
/// [showRouteOptions] fills [routeOptionPolylines] with a casing and a line
/// per route; the selected one is drawn on top in the route colour, the
/// others muted. Their ids all start with `navigation_engine_option_`; a tap
/// reaches [onRouteOptionTap].
///
/// With [routeLabel] set, [routeOptionMarkers] also gets one label bubble per
/// route at the middle of the route (id `navigation_engine_option_label_<i>`).
/// Bubbles are rendered asynchronously, in [labelColors], and appear
/// together; a newer [showRouteOptions] or [clearRouteOptions] drops renders
/// still pending. [fitRoutes] needs the map controller and [viewportSize];
/// called earlier, it is kept and applied once both exist. Fits account for
/// [mapPadding]; camera errors are reported through [FlutterError], not
/// thrown.
///
/// Wire [onMapCreated] to `GoogleMap.onMapCreated`; camera updates before
/// are dropped. Polylines and markers are widget properties in
/// google_maps_flutter, so the route line and the vehicle marker are
/// exposed as listenables for the view (or an app's own `GoogleMap`) to
/// build from.
class GoogleMapsNavigationMap
    implements NavigationMap, VehicleMarkerMap, RoutePreviewMap {
  GoogleMapsNavigationMap({RouteColors routeColors = const RouteColors()})
    // A named parameter cannot be a private initializing formal.
    // ignore: prefer_initializing_formals
    : _routeColors = routeColors;

  RouteColors _routeColors;
  List<GeoPoint> _driven = const [];
  List<GeoPoint> _ahead = const [];

  RouteColors get routeColors => _routeColors;

  /// Rebuilds the drawn route polylines with the new colours and widths.
  set routeColors(RouteColors value) {
    final old = _routeColors;
    if (value.driven == old.driven &&
        value.ahead == old.ahead &&
        value.drivenWidth == old.drivenWidth &&
        value.aheadWidth == old.aheadWidth) {
      return;
    }
    _routeColors = value;
    if (polylines.value.isNotEmpty) {
      polylines.value = routePolylines(_driven, _ahead, value);
    }
    _redrawRouteOptions();
  }

  final polylines = ValueNotifier<Set<Polyline>>(const {});
  final vehicleMarker = ValueNotifier<Marker?>(null);

  /// The route option polylines drawn by [showRouteOptions].
  final routeOptionPolylines = ValueNotifier<Set<Polyline>>(const {});

  /// The route option label markers (empty until the labels are rendered).
  final routeOptionMarkers = ValueNotifier<Set<Marker>>(const {});

  /// The text of the label bubble of a route option, such as its duration.
  /// When null, [showRouteOptions] adds no label markers.
  String Function(NavRoute route)? routeLabel;

  /// The pixel ratio of the label images; the view sets it from the device.
  double labelPixelRatio = 3;

  /// Renders a label bubble as PNG bytes in [labelColors] (passed as
  /// `colors`). It defaults to [paintRouteLabel] with the selected bubble in
  /// `accent` / `onAccent` and the others in `surface` / `onSurface`; tests
  /// replace it to control when (and whether) a render finishes.
  Future<Uint8List> Function(
    String text, {
    required bool selected,
    required double pixelRatio,
    required GoogleStyleColors colors,
  })?
  labelPainter;

  GoogleStyleColors _labelColors = GoogleStyleColors.day;

  /// The colours of the label bubbles (see [labelPainter]). Changing them
  /// while options are shown renders the labels again; the old bubbles stay
  /// until the new ones are ready.
  GoogleStyleColors get labelColors => _labelColors;
  set labelColors(GoogleStyleColors value) {
    final old = _labelColors;
    if (identical(value, old) ||
        (value.accent == old.accent &&
            value.onAccent == old.onAccent &&
            value.surface == old.surface &&
            value.onSurface == old.onSurface)) {
      _labelColors = value;
      return;
    }
    _labelColors = value;
    final routes = _shownRoutes;
    if (routes != null && routeLabel != null) {
      unawaited(_showLabels(routes, _shownSelected, ++_labelGeneration));
    }
  }

  /// The padding of the map widget itself (`GoogleMap.padding`), which
  /// moves where the SDK puts the camera target; [fitRoutes] and a pending
  /// fit account for it (see [fitCameraToBounds]). The view sets it from its
  /// focus padding. Setting it moves nothing: the next fit uses it.
  EdgeInsets mapPadding = EdgeInsets.zero;

  // Bumped by every showRouteOptions / clearRouteOptions; a label render
  // started under an older value is dropped.
  int _labelGeneration = 0;

  /// Called with the route index when a route option is tapped.
  void Function(int index)? onRouteOptionTap;

  Color _alternativeColor = GoogleStyleColors.day.alternative;

  /// The colour of the route options that are not selected. Changing it
  /// while options are shown redraws their polylines (same ids); the labels
  /// keep their bubbles.
  Color get alternativeColor => _alternativeColor;
  set alternativeColor(Color value) {
    if (value == _alternativeColor) return;
    _alternativeColor = value;
    _redrawRouteOptions();
  }

  // What showRouteOptions was last given; null when no options are shown.
  List<NavRoute>? _shownRoutes;
  int _shownSelected = 0;

  // Label images by (text, selected, pixel ratio, accent, onAccent, surface,
  // onSurface), oldest first. The futures are kept, so a render still
  // running is shared too.
  final _labelImages = <_LabelKey, Future<Uint8List>>{};

  Size? _viewportSize;
  _PendingFit? _pendingFit;

  /// The size of the map view, used by [fitRoutes]. Setting it applies a
  /// pending fit when the map controller exists.
  Size? get viewportSize => _viewportSize;
  set viewportSize(Size? value) {
    _viewportSize = value;
    _applyPendingFit();
  }

  BitmapDescriptor _vehicleIcon = BitmapDescriptor.defaultMarker;

  /// The vehicle icon for [vehicleMarker]; set it with
  /// `BitmapDescriptor.bytes(png, imagePixelRatio: ratio)`. A marker already
  /// shown gets the new icon.
  BitmapDescriptor get vehicleIcon => _vehicleIcon;
  set vehicleIcon(BitmapDescriptor value) {
    _vehicleIcon = value;
    final shown = vehicleMarker.value;
    if (shown != null) vehicleMarker.value = shown.copyWith(iconParam: value);
  }

  GoogleMapController? _controller;

  void onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _applyPendingFit();
  }

  void _applyPendingFit() {
    final controller = _controller;
    final size = _viewportSize;
    final pending = _pendingFit;
    if (controller == null || size == null || pending == null) return;
    _pendingFit = null;
    final target = fitCameraToBounds(
      pending.points,
      size,
      pending.padding,
      mapPadding: mapPadding,
    );
    unawaited(
      controller
          .moveCamera(CameraUpdate.newCameraPosition(toCameraPosition(target)))
          .catchError(
            (Object e, StackTrace st) =>
                _reportCameraError(e, st, 'applying a pending route fit'),
          ),
    );
  }

  void _reportCameraError(Object e, StackTrace st, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'navigation_engine_google_maps',
        context: ErrorDescription('while $what'),
      ),
    );
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
    polylines.value = routePolylines(driven, ahead, _routeColors);
  }

  @override
  void clearRoute() {
    _driven = _ahead = const [];
    polylines.value = const {};
  }

  @override
  void showRouteOptions(List<NavRoute> routes, int selected) {
    final generation = ++_labelGeneration;
    _shownRoutes = routes;
    _shownSelected = selected;
    routeOptionMarkers.value = const {};
    routeOptionPolylines.value = _buildOptionPolylines(routes, selected);
    if (routeLabel != null) {
      unawaited(_showLabels(routes, selected, generation));
    }
  }

  Set<Polyline> _buildOptionPolylines(List<NavRoute> routes, int selected) {
    final width = _routeColors.aheadWidth.round();
    return {
      for (var i = 0; i < routes.length; i++)
        ..._optionPolylines(
          i,
          routes[i],
          selected: i == selected,
          lineColor: i == selected ? _routeColors.ahead : alternativeColor,
          casingColor: i == selected
              ? Color.lerp(_routeColors.ahead, const Color(0xFF000000), 0.35)!
              : Color.lerp(alternativeColor, const Color(0xFFFFFFFF), 0.5)!,
          width: width,
          onTap: () => onRouteOptionTap?.call(i),
        ),
    };
  }

  // Draws the shown options again after a colour change. The labels, and the
  // renders still pending, are left alone.
  void _redrawRouteOptions() {
    final routes = _shownRoutes;
    if (routes == null) return;
    routeOptionPolylines.value = _buildOptionPolylines(routes, _shownSelected);
  }

  Future<Uint8List> _labelImage(
    String text,
    bool selected,
    double ratio,
    GoogleStyleColors colors,
  ) {
    final key = (
      text,
      selected,
      ratio,
      colors.accent,
      colors.onAccent,
      colors.surface,
      colors.onSurface,
    );
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
              selectedColor: colors.accent,
              selectedTextColor: colors.onAccent,
              color: colors.surface,
              textColor: colors.onSurface,
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

  Future<void> _showLabels(
    List<NavRoute> routes,
    int selected,
    int generation,
  ) async {
    final label = routeLabel!;
    final ratio = labelPixelRatio;
    final colors = _labelColors;
    final List<Uint8List> images;
    try {
      images = await Future.wait([
        for (var i = 0; i < routes.length; i++)
          _labelImage(label(routes[i]), i == selected, ratio, colors),
      ]);
    } on Object {
      // No labels for this generation; the polylines are still shown.
      return;
    }
    if (generation != _labelGeneration) return;
    routeOptionMarkers.value = {
      for (var i = 0; i < routes.length; i++)
        Marker(
          markerId: MarkerId('navigation_engine_option_label_$i'),
          position: toLatLng(routes[i].pointAt(routes[i].length / 2)),
          anchor: const Offset(0.5, 1),
          icon: BitmapDescriptor.bytes(images[i], imagePixelRatio: ratio),
          zIndexInt: i == selected ? 7 : 5,
          onTap: () => onRouteOptionTap?.call(i),
        ),
    };
  }

  @override
  void clearRouteOptions() {
    _labelGeneration++;
    _shownRoutes = null;
    _pendingFit = null;
    routeOptionPolylines.value = const {};
    routeOptionMarkers.value = const {};
  }

  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {
    final points = [for (final r in routes) ...r.points];
    if (points.isEmpty) return;
    final controller = _controller;
    final size = _viewportSize;
    if (controller == null || size == null) {
      _pendingFit = _PendingFit(points, padding);
      return;
    }
    _pendingFit = null;
    final target = fitCameraToBounds(
      points,
      size,
      padding,
      mapPadding: mapPadding,
    );
    await controller
        .animateCamera(CameraUpdate.newCameraPosition(toCameraPosition(target)))
        .catchError(
          (Object e, StackTrace st) =>
              _reportCameraError(e, st, 'fitting route options'),
        );
  }

  @override
  void showVehicle(GeoPoint position, double bearing) {
    vehicleMarker.value = Marker(
      markerId: const MarkerId('navigation_engine_vehicle'),
      position: toLatLng(position),
      rotation: bearing,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon: vehicleIcon,
      zIndexInt: 10,
    );
  }

  @override
  void hideVehicle() => vehicleMarker.value = null;

  void dispose() {
    polylines.dispose();
    vehicleMarker.dispose();
    routeOptionPolylines.dispose();
    routeOptionMarkers.dispose();
    _labelGeneration++;
    _shownRoutes = null;
    _labelImages.clear();
    _pendingFit = null;
    _controller = null;
  }

  @visibleForTesting
  bool get hasController => _controller != null;
}

/// The key of a cached label image.
typedef _LabelKey = (String, bool, double, Color, Color, Color, Color);

/// A [GoogleMapsNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}

/// PNG bytes → marker icon at the given pixel ratio.
BitmapDescriptor vehicleIconFrom(Uint8List png, {double pixelRatio = 3}) =>
    BitmapDescriptor.bytes(png, imagePixelRatio: pixelRatio);
