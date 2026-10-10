import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

/// Delivers a tap on [map] itself through [deliver] unless a feature the
/// adapter draws took the gesture (see [MapTapGuard.dispatch]). Not part of
/// the public API (hidden by the library export): the view calls it.
void dispatchMapTap(FlutterMapNavigationMap map, VoidCallback deliver) =>
    map._tapGuard.dispatch(deliver);

/// A tap on a route option line of [map], whose layer reported [hit] (the
/// route index), from the view. Not part of the public API.
void tapRouteOptionLine(FlutterMapNavigationMap map, Object? hit) {
  map._tapGuard.featureTapped();
  if (hit is int) map.onRouteOptionTap?.call(hit);
}

/// A tap on an alternate line of [map], whose layer reported [hit], from
/// the view. Not part of the public API.
void tapAlternateLine(FlutterMapNavigationMap map, Object? hit) {
  map._tapGuard.featureTapped();
  if (hit is _AlternateHit) map._tapAlternate(hit.index, hit.route);
}

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
/// a [RouteLabelBubble] marker at the middle of each route, with
/// `rotate: true` so it stays upright when the map rotates. Labels are
/// widgets, so they are rebuilt synchronously.
///
/// [fitRoutes] needs the map to be ready ([onMapReady]) and [viewportSize];
/// called earlier, it is kept and applied once both exist. Fits account for
/// [mapPadding].
///
/// ## Alternate routes
///
/// [showAlternates] fills [alternateLines] with one line per alternate, in
/// [alternateColor] and 70 % as wide as the route, each with `hitValue`
/// set; the view draws them under the session's route and the route
/// options. A line is the alternate's own part ([alternateLinePoints]):
/// from 40 m before it leaves the route to 40 m after it rejoins it, so a
/// tap on the route where the two share the road is a map tap, as on every
/// adapter. With [alternateLabel] set, [alternateLabels] gets a
/// [RouteLabelBubble] per alternate (in [fasterLabelColors] or
/// [slowerLabelColors]) at the middle of the part that differs (from its
/// divergence to its rejoin, else its end), but at most
/// [alternateLabelLead] metres past the divergence
/// ([alternateLabelDistance]), so always on its line. A tap on a line or a bubble
/// calls the `onTap` given to [showAlternates]. A tap on a line or a bubble
/// drawn for an older list (the user pressed it before a newer
/// [showAlternates]) is ignored. A press on a marker this map draws (a
/// bubble, a label, a pin) is never a map tap, also when a newer list moves
/// or removes it during the press; see "Presses on markers". Where the
/// session's route covers an alternate (the 40 m it reaches onto the
/// shared stretches), the route takes the tap, which is a map tap.
///
/// ## Search pins and the destination pin
///
/// [showSearchPins] fills [searchPins] with one marker per place (the
/// images of [pinPainter], by default [paintSearchPin], in [pinColor]), the
/// focused one larger and last (on top); a tap on one calls `onTap` with
/// its place. [showDestinationPin] sets [destinationPin] to the shared red
/// pin of [paintDestinationPin]. The images are rendered at [pixelRatio],
/// asynchronously: a newer call drops a render still pending, and a failed
/// render removes the pins (or the destination pin) and is reported through
/// [FlutterError]. Each pin is anchored at its tip and stays upright when
/// the map rotates. The view draws them above the route and its labels,
/// below the app's layers and the vehicle, the destination under the
/// search pins.
///
/// ## Presses on markers
///
/// A press on a marker this map draws ends as a tap on what was pressed, or
/// as nothing; never as a tap on another marker, and never as a map tap,
/// even when a newer list moves or removes the marker during the press, or
/// the view goes. What it reports, when the press ends:
/// - a route option label: [onRouteOptionTap] with its index, only while
///   the route it was drawn for is still the option at that index (not
///   after [clearRouteOptions], a new list that moves it, or [dispose]);
/// - an alternate bubble: the `onTap` of [showAlternates] with its index,
///   only while the route it was drawn for is still the alternate at that
///   index;
/// - a search pin: the newest `onTap` of [showSearchPins] with its place,
///   only while a pin with that place's id is still shown;
/// - the destination pin: nothing.
///
/// ## Feature taps and map taps
///
/// A tap on a feature this map draws (a route option or its label, an
/// alternate or its bubble, a search pin or the destination pin) is no map
/// tap: flutter_map's gesture arena gives the tap to the feature's layer.
/// Each such tap also calls [MapTapGuard.featureTapped], and the view sends
/// map taps through the guard, as the other adapters of this family do;
/// flutter_map never reports a map tap in the frame or turn of a feature
/// tap, so the guard is kept for parity and changes nothing here.
class FlutterMapNavigationMap
    implements
        NavigationMap,
        VehicleMarkerMap,
        RoutePreviewMap,
        AlternateRoutesMap,
        SearchPinsMap,
        DestinationPinMap {
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
  /// When null, [showRouteOptions] adds no labels. Changing it while options
  /// are shown rebuilds the labels.
  String Function(NavRoute route)? get routeLabel => _routeLabel;
  set routeLabel(String Function(NavRoute route)? value) {
    if (value == _routeLabel) return;
    _routeLabel = value;
    final routes = _shownRoutes;
    if (routes != null) _redrawLabels(routes, _shownSelected);
  }

  String Function(NavRoute route)? _routeLabel;

  /// Called with the route index when a route option, or its label, is
  /// tapped. A press on a label reports its index only while the route it
  /// was drawn for is still the option at that index when the press ends.
  void Function(int index)? onRouteOptionTap;

  /// How far below the map centre the followed point sits, in logical
  /// pixels (set by the view from its focus padding).
  double focusOffset = 0;

  /// How far right of the map centre the followed point sits, in logical
  /// pixels (set by the view from its focus padding; negative: left of it).
  double horizontalFocusOffset = 0;

  /// The device pixel ratio the pin images are rendered at (set by the
  /// view). A change applies to the pins shown next.
  double pixelRatio = 1;

  // Keeps the map tap of a gesture that a feature of this map took away
  // from the app (see [dispatchMapTap]).
  final _tapGuard = MapTapGuard();

  /// The padding of the map area that the camera target is centred in (the
  /// view sets it from its focus padding); [fitRoutes] and a pending fit
  /// account for it (see [fitCameraToBounds]). Setting it moves nothing: the
  /// next fit uses it.
  EdgeInsets mapPadding = EdgeInsets.zero;

  RouteColors _routeColors = const RouteColors();
  Color _alternativeColor = const Color(0xFF9AA0A6);
  RouteLabelColors _labelColors = MapDefaultColors.routeLabels;

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
    _redrawAlternateLines();
  }

  /// The colour of the route options that are not selected. Changing it
  /// while options are shown redraws their lines.
  Color get alternativeColor => _alternativeColor;
  set alternativeColor(Color value) {
    if (value == _alternativeColor) return;
    _alternativeColor = value;
    _redrawLines();
  }

  /// The colours of the label bubbles (by default
  /// [MapDefaultColors.routeLabels], as on every adapter). Changing them
  /// while options are shown
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
      offset: Offset(horizontalFocusOffset, focusOffset),
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

    // Each route's points are mapped once; its casing and line share them.
    final points = [
      for (final route in routes) route.points.map(toLatLng).toList(),
    ];
    Polyline<Object> casingOf(int i, Color color) => Polyline<Object>(
      points: points[i],
      color: color,
      strokeWidth: width + 4,
      hitValue: i,
    );
    Polyline<Object> lineOf(int i, Color color) => Polyline<Object>(
      points: points[i],
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
    return _bubbleMarker(
      point: route.pointAt(route.length / 2),
      text: label(route),
      selected: selected,
      colors: colors,
      onTap: () {
        _tapGuard.featureTapped();
        _tapRouteOption(index, route);
      },
    );
  }

  // A tap on the label of option [index], drawn for [route]. A press lasts
  // across a newer showRouteOptions, clearRouteOptions or dispose: it is
  // reported only while [route] is still the option at [index].
  void _tapRouteOption(int index, NavRoute route) {
    final shown = _shownRoutes;
    if (shown == null || index >= shown.length) return;
    if (!identical(shown[index], route)) return;
    onRouteOptionTap?.call(index);
  }

  // A label bubble at [point] (a route option's or an alternate's).
  Marker _bubbleMarker({
    required GeoPoint point,
    required String text,
    required bool selected,
    required RouteLabelColors colors,
    required VoidCallback onTap,
  }) {
    return Marker(
      point: toLatLng(point),
      width: _labelWidth(text),
      height: _labelHeight,
      // The box sits above the point: its bottom-centre is on the route.
      alignment: Alignment.topCenter,
      // flutter_map turns the marker against the map's rotation, so the
      // bubble stays upright on the screen, its anchor on the route.
      rotate: true,
      child: _PressTarget(
        onTap: onTap,
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

  // ---- Alternate routes ----

  /// How far past its divergence an alternate's bubble sits at most, in
  /// metres: the middle of a long alternate's own part is off screen at
  /// driving zooms.
  static const double alternateLabelLead = 400;

  /// The alternate lines drawn by [showAlternates], one per alternate, each
  /// with `hitValue` set (an opaque value the view hands back on a tap).
  final alternateLines = ValueNotifier<List<Polyline<Object>>>(const []);

  /// The alternates' bubble markers (empty without [alternateLabel]).
  final alternateLabels = ValueNotifier<List<Marker>>(const []);

  // What showAlternates was last given; null when no alternates are shown.
  List<AlternateRoute>? _shownAlternates;
  void Function(int index)? _alternateTap;

  String Function(AlternateRoute alternate)? _alternateLabel;

  // The texts of the bubbles shown; null when none.
  List<String>? _alternateTexts;

  /// The text of the bubble on each alternate, such as "2 min faster"; when
  /// null, [showAlternates] draws no bubbles. Setting it while alternates
  /// are shown rebuilds their bubbles when the texts change (such as a new
  /// language, also through the same function), and removes them when
  /// null.
  String Function(AlternateRoute alternate)? get alternateLabel =>
      _alternateLabel;
  set alternateLabel(String Function(AlternateRoute alternate)? value) {
    _alternateLabel = value;
    final shown = _shownAlternates;
    if (shown == null) return;
    if (value != null &&
        listEquals([for (final a in shown) value(a)], _alternateTexts)) {
      return;
    }
    _redrawAlternateLabels();
  }

  Color _alternateColor = MapDefaultColors.alternate;

  /// The colour of the alternate lines (by default
  /// [MapDefaultColors.alternate]); a change redraws them.
  Color get alternateColor => _alternateColor;
  set alternateColor(Color value) {
    if (value == _alternateColor) return;
    _alternateColor = value;
    _redrawAlternateLines();
  }

  RouteLabelColors _fasterLabelColors = MapDefaultColors.fasterLabels;
  RouteLabelColors _slowerLabelColors = MapDefaultColors.slowerLabels;

  /// The bubble colours of a faster alternate (by default
  /// [MapDefaultColors.fasterLabels], as on every adapter).
  RouteLabelColors get fasterLabelColors => _fasterLabelColors;

  /// The bubble colours of a slower (or as fast) alternate (by default
  /// [MapDefaultColors.slowerLabels]).
  RouteLabelColors get slowerLabelColors => _slowerLabelColors;

  /// Sets the bubble colours; bubbles shown are rebuilt.
  void setAlternateLabelColors({
    required RouteLabelColors faster,
    required RouteLabelColors slower,
  }) {
    if (faster == _fasterLabelColors && slower == _slowerLabelColors) return;
    _fasterLabelColors = faster;
    _slowerLabelColors = slower;
    _redrawAlternateLabels();
  }

  @override
  void showAlternates(
    List<AlternateRoute> alternates, {
    required void Function(int index) onTap,
  }) {
    _shownAlternates = alternates;
    _alternateTap = onTap;
    _redrawAlternateLines();
    _redrawAlternateLabels();
  }

  @override
  void clearAlternates() {
    _shownAlternates = null;
    _alternateTap = null;
    _alternateTexts = null;
    alternateLines.value = const [];
    alternateLabels.value = const [];
  }

  void _redrawAlternateLines() {
    final shown = _shownAlternates;
    if (shown == null) return;
    final width = math.max(1.0, _routeColors.aheadWidth * 0.7);
    alternateLines.value = [
      for (var i = 0; i < shown.length; i++)
        Polyline<Object>(
          // Only its own part: a tap where it shares the route is a map
          // tap, also where the session's route is not drawn over it.
          points: alternateLinePoints(shown[i]).map(toLatLng).toList(),
          color: _alternateColor,
          strokeWidth: width,
          hitValue: _AlternateHit(i, shown[i].route),
        ),
    ];
  }

  void _redrawAlternateLabels() {
    final shown = _shownAlternates;
    if (shown == null) return;
    final label = _alternateLabel;
    if (label == null) {
      _alternateTexts = null;
      alternateLabels.value = const [];
      return;
    }
    final texts = [for (final a in shown) label(a)];
    _alternateTexts = texts;
    alternateLabels.value = [
      for (var i = 0; i < shown.length; i++)
        _bubbleMarker(
          point: shown[i].route.pointAt(
            alternateLabelDistance(shown[i], lead: alternateLabelLead),
          ),
          text: texts[i],
          selected: false,
          colors: shown[i].minutesDelta < 0
              ? _fasterLabelColors
              : _slowerLabelColors,
          onTap: () {
            _tapGuard.featureTapped();
            _tapAlternate(i, shown[i].route);
          },
        ),
    ];
  }

  // A tap on alternate [index] as drawn for [route]. A line or a bubble
  // drawn for an older list may stand for another route than the alternate
  // now at [index]; its tap is ignored.
  void _tapAlternate(int index, NavRoute route) {
    final shown = _shownAlternates;
    if (shown == null || index >= shown.length) return;
    if (!identical(shown[index].route, route)) return;
    _alternateTap?.call(index);
  }

  // ---- Search pins ----

  /// The search pins drawn by [showSearchPins], the focused one last.
  final searchPins = ValueNotifier<List<Marker>>(const []);

  /// Renders a search pin as PNG bytes. It defaults to [paintSearchPin];
  /// tests replace it.
  Future<Uint8List> Function({
    required bool focused,
    required double pixelRatio,
    required Color color,
  })?
  pinPainter;

  Color _pinColor = MapDefaultColors.searchPin;

  /// The colour of the search pins (by default [MapDefaultColors.searchPin],
  /// as on every adapter); a change paints the pins shown again (same places, focus and
  /// taps).
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

  // What showSearchPins was last given; null when no pins are shown.
  ({
    List<AlongRoutePlace> places,
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  })?
  _shownPins;

  // Bumped by every showSearchPins / clearSearchPins (and dispose); a
  // render started under an older value is dropped.
  int _pinGeneration = 0;

  /// Pins [places] on the map, the one with [focusedId] 1.3 times larger
  /// and on top; a tap on a pin calls [onTap] with its place (and is no map
  /// tap, with or without [onTap]). A press on a pin counts for the place
  /// pressed, also when a newer call moves its pin in the list (such as a
  /// focus change); if a newer call removed that place, the press reports
  /// nothing. The pins are rendered asynchronously; a
  /// newer call or [clearSearchPins] drops a render still pending. When the
  /// render fails, the pins are cleared and the error is reported through
  /// [FlutterError].
  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) async {
    final generation = ++_pinGeneration;
    if (places.isEmpty) {
      _shownPins = null;
      searchPins.value = const [];
      return;
    }
    _shownPins = (places: places, focusedId: focusedId, onTap: onTap);
    final ratio = pixelRatio;
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
      searchPins.value = const [];
      _reportError(e, st, 'rendering search pins');
      return;
    }
    if (generation != _pinGeneration) return;
    Marker pin(AlongRoutePlace place, bool focused) => _pinMarker(
      point: place.position,
      png: focused ? images[1] : images[0],
      ratio: ratio,
      width: focused ? _pinWidth * _focusedScale : _pinWidth,
      height: focused ? _pinHeight * _focusedScale : _pinHeight,
      onTap: () {
        _tapGuard.featureTapped();
        _tapPin(place);
      },
    );
    searchPins.value = [
      for (final place in places)
        if (place.id != focusedId) pin(place, false),
      for (final place in places)
        if (place.id == focusedId) pin(place, true),
    ];
  }

  // A tap on the pin of [place], as pressed. The pins shown now may be
  // another list (a press lasts across a newer showSearchPins): the place
  // is reported, with the newest onTap, only while a pin with its id is
  // still shown.
  void _tapPin(AlongRoutePlace place) {
    final shown = _shownPins;
    if (shown == null) return;
    for (final p in shown.places) {
      if (p.id == place.id) {
        shown.onTap?.call(p);
        return;
      }
    }
  }

  /// Removes the search pins, also those still being rendered.
  @override
  void clearSearchPins() {
    _pinGeneration++;
    _shownPins = null;
    searchPins.value = const [];
  }

  // ---- Destination pin ----

  /// The destination pin drawn by [showDestinationPin]; null while none is
  /// shown (also until its image is rendered).
  final destinationPin = ValueNotifier<Marker?>(null);

  /// Renders the destination pin as PNG bytes. It defaults to
  /// [paintDestinationPin]; tests replace it.
  Future<Uint8List> Function({required double pixelRatio})?
  destinationPinPainter;

  // Bumped by every showDestinationPin (and dispose); a render started
  // under an older value is dropped.
  int _destinationGeneration = 0;

  // The destination pin image and the pixel ratio it was rendered at.
  ({double ratio, Future<Uint8List> png})? _destinationImage;

  /// Pins the trip's destination at [point] (the shared red pin, anchored
  /// at its tip), replacing the one shown; null removes it. The pin is
  /// rendered asynchronously at [pixelRatio], once per ratio; a newer call
  /// drops a render still pending. When the render fails, the pin is
  /// removed and the error is reported through [FlutterError]. A tap on the
  /// pin does nothing (and is no map tap); it reports no place, so a press
  /// on the pin while it moves cannot report a wrong one.
  @override
  void showDestinationPin(GeoPoint? point) {
    final generation = ++_destinationGeneration;
    if (point == null) {
      destinationPin.value = null;
      return;
    }
    unawaited(_showDestination(point, generation));
  }

  Future<void> _showDestination(GeoPoint point, int generation) async {
    final ratio = pixelRatio;
    final Uint8List png;
    try {
      png = await _destinationPng(ratio);
    } on Object catch (e, st) {
      if (generation != _destinationGeneration) return;
      destinationPin.value = null;
      _reportError(e, st, 'rendering the destination pin');
      return;
    }
    if (generation != _destinationGeneration) return;
    destinationPin.value = _pinMarker(
      point: point,
      png: png,
      ratio: ratio,
      width: _destinationWidth,
      height: _destinationHeight,
      onTap: _tapGuard.featureTapped,
    );
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

  // The logical sizes of the painted pins (see paintSearchPin and
  // paintDestinationPin).
  static const _pinWidth = 28.0;
  static const _pinHeight = 36.0;
  static const _focusedScale = 1.3;
  static const _destinationWidth = 32.0;
  static const _destinationHeight = 42.0;

  // A pin image at [point], its tip on the point, upright on the screen; a
  // tap on it calls [onTap].
  static Marker _pinMarker({
    required GeoPoint point,
    required Uint8List png,
    required double ratio,
    required double width,
    required double height,
    required VoidCallback onTap,
  }) => Marker(
    point: toLatLng(point),
    width: width,
    height: height,
    // The image sits above the point: its bottom-centre (the tip) is on it.
    alignment: Alignment.topCenter,
    rotate: true,
    child: _PressTarget(
      onTap: onTap,
      child: Image.memory(
        png,
        scale: ratio,
        width: width,
        height: height,
        gaplessPlayback: true,
      ),
    ),
  );

  void _reportError(Object e, StackTrace st, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'navigation_engine_flutter_map',
        context: ErrorDescription('while $what'),
      ),
    );
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

  /// Releases the notifiers and the controller, and drops pending renders,
  /// fits and held map taps. The map must not be used afterwards.
  void dispose() {
    _tapGuard.dispose();
    route.dispose();
    vehicle.dispose();
    routeOptionLines.dispose();
    routeOptionLabels.dispose();
    alternateLines.dispose();
    alternateLabels.dispose();
    searchPins.dispose();
    destinationPin.dispose();
    _shownAlternates = null;
    _alternateTap = null;
    _alternateTexts = null;
    _pinGeneration++;
    _shownPins = null;
    _destinationGeneration++;
    _destinationImage = null;
    _shownRoutes = null;
    _pendingFit = null;
    _ready = false;
    controller.dispose();
  }
}

