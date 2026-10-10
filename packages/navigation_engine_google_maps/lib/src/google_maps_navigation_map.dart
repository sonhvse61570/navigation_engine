import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

/// The Google Maps position of [p].
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

/// [NavigationMap], [VehicleMarkerMap], [RoutePreviewMap],
/// [AlternateRoutesMap], [SearchPinsMap] and [DestinationPinMap] on top of
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
/// ## Alternate routes
///
/// [showAlternates] fills [alternatePolylines] with one grey line per
/// alternate (id `navigation_engine_alternate_<i>`), in [alternateColor] and
/// 70 % as wide as the route, under the route (`zIndex` 0). A line is the
/// alternate's own part ([alternateLinePoints]): from 40 m before it leaves
/// the route to 40 m after it rejoins it, so a tap on the route where the
/// two share the road is a map tap, as on every adapter. With
/// [alternateLabel] set, [alternateMarkers] also gets a bubble on each one
/// (id `navigation_engine_alternate_label_<i>`), at the middle of the part
/// that differs (from the divergence to the rejoin, else the end) but at
/// most [alternateLabelLead] metres past the divergence
/// ([alternateLabelDistance]), so it is on its line and shows near the car
/// at follow zoom, in [fasterLabelColors] or
/// [slowerLabelColors]. A
/// tap on a line or a bubble calls the `onTap` given to [showAlternates],
/// unless it was drawn for another route than the alternate now at its
/// index (an older list the SDK still shows); the same holds for a tap on
/// a route option line or label.
/// Bubbles are rendered like the route option labels; a newer
/// [showAlternates] or [clearAlternates] drops renders still pending. Until
/// the new bubbles land the old ones stay, but a tap on one that labels
/// another route than the alternate now at its index is ignored. A failed
/// render removes the bubbles (the lines stay) and is reported through
/// [FlutterError]. Bubble and pin taps do not move the camera. New bubble
/// colours, or an [alternateLabel] that gives other texts, paint the shown
/// bubbles again.
///
/// ## Search pins
///
/// [showSearchPins] fills [searchMarkers] with one pin per place found along
/// the route (id `navigation_engine_search_<placeId>`), in [pinColor] and
/// painted by [pinPainter]; the focused one is larger and on top. A tap on
/// a pin calls the newest `onTap` with its place, only while a place with
/// its id is still shown (the SDK keeps old markers for a round trip). A
/// newer [showSearchPins] or [clearSearchPins] drops renders still pending; a
/// failed render clears the pins and is reported through [FlutterError]. A
/// new [pinColor] paints the shown pins again.
///
/// ## Destination pin
///
/// [showDestinationPin] sets [destinationMarker] (id
/// `navigation_engine_destination`): the shared red pin of
/// [paintDestinationPin] (or [destinationPinPainter]), anchored at its tip,
/// under the vehicle. A newer call drops a render still pending; a failed
/// render removes the pin and is reported through [FlutterError].
///
/// ## Taps on the map's own features
///
/// A tap on a feature the map draws (a route option or its bubble, an
/// alternate or its bubble, a search pin or the destination pin) drops the
/// one map tap of its gesture, should the platform report one too:
/// `GoogleMapsNavigationView.onMapTap` does not get a map tap that comes
/// in the same frame after such a tap, nor one that such a tap follows in
/// the same turn of the event loop. A map tap in a later frame is
/// delivered. `GoogleMapsNavigationView` also makes a tap on the vehicle
/// marker a map tap at the vehicle.
///
/// Wire [onMapCreated] to `GoogleMap.onMapCreated`; camera updates before
/// are dropped. Polylines and markers are widget properties in
/// google_maps_flutter, so the route line and the vehicle marker are
/// exposed as listenables for the view (or an app's own `GoogleMap`) to
/// build from.
class GoogleMapsNavigationMap
    implements
        NavigationMap,
        VehicleMarkerMap,
        RoutePreviewMap,
        AlternateRoutesMap,
        SearchPinsMap,
        DestinationPinMap {
  /// Creates the map's drawing state, with the route drawn in
  /// [routeColors].
  GoogleMapsNavigationMap({RouteColors routeColors = const RouteColors()})
    // A named parameter cannot be a private initializing formal.
    // ignore: prefer_initializing_formals
    : _routeColors = routeColors;

  /// How far past its divergence an alternate's bubble sits at most, in
  /// metres: the middle of a long alternate's own part is off screen at
  /// follow zoom.
  static const double alternateLabelLead = 400;

  // Drops the map tap of a gesture a feature the map draws took (see
  // [dispatchMapTap]).
  final _tapGuard = MapTapGuard();

  // A tap on a feature the map draws: it drops the map tap of its gesture,
  // held or to come.
  void _featureTapped() => _tapGuard.featureTapped();

  RouteColors _routeColors;
  List<GeoPoint> _driven = const [];
  List<GeoPoint> _ahead = const [];

  /// The route line colours and widths. Setting new ones rebuilds the drawn
  /// route polylines, route options and alternates with them.
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
    if (polylines.value.isNotEmpty) {
      polylines.value = routePolylines(_driven, _ahead, value);
    }
    _redrawRouteOptions();
    _redrawAlternates();
  }

  /// The route polylines: the driven part and the part ahead (ids
  /// `navigation_engine_driven` and `navigation_engine_ahead`); empty while
  /// no route is shown.
  final polylines = ValueNotifier<Set<Polyline>>(const {});

  /// The vehicle marker (id `navigation_engine_vehicle`) drawn while the
  /// camera does not follow the vehicle; null while it is hidden.
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
  /// `colors`). It defaults to [paintRouteLabel]; tests replace it to control
  /// when (and whether) a render finishes.
  Future<Uint8List> Function(
    String text, {
    required bool selected,
    required double pixelRatio,
    required RouteLabelColors colors,
  })?
  labelPainter;

  RouteLabelColors _labelColors = MapDefaultColors.routeLabels;

  /// The colours of the label bubbles (see [labelPainter]), by default
  /// [MapDefaultColors.routeLabels], as on every adapter. Changing them
  /// while options are shown renders the labels again; the old bubbles stay
  /// until the new ones are ready.
  RouteLabelColors get labelColors => _labelColors;
  set labelColors(RouteLabelColors value) {
    final old = _labelColors;
    if (value == old) {
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

  // Label images by (text, selected, pixel ratio, colours), least recently
  // used first. The futures are kept, so a render still running is shared
  // too.
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

  /// Connects the map's [controller]: camera moves and fits go to it from
  /// now on, and a fit asked for earlier is applied.
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
                _reportError(e, st, 'applying a pending route fit'),
          ),
    );
  }

  void _reportError(Object e, StackTrace st, String what) {
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
          onTap: () => _tapOption(i, routes[i]),
        ),
    };
  }

  // A tap on route option [index] (its line or its label), drawn for
  // [route]. A line or a label still shown from an older list (for one round trip to the SDK) may stand for
  // another route than the option now at [index]; its tap is ignored.
  void _tapOption(int index, NavRoute route) {
    _featureTapped();
    final shown = _shownRoutes;
    if (shown == null || index >= shown.length) return;
    if (!identical(shown[index], route)) return;
    onRouteOptionTap?.call(index);
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

  // Renders the bubbles [labels] builds (through the shared image cache) and
  // returns their markers, anchored at the bottom centre. A failed render
  // completes the future with its error, which the caller handles; [labels]
  // runs inside this future, so a label text that throws fails it too.
  Future<Set<Marker>> _labelMarkers(
    List<_Label> Function() labels, {
    bool consumeTapEvents = false,
  }) async {
    final ratio = labelPixelRatio;
    final shown = labels();
    final images = await Future.wait([
      for (final l in shown) _labelImage(l.text, l.selected, ratio, l.colors),
    ]);
    return {
      for (var i = 0; i < shown.length; i++)
        Marker(
          markerId: MarkerId(shown[i].id),
          position: toLatLng(shown[i].position),
          anchor: const Offset(0.5, 1),
          icon: BitmapDescriptor.bytes(images[i], imagePixelRatio: ratio),
          zIndexInt: shown[i].zIndex,
          consumeTapEvents: consumeTapEvents,
          onTap: shown[i].onTap,
        ),
    };
  }

  Future<void> _showLabels(
    List<NavRoute> routes,
    int selected,
    int generation,
  ) async {
    final label = routeLabel!;
    final colors = _labelColors;
    final Set<Marker> markers;
    try {
      markers = await _labelMarkers(
        () => [
          for (var i = 0; i < routes.length; i++)
            _Label(
              id: 'navigation_engine_option_label_$i',
              text: label(routes[i]),
              selected: i == selected,
              colors: colors,
              position: routes[i].pointAt(routes[i].length / 2),
              zIndex: i == selected ? 7 : 5,
              onTap: () => _tapOption(i, routes[i]),
            ),
        ],
      );
    } on Object {
      // No labels for this generation; the polylines are still shown.
      return;
    }
    if (generation != _labelGeneration) return;
    routeOptionMarkers.value = markers;
  }

  @override
  void clearRouteOptions() {
    _labelGeneration++;
    _shownRoutes = null;
    _pendingFit = null;
    routeOptionPolylines.value = const {};
    routeOptionMarkers.value = const {};
  }

  /// The alternate routes drawn by [showAlternates]: grey lines, 70 % as wide
  /// as the route, under it (`zIndex` 0).
  final alternatePolylines = ValueNotifier<Set<Polyline>>(const {});

  /// The alternate routes' bubbles (empty until rendered).
  final alternateMarkers = ValueNotifier<Set<Marker>>(const {});

  /// The search result pins drawn by [showSearchPins].
  final searchMarkers = ValueNotifier<Set<Marker>>(const {});

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
      _alternateGeneration++;
      _alternateTexts = null;
      alternateMarkers.value = const {};
      return;
    }
    if (listEquals([for (final a in shown) value(a)], _alternateTexts)) return;
    unawaited(_showAlternateLabels(shown, ++_alternateGeneration));
  }

  /// The texts of the bubbles last asked for; null when none.
  List<String>? _alternateTexts;

  Color _alternateColor = MapDefaultColors.alternate;

  /// The colour of the alternate lines (by default
  /// [MapDefaultColors.alternate]); a change redraws them.
  Color get alternateColor => _alternateColor;
  set alternateColor(Color value) {
    if (value == _alternateColor) return;
    _alternateColor = value;
    _redrawAlternates();
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
    if (shown != null && alternateLabel != null) {
      unawaited(_showAlternateLabels(shown, ++_alternateGeneration));
    }
  }

  Color _pinColor = MapDefaultColors.searchPin;

  /// The colour of the search pins (by default [MapDefaultColors.searchPin],
  /// as on every adapter); a change paints the pins shown again (same
  /// places, focus and taps).
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

  /// Renders a search pin as PNG bytes. It defaults to [paintSearchPin];
  /// tests replace it.
  Future<Uint8List> Function({
    required bool focused,
    required double pixelRatio,
    required Color color,
  })?
  pinPainter;

  // What showAlternates was last given; null when no alternates are shown.
  List<AlternateRoute>? _shownAlternates;
  void Function(int index)? _alternateTap;

  // Bumped by every showAlternates / clearAlternates (and bubble colour
  // change); a bubble render started under an older value is dropped.
  int _alternateGeneration = 0;

  // Bumped by every showSearchPins / clearSearchPins; a pin render started
  // under an older value is dropped.
  int _pinGeneration = 0;

  @override
  void showAlternates(
    List<AlternateRoute> alternates, {
    required void Function(int index) onTap,
  }) {
    final generation = ++_alternateGeneration;
    _shownAlternates = alternates;
    _alternateTap = onTap;
    alternatePolylines.value = _buildAlternatePolylines(alternates);
    if (alternateLabel == null) {
      _alternateTexts = null;
      alternateMarkers.value = const {};
      return;
    }
    unawaited(_showAlternateLabels(alternates, generation));
  }

  Set<Polyline> _buildAlternatePolylines(List<AlternateRoute> alternates) {
    final width = math.max(1, (_routeColors.aheadWidth * 0.7).round());
    return {
      for (var i = 0; i < alternates.length; i++)
        Polyline(
          polylineId: PolylineId('navigation_engine_alternate_$i'),
          // Only its own part: a tap where it shares the route is a map tap.
          points: alternateLinePoints(alternates[i]).map(toLatLng).toList(),
          color: _alternateColor,
          width: width,
          zIndex: 0,
          consumeTapEvents: true,
          onTap: () => _tapAlternate(i, alternates[i].route),
        ),
    };
  }

  // Draws the shown alternates again after a colour or width change. The
  // bubbles, and the renders still pending, are left alone.
  void _redrawAlternates() {
    final shown = _shownAlternates;
    if (shown == null) return;
    alternatePolylines.value = _buildAlternatePolylines(shown);
  }

  Future<void> _showAlternateLabels(
    List<AlternateRoute> alternates,
    int generation,
  ) async {
    final label = alternateLabel!;
    final faster = _fasterLabelColors;
    final slower = _slowerLabelColors;
    _alternateTexts = [for (final a in alternates) label(a)];
    final Set<Marker> markers;
    try {
      markers = await _labelMarkers(
        consumeTapEvents: true,
        () => [
          for (var i = 0; i < alternates.length; i++)
            _Label(
              id: 'navigation_engine_alternate_label_$i',
              text: label(alternates[i]),
              selected: false,
              colors: alternates[i].minutesDelta < 0 ? faster : slower,
              position: alternates[i].route.pointAt(
                alternateLabelDistance(alternates[i], lead: alternateLabelLead),
              ),
              zIndex: 4,
              onTap: () => _tapAlternate(i, alternates[i].route),
            ),
        ],
      );
    } on Object catch (e, st) {
      // The lines stay; only the bubbles go, and only when this render is
      // still the latest.
      if (generation != _alternateGeneration) return;
      alternateMarkers.value = const {};
      _reportError(e, st, 'rendering alternate route bubbles');
      return;
    }
    if (generation != _alternateGeneration) return;
    alternateMarkers.value = markers;
  }

  // A tap on line or bubble [index], drawn for [route]. A line still shown
  // from an older list (for one round trip to the SDK), or a bubble (while
  // the new bubbles render), may stand for another route than the
  // alternate now at [index]; its tap is ignored.
  void _tapAlternate(int index, NavRoute route) {
    _featureTapped();
    final shown = _shownAlternates;
    if (shown == null || index >= shown.length) return;
    if (!identical(shown[index].route, route)) return;
    _alternateTap?.call(index);
  }

  @override
  void clearAlternates() {
    _alternateGeneration++;
    _shownAlternates = null;
    _alternateTexts = null;
    alternatePolylines.value = const {};
    alternateMarkers.value = const {};
  }

  /// Pins [places] on the map, the one with [focusedId] larger and on top;
  /// a tap on a pin calls [onTap] (and does not move the camera). Pins are
  /// rendered asynchronously; a newer call or [clearSearchPins] drops a
  /// render still pending. When the render fails, the pins are cleared and
  /// the error is reported through [FlutterError].
  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) async {
    final generation = ++_pinGeneration;
    if (places.isEmpty) {
      _shownPins = null;
      searchMarkers.value = const {};
      return;
    }
    _shownPins = (places: places, focusedId: focusedId, onTap: onTap);
    final ratio = labelPixelRatio;
    final paint = pinPainter ?? paintSearchPin;
    final List<Uint8List> images;
    try {
      images = await Future.wait([
        paint(focused: false, pixelRatio: ratio, color: pinColor),
        paint(focused: true, pixelRatio: ratio, color: pinColor),
      ]);
    } on Object catch (e, st) {
      // The pins of an older search must not stand for this one.
      if (generation != _pinGeneration) return;
      _shownPins = null;
      searchMarkers.value = const {};
      _reportError(e, st, 'rendering search pins');
      return;
    }
    if (generation != _pinGeneration) return;
    searchMarkers.value = {
      for (final place in places)
        Marker(
          markerId: MarkerId('navigation_engine_search_${place.id}'),
          position: toLatLng(place.position),
          anchor: const Offset(0.5, 1),
          icon: BitmapDescriptor.bytes(
            place.id == focusedId ? images[1] : images[0],
            imagePixelRatio: ratio,
          ),
          zIndexInt: place.id == focusedId ? 9 : 8,
          consumeTapEvents: true,
          onTap: () => _tapPin(place.id),
        ),
    };
  }

  // A tap on the pin drawn for the place [id]: the place with that id still
  // shown, with the newest onTap. A pin the SDK still shows from an older
  // list (or after a clear) for one round trip reports nothing else.
  void _tapPin(String id) {
    _featureTapped();
    final shown = _shownPins;
    if (shown == null) return;
    for (final place in shown.places) {
      if (place.id == id) {
        shown.onTap?.call(place);
        return;
      }
    }
  }

  /// Removes the search pins, also those still being rendered.
  @override
  void clearSearchPins() {
    _pinGeneration++;
    _shownPins = null;
    searchMarkers.value = const {};
  }

  /// The destination pin drawn by [showDestinationPin]; null while none is
  /// shown (also until its image is rendered).
  final destinationMarker = ValueNotifier<Marker?>(null);

  /// Renders the destination pin as PNG bytes. It defaults to
  /// [paintDestinationPin]; tests replace it.
  Future<Uint8List> Function({required double pixelRatio})?
  destinationPinPainter;

  // Bumped by every showDestinationPin; a render started under an older
  // value is dropped.
  int _destinationGeneration = 0;

  // The destination pin image and the pixel ratio it was rendered at.
  ({double ratio, Future<Uint8List> png})? _destinationImage;

  /// Pins the trip's destination at [point] (the shared red pin, anchored
  /// at its tip), replacing the one shown; null removes it. The pin is
  /// rendered asynchronously at [labelPixelRatio], once per ratio; a newer
  /// call drops a render still pending. When the render fails, the pin is
  /// removed and the error is reported through [FlutterError]. A tap on the
  /// pin does nothing (and does not move the camera).
  @override
  void showDestinationPin(GeoPoint? point) {
    final generation = ++_destinationGeneration;
    if (point == null) {
      destinationMarker.value = null;
      return;
    }
    unawaited(_showDestination(point, generation));
  }

  Future<void> _showDestination(GeoPoint point, int generation) async {
    final ratio = labelPixelRatio;
    final Uint8List png;
    try {
      png = await _destinationPng(ratio);
    } on Object catch (e, st) {
      if (generation != _destinationGeneration) return;
      destinationMarker.value = null;
      _reportError(e, st, 'rendering the destination pin');
      return;
    }
    if (generation != _destinationGeneration) return;
    destinationMarker.value = Marker(
      markerId: const MarkerId('navigation_engine_destination'),
      position: toLatLng(point),
      anchor: const Offset(0.5, 1),
      icon: BitmapDescriptor.bytes(png, imagePixelRatio: ratio),
      zIndexInt: 6,
      consumeTapEvents: true,
      onTap: _featureTapped,
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
              _reportError(e, st, 'fitting route options'),
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

  /// Releases the notifiers and drops pending renders and fits. The map
  /// must not be used afterwards.
  void dispose() {
    _tapGuard.dispose();
    polylines.dispose();
    vehicleMarker.dispose();
    routeOptionPolylines.dispose();
    routeOptionMarkers.dispose();
    alternatePolylines.dispose();
    alternateMarkers.dispose();
    searchMarkers.dispose();
    destinationMarker.dispose();
    _destinationGeneration++;
    _destinationImage = null;
    _alternateGeneration++;
    _pinGeneration++;
    _shownAlternates = null;
    _alternateTexts = null;
    _shownPins = null;
    _labelGeneration++;
    _shownRoutes = null;
    _labelImages.clear();
    _pendingFit = null;
    _controller = null;
  }

  /// Whether a map controller is connected ([onMapCreated]).
  @visibleForTesting
  bool get hasController => _controller != null;
}

/// Delivers a tap on [map] itself through [deliver], unless it belongs to
/// a tap on a feature the map draws (a route option or its bubble, an
/// alternate or its bubble, a search pin or the destination pin): one that
/// came before it in the same frame, or one that comes in the same turn of
/// the event loop. [deliver] runs after that turn, and not at all once the
/// map is disposed. The view calls it from `GoogleMap.onTap`; the library
/// does not export it.
void dispatchMapTap(GoogleMapsNavigationMap map, VoidCallback deliver) =>
    map._tapGuard.dispatch(deliver);

/// The key of a cached label image.
typedef _LabelKey = (String, bool, double, RouteLabelColors);

/// A bubble to render as a marker: a route option label or an alternate
/// route's bubble.
class _Label {
  const _Label({
    required this.id,
    required this.text,
    required this.selected,
    required this.colors,
    required this.position,
    required this.zIndex,
    required this.onTap,
  });

  final String id;
  final String text;
  final bool selected;
  final RouteLabelColors colors;
  final GeoPoint position;
  final int zIndex;
  final VoidCallback onTap;
}

/// A [GoogleMapsNavigationMap.fitRoutes] waiting for the map to be ready.
class _PendingFit {
  const _PendingFit(this.points, this.padding);
  final List<GeoPoint> points;
  final EdgeInsets padding;
}

/// PNG bytes → marker icon at the given pixel ratio.
BitmapDescriptor vehicleIconFrom(Uint8List png, {double pixelRatio = 3}) =>
    BitmapDescriptor.bytes(png, imagePixelRatio: pixelRatio);
