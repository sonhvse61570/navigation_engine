import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// The route line as flutter_map points.
typedef FlutterMapRouteLine = ({List<LatLng> driven, List<LatLng> ahead});

/// The vehicle marker as flutter_map values.
typedef FlutterMapVehicle = ({LatLng position, double bearing});

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

// The room around a label bubble, so a font wider than the estimate still
// fits its box (the box is transparent and does not take taps).
const _labelSlack = 48.0;
// The bubble's text size and horizontal padding (see [RouteLabelBubble]).
const _labelFontSize = 14.0;
const _labelPaddingX = 10.0;
const _labelHeight = 48.0;

/// [NavigationMap], [VehicleMarkerMap] and [RoutePreviewMap] on top of
/// flutter_map.
///
/// flutter_map applies camera moves synchronously and has no tilt, so
/// [CameraTarget.tilt] is ignored. Its rotation is counter-clockwise, hence
/// the minus sign that puts the vehicle's heading up. The route line and the
/// vehicle marker are exposed as listenables for the map's layers.
///
/// ## Route options
///
/// [showRouteOptions] fills [routeOptionLines] with a casing and a line per
/// route, each with `hitValue` set to the route's index; the muted routes
/// come first, so the selected one is drawn on top and hit first. The view
/// reads the hit through a `PolylineLayer.hitNotifier` and calls
/// [onRouteOptionTap]. With [routeLabel] set, [routeOptionLabels] also gets
/// a [RouteLabelBubble] marker at the middle of each route. Labels are
/// widgets, so they are rebuilt synchronously.
///
/// [fitRoutes] needs the map to be ready ([onMapReady]) and [viewportSize];
/// called earlier, it is kept and applied once both exist. Fits account for
/// [mapPadding].
class FlutterMapNavigationMap
    implements NavigationMap, VehicleMarkerMap, RoutePreviewMap {
  FlutterMapNavigationMap({MapController? controller})
    : controller = controller ?? MapController();

  final MapController controller;
  final route = ValueNotifier<FlutterMapRouteLine?>(null);
  final vehicle = ValueNotifier<FlutterMapVehicle?>(null);

  /// The route option lines drawn by [showRouteOptions]: a casing and a line
  /// per route, bottom to top, each with `hitValue` set to the route index.
  final routeOptionLines = ValueNotifier<List<Polyline<Object>>>(const []);

  /// The route option label markers (empty without [routeLabel]).
  final routeOptionLabels = ValueNotifier<List<Marker>>(const []);

  /// The text of the label bubble of a route option, such as its duration.
  /// When null, [showRouteOptions] adds no labels. It is read when the
  /// options are shown.
  String Function(NavRoute route)? routeLabel;

  /// Called with the route index when a route option is tapped.
  void Function(int index)? onRouteOptionTap;

  /// How far below the map centre the followed point sits, in logical
  /// pixels (set by the view from its focus padding).
  double focusOffset = 0;

  /// The padding of the map area that the camera target is centred in (the
  /// view sets it from its focus padding); [fitRoutes] and a pending fit
  /// account for it (see [fitCameraToBounds]). Setting it moves nothing: the
  /// next fit uses it.
  EdgeInsets mapPadding = EdgeInsets.zero;

  RouteColors _routeColors = const RouteColors();
  Color _alternativeColor = const Color(0xFF9AA0A6);
  RouteLabelColors _labelColors = const RouteLabelColors();

  /// The colours and width of the selected option. Changing them while
  /// options are shown redraws the lines.
  RouteColors get routeColors => _routeColors;
  set routeColors(RouteColors value) {
    final old = _routeColors;
    if (value.driven == old.driven &&
        value.ahead == old.ahead &&
        value.drivenWidth == old.drivenWidth &&
        value.aheadWidth == old.aheadWidth) {
      return;
    }
    _routeColors = value;
    _redrawLines();
  }

  /// The colour of the route options that are not selected. Changing it
  /// while options are shown redraws their lines.
  Color get alternativeColor => _alternativeColor;
  set alternativeColor(Color value) {
    if (value == _alternativeColor) return;
    _alternativeColor = value;
    _redrawLines();
  }

  /// The colours of the label bubbles. Changing them while options are shown
  /// rebuilds the labels.
  RouteLabelColors get labelColors => _labelColors;
  set labelColors(RouteLabelColors value) {
    if (value == _labelColors) return;
    _labelColors = value;
    final routes = _shownRoutes;
    if (routes != null) _redrawLabels(routes, _shownSelected);
  }

  // What showRouteOptions was last given; null when no options are shown.
  List<NavRoute>? _shownRoutes;
  int _shownSelected = 0;

  bool _ready = false;
  Size? _viewportSize;
  _PendingFit? _pendingFit;

  /// The size of the map view, used by [fitRoutes]. Setting it applies a
  /// pending fit when the map is ready.
  Size? get viewportSize => _viewportSize;
  set viewportSize(Size? value) {
    _viewportSize = value;
    _applyPendingFit();
  }

  /// Call from `MapOptions.onMapReady`; camera updates before are dropped.
  void onMapReady() {
    _ready = true;
    _applyPendingFit();
  }

  @override
  Future<void> moveCamera(CameraTarget target) async {
    if (!_ready) return;
    controller.rotate(-target.bearing);
    controller.move(
      toLatLng(target.position),
      target.zoom,
      // The offset is in screen space, whatever the rotation.
      offset: Offset(0, focusOffset),
    );
  }

  @override
  void showRoute(List<GeoPoint> driven, List<GeoPoint> ahead) {
    route.value = (
      driven: driven.map(toLatLng).toList(),
      ahead: ahead.map(toLatLng).toList(),
    );
  }

  @override
  void clearRoute() => route.value = null;

  @override
  void showVehicle(GeoPoint position, double bearing) =>
      vehicle.value = (position: toLatLng(position), bearing: bearing);

  @override
  void hideVehicle() => vehicle.value = null;

  @override
  void showRouteOptions(List<NavRoute> routes, int selected) {
    _shownRoutes = routes;
    _shownSelected = selected;
    _redrawLines();
    _redrawLabels(routes, selected);
  }

  @override
  void clearRouteOptions() {
    _shownRoutes = null;
    _pendingFit = null;
    routeOptionLines.value = const [];
    routeOptionLabels.value = const [];
  }

  // Draws the shown options again after a colour change.
  void _redrawLines() {
    final routes = _shownRoutes;
    if (routes == null) return;
    final selected = _shownSelected;
    final width = _routeColors.aheadWidth;
    final selectedColor = _routeColors.ahead;
    final selectedCasing = Color.lerp(
      selectedColor,
      const Color(0xFF000000),
      0.35,
    )!;
    final mutedCasing = Color.lerp(
      _alternativeColor,
      const Color(0xFFFFFFFF),
      0.5,
    )!;

    Polyline<Object> casingOf(int i, Color color) => Polyline<Object>(
      points: routes[i].points.map(toLatLng).toList(),
      color: color,
      strokeWidth: width + 4,
      hitValue: i,
    );
    Polyline<Object> lineOf(int i, Color color) => Polyline<Object>(
      points: routes[i].points.map(toLatLng).toList(),
      color: color,
      strokeWidth: width,
      hitValue: i,
    );

    final muted = [
      for (var i = 0; i < routes.length; i++)
        if (i != selected) i,
    ];
    routeOptionLines.value = [
      // Bottom to top, as the z-order of the Google adapter: all muted
      // casings, all muted lines, then the selected casing and line.
      for (final i in muted) casingOf(i, mutedCasing),
      for (final i in muted) lineOf(i, _alternativeColor),
      if (selected >= 0 && selected < routes.length) ...[
        casingOf(selected, selectedCasing),
        lineOf(selected, selectedColor),
      ],
    ];
  }

  void _redrawLabels(List<NavRoute> routes, int selected) {
    final label = routeLabel;
    if (label == null) {
      routeOptionLabels.value = const [];
      return;
    }
    final colors = _labelColors;
    routeOptionLabels.value = [
      // The selected label is last, so it is drawn on top.
      for (var i = 0; i < routes.length; i++)
        if (i != selected) _labelMarker(routes, i, label, false, colors),
      if (selected >= 0 && selected < routes.length)
        _labelMarker(routes, selected, label, true, colors),
    ];
  }

  Marker _labelMarker(
    List<NavRoute> routes,
    int index,
    String Function(NavRoute) label,
    bool selected,
    RouteLabelColors colors,
  ) {
    final route = routes[index];
    final text = label(route);
    return Marker(
      point: toLatLng(route.pointAt(route.length / 2)),
      width: _labelWidth(text),
      height: _labelHeight,
      // The box sits above the point: its bottom-centre is on the route.
      alignment: Alignment.topCenter,
      rotate: true,
      child: GestureDetector(
        onTap: () => onRouteOptionTap?.call(index),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RouteLabelBubble(
            text: text,
            selected: selected,
            colors: colors,
          ),
        ),
      ),
    );
  }

  static double _labelWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: _labelFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 2 * _labelPaddingX + _labelSlack;
  }

  @override
  Future<void> fitRoutes(List<NavRoute> routes, EdgeInsets padding) async {
    final points = [for (final r in routes) ...r.points];
    if (points.isEmpty) return;
    _pendingFit = _PendingFit(points, padding);
    _applyPendingFit();
  }

  void _applyPendingFit() {
    final size = _viewportSize;
    final pending = _pendingFit;
    if (!_ready || size == null || pending == null) return;
    _pendingFit = null;
    final target = fitCameraToBounds(
      pending.points,
      size,
      pending.padding,
      mapPadding: mapPadding,
    );
    controller.rotate(0);
    controller.move(
      toLatLng(target.position),
      target.zoom,
      // The target sits at the centre of the view minus the map padding.
      offset: Offset(
        (mapPadding.left - mapPadding.right) / 2,
        (mapPadding.top - mapPadding.bottom) / 2,
      ),
    );
  }

  void dispose() {
    route.dispose();
    vehicle.dispose();
    routeOptionLines.dispose();
    routeOptionLabels.dispose();
    _shownRoutes = null;
    _pendingFit = null;
    _ready = false;
    controller.dispose();
  }
}

/// A [FlutterMapNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}