/// A marker's tap target. Each press gets its own tap recognizer, made
/// when the pointer goes down with the tap callback of the marker pressed,
/// and not owned by this widget. `MarkerLayer` lays markers out by list
/// position, so a newer list during a press may hand this element another
/// marker (another place, route or index), or drop it: the press keeps the
/// callback of what was pressed, which reports it only if it still stands
/// (see "Presses on markers" on [FlutterMapNavigationMap]), and, since the
/// recognizer outlives the element, it is never a map tap. A long press or
/// a pan still goes to the map.
class _PressTarget extends StatelessWidget {
  const _PressTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  void _press(PointerDownEvent event) {
    final onTap = this.onTap;
    late final TapGestureRecognizer recognizer;
    // Disposed, out of its own callback, once a tap is reported or a press
    // is cancelled after its tap down. A press rejected before its tap
    // down (a quick drag) only stops tracking its pointer, and is then
    // garbage.
    void done() => scheduleMicrotask(recognizer.dispose);
    recognizer = TapGestureRecognizer(debugOwner: this)
      ..onTap = () {
        done();
        onTap();
      }
      ..onTapCancel = done
      ..addPointer(event);
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: _press, child: child);
}

/// What an alternate line reports when tapped: its index and the route it
/// was drawn for.
@immutable
class _AlternateHit {
  const _AlternateHit(this.index, this.route);
  final int index;
  final NavRoute route;
}

/// A [FlutterMapNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}
