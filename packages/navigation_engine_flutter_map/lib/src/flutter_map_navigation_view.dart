import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'flutter_map_navigation_map.dart';

/// A ready-made navigation map on flutter_map: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter. Its
/// map is a [RoutePreviewMap], an [AlternateRoutesMap], a [SearchPinsMap]
/// and a [DestinationPinMap] too: a [NavigationFlowController] on
/// [session] draws its route options (see [routeLabel],
/// [onRouteOptionTap]) and alternates (see [alternateLabel]) here, and a
/// navigation scaffold its pins.
///
/// Attaches itself as [NavigationSession.map] while mounted. The app owns
/// the session (create, start, dispose).
///
/// ## The layers
///
/// Bottom to top: the tiles, the alternates, the route options, the
/// session's route, the alternates' bubbles, the route options' labels, the
/// destination pin, the search pins, the app's [children], the vehicle and
/// the attribution.
///
/// ## Under a Google-style scaffold
///
/// A `GoogleStyleFlowScaffold`'s `mapBuilder` can build this view from its
/// `GoogleStyleMapLayers`: [horizontalFocus] from `horizontalFocus`,
/// [bottomInset] from `bottomOverlay`, [routeColors], [routeLabel] and
/// [alternateLabel] from the fields of the same names, and the colours
/// ([labelColors], [alternativeRouteColor], [alternateColor],
/// [fasterLabelColors], [slowerLabelColors], [searchPinColor]) from
/// `colors`. Raster tiles have no traffic layer and no satellite imagery of
/// their own, so the view ignores `traffic` and `satellite`; an app with
/// satellite tiles can pass them as [tileUrlTemplate] (with their
/// [attribution]) when `satellite` is on.
///
/// ## How the session is driven
///
/// The view's [NavigationMapFrame] ticks the session only while it is on
/// screen. A full-screen route pushed on top mutes it: no guidance and no
/// reroute until the user returns. Show a session in one view at a time; two
/// frames on one session tick it twice. To keep guidance running off-screen,
/// call [NavigationSession.tick] yourself, for example from a `Timer` or your
/// own `Ticker`.
class FlutterMapNavigationView extends StatefulWidget {
  const FlutterMapNavigationView({
    super.key,
    required this.session,
    required this.initialCenter,
    required this.userAgentPackageName,
    this.initialZoom = 17,
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.nightTileUrlTemplate,
    this.night = false,
    this.attribution = 'OpenStreetMap contributors',
    this.bottomInset = 0,
    this.routeColors = const RouteColors(),
    this.puck = const CarPuck(),
    this.markerSize = 44,
    this.recenterButton,
    this.focus = 0.7,
    this.children = const [],
    this.onMapReady,
    this.routeLabel,
    this.onRouteOptionTap,
    this.labelColors = MapDefaultColors.routeLabels,
    this.alternativeRouteColor = const Color(0xFF9AA0A6),
    this.onMapTap,
    this.onMapLongPress,
    this.horizontalFocus = 0.5,
    this.alternateLabel,
    this.alternateColor,
    this.fasterLabelColors,
    this.slowerLabelColors,
    this.searchPinColor,
  });

  final NavigationSession session;
  final GeoPoint initialCenter;
  final double initialZoom;
  final String tileUrlTemplate;

  /// The tile URL template used while [night] is true. When null, the day
  /// tiles ([tileUrlTemplate]) are used at night too.
  final String? nightTileUrlTemplate;

  /// Whether to draw the night tiles ([nightTileUrlTemplate], when set).
  final bool night;

  /// Sent as the tile requests' user agent, as tile servers require.
  final String userAgentPackageName;

  /// The tiles' attribution, behind the map's attribution button (bottom
  /// left, beside a side panel there; see [horizontalFocus]).
  final String attribution;

  /// The height of what the app shows over the bottom of the map (a panel,
  /// a footer): the attribution button keeps above it, as tile providers
  /// require it to stay visible. The bottom safe area is kept too.
  final double bottomInset;
  final RouteColors routeColors;

  /// The vehicle drawn on the map. A [CarPuck] sets the marker's size too.
  final Widget puck;

  /// Size of the vehicle marker while not following, when [puck] is not a
  /// [CarPuck].
  final double markerSize;
  final Widget Function(VoidCallback recenter)? recenterButton;
  final double focus;

  /// Extra layers drawn above the route (markers, polygons, …).
  final List<Widget> children;

  /// Called once the map is ready, with its controller (after the adapter's
  /// own setup).
  final void Function(MapController controller)? onMapReady;

  /// The text of the label bubble of a route option, such as its duration.
  /// When null, route options get no labels.
  final String Function(NavRoute route)? routeLabel;

  /// Called with the route index when a route option, or its label, is
  /// tapped.
  final void Function(int index)? onRouteOptionTap;

  /// The colours of the route option labels.
  final RouteLabelColors labelColors;

  /// The colour of the route options that are not selected.
  final Color alternativeRouteColor;

  /// Called with the place the user taps on the map (`MapOptions.onTap`,
  /// so after flutter_map's double-tap window). A tap on a feature the
  /// adapter draws (a route option or its label, an alternate or its
  /// bubble, a search pin or the destination pin) does not call it: the
  /// feature's layer wins flutter_map's gesture arena, so flutter_map
  /// reports no map tap for it, also when a newer list moves or removes the
  /// pressed marker during the press. The map taps also go through the
  /// family's [MapTapGuard], as on the other adapters; it cannot change
  /// anything here (flutter_map reports a map tap only after its double-tap
  /// window, never in the frame or turn of a feature tap). A tap is
  /// delivered one turn of the event loop after flutter_map reports it, and
  /// not once the view is gone. A tap on the session's route line is a map
  /// tap, also where an alternate shares the road (the alternate's line is
  /// drawn only where it differs). A touch on the map still stops following
  /// the vehicle.
  final void Function(GeoPoint point)? onMapTap;

  /// Called with the place the user long-presses on the map
  /// (`MapOptions.onLongPress`), wherever it is, also on a feature the
  /// adapter draws, such as to pin a destination of the app's own
  /// ([DestinationPinMap.showDestinationPin]).
  final void Function(GeoPoint point)? onMapLongPress;

  /// Where the followed vehicle sits across the map, as a fraction of the
  /// width (see [NavigationMapFrame.horizontalFocus]). It is physical: 0 is
  /// the left edge in both text directions, so a caller that places it
  /// beside a start-side panel mirrors it in RTL. The attribution (bottom
  /// left) keeps clear of the panel side of the focus padding: of a panel
  /// on the left (a focus above 0.5), and on the right (below 0.5) when
  /// its popup opens wide.
  final double horizontalFocus;

  /// The text of the bubble on each alternate route drawn while navigating
  /// (see [FlutterMapNavigationMap.alternateLabel]); null draws none.
  /// Forwarded to the map.
  final String Function(AlternateRoute alternate)? alternateLabel;

  /// The colour of the alternate routes drawn while navigating. When null
  /// the map's own colour is kept; forwarded to
  /// [FlutterMapNavigationMap.alternateColor].
  final Color? alternateColor;

  /// The bubble colours of a faster alternate route. When null the map's
  /// own are kept; see [FlutterMapNavigationMap.setAlternateLabelColors].
  final RouteLabelColors? fasterLabelColors;

  /// The bubble colours of a slower (or as fast) alternate route. When null
  /// the map's own are kept; see
  /// [FlutterMapNavigationMap.setAlternateLabelColors].
  final RouteLabelColors? slowerLabelColors;

  /// The colour of the search pins. When null the map's own colour is
  /// kept; forwarded to [FlutterMapNavigationMap.pinColor].
  final Color? searchPinColor;

  @override
  State<FlutterMapNavigationView> createState() =>
      _FlutterMapNavigationViewState();
}

class _FlutterMapNavigationViewState extends State<FlutterMapNavigationView> {
  final _map = FlutterMapNavigationMap();
  final LayerHitNotifier<Object> _optionHits = ValueNotifier(null);
  final LayerHitNotifier<Object> _alternateHits = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _syncMap();
    widget.session.map = _map;
  }

  // What the adapter takes from the widget's properties.
  void _syncMap() {
    _map
      ..routeLabel = widget.routeLabel
      ..onRouteOptionTap = widget.onRouteOptionTap
      ..routeColors = widget.routeColors
      ..alternativeColor = widget.alternativeRouteColor
      ..labelColors = widget.labelColors
      ..alternateLabel = widget.alternateLabel;
    final alternateColor = widget.alternateColor;
    if (alternateColor != null) _map.alternateColor = alternateColor;
    final faster = widget.fasterLabelColors;
    final slower = widget.slowerLabelColors;
    if (faster != null || slower != null) {
      _map.setAlternateLabelColors(
        faster: faster ?? _map.fasterLabelColors,
        slower: slower ?? _map.slowerLabelColors,
      );
    }
    final pinColor = widget.searchPinColor;
    if (pinColor != null) _map.pinColor = pinColor;
  }

  void _onOptionTap() {
    final hit = _optionHits.value?.hitValues.firstOrNull;
    _optionHits.value = null;
    tapRouteOptionLine(_map, hit);
  }

  void _onAlternateTap() {
    final hit = _alternateHits.value?.hitValues.firstOrNull;
    _alternateHits.value = null;
    tapAlternateLine(_map, hit);
  }

  void _onMapTap(TapPosition _, LatLng point) {
    if (widget.onMapTap == null) return;
    final p = GeoPoint(point.latitude, point.longitude);
    // Not the map's side of a tap one of the adapter's features took; read
    // the callback when the tap is delivered.
    dispatchMapTap(_map, () => widget.onMapTap?.call(p));
  }

  void _onMapLongPress(TapPosition _, LatLng point) =>
      widget.onMapLongPress?.call(GeoPoint(point.latitude, point.longitude));

  Size? _reportedSize;

  // Tells the adapter the size of the map, after the frame (a pending fit
  // moves the camera, which must not happen while building).
  void _reportViewport(Size size) {
    if (size == _reportedSize) return;
    _reportedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedSize == size) _map.viewportSize = size;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _map.pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(FlutterMapNavigationView old) {
    super.didUpdateWidget(old);
    _syncMap();
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
  }

  @override
  void dispose() {
    if (identical(widget.session.map, _map)) widget.session.map = null;
    _map.dispose();
    _optionHits.dispose();
    _alternateHits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.routeColors;
    final puck = widget.puck;
    final markerSize = puck is CarPuck ? puck.size : widget.markerSize;
    final nightTiles = widget.night ? widget.nightTileUrlTemplate : null;
    final tileUrlTemplate = nightTiles ?? widget.tileUrlTemplate;
    return NavigationMapFrame(
      session: widget.session,
      vehicleMarkers: _map,
      focus: widget.focus,
      horizontalFocus: widget.horizontalFocus,
      puck: widget.puck,
      recenterButton: widget.recenterButton,
      mapBuilder: (context, padding) {
        _map
          ..focusOffset = (padding.top - padding.bottom) / 2
          ..horizontalFocusOffset = (padding.left - padding.right) / 2
          ..mapPadding = padding;
        return LayoutBuilder(
          builder: (context, constraints) {
            _reportViewport(constraints.biggest);
            return _buildMap(
              context,
              colors,
              markerSize,
              tileUrlTemplate,
              padding,
            );
          },
        );
      },
    );
  }

  Widget _buildMap(
    BuildContext context,
    RouteColors colors,
    double markerSize,
    String tileUrlTemplate,
    EdgeInsets focus,
  ) {
    return FlutterMap(
      mapController: _map.controller,
      options: MapOptions(
        initialCenter: toLatLng(widget.initialCenter),
        initialZoom: widget.initialZoom,
        onMapReady: () {
          _map.onMapReady();
          widget.onMapReady?.call(_map.controller);
        },
        onTap: _onMapTap,
        onLongPress: _onMapLongPress,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrlTemplate,
          userAgentPackageName: widget.userAgentPackageName,
        ),
        // The alternates, under the route options and the session's route
        // (which takes the taps where it covers them). A tap on a line
        // reads the layer's hit.
        ValueListenableBuilder(
          valueListenable: _map.alternateLines,
          builder: (context, lines, _) => lines.isEmpty
              ? const SizedBox.shrink()
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  hitTestBehavior: HitTestBehavior.deferToChild,
                  child: GestureDetector(
                    onTap: _onAlternateTap,
                    child: PolylineLayer<Object>(
                      polylines: lines,
                      hitNotifier: _alternateHits,
                    ),
                  ),
                ),
        ),
        // The route options, under the session's own route. A tap on a line
        // reads the layer's hit.
        ValueListenableBuilder(
          valueListenable: _map.routeOptionLines,
          builder: (context, lines, _) => lines.isEmpty
              ? const SizedBox.shrink()
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  hitTestBehavior: HitTestBehavior.deferToChild,
                  child: GestureDetector(
                    onTap: _onOptionTap,
                    child: PolylineLayer<Object>(
                      polylines: lines,
                      hitNotifier: _optionHits,
                    ),
                  ),
                ),
        ),
        ValueListenableBuilder(
          valueListenable: _map.route,
          builder: (context, line, _) => PolylineLayer(
            polylines: [
              if (line != null) ...[
                Polyline(
                  points: line.driven,
                  color: colors.driven,
                  strokeWidth: colors.drivenWidth,
                ),
                Polyline(
                  points: line.ahead,
                  color: colors.ahead,
                  strokeWidth: colors.aheadWidth,
                ),
              ],
            ],
          ),
        ),
        _markers(_map.alternateLabels),
        _markers(_map.routeOptionLabels),
        ValueListenableBuilder(
          valueListenable: _map.destinationPin,
          builder: (context, pin, _) => pin == null
              ? const SizedBox.shrink()
              : MarkerLayer(markers: [pin]),
        ),
        _markers(_map.searchPins),
        ...widget.children,
        ValueListenableBuilder(
          valueListenable: _map.vehicle,
          builder: (context, v, _) => MarkerLayer(
            markers: [
              if (v != null)
                Marker(
                  point: v.position,
                  width: markerSize,
                  height: markerSize,
                  child: Transform.rotate(
                    angle: v.bearing * math.pi / 180,
                    child: widget.puck,
                  ),
                ),
            ],
          ),
        ),
        _attribution(context, focus),
      ],
    );
  }

  /// A marker layer of [markers], none while empty.
  static Widget _markers(ValueListenable<List<Marker>> markers) =>
      ValueListenableBuilder(
        valueListenable: markers,
        builder: (context, list, _) =>
            list.isEmpty ? const SizedBox.shrink() : MarkerLayer(markers: list),
      );

  /// The attribution, above [FlutterMapNavigationView.bottomInset] and
  /// beside the side insets of the [focus] padding (a side panel). What
  /// covers the bottom keeps its content above the bottom safe area, so the
  /// safe area counts only without it. The wrappers are the same whatever
  /// the insets, so an inset change keeps the attribution's state (an open
  /// popup stays open). The sides are physical, as `horizontalFocus` is, so
  /// this holds in LTR and in RTL.
  Widget _attribution(BuildContext context, EdgeInsets focus) {
    final inset = math.max(0.0, widget.bottomInset);
    return Padding(
      padding: EdgeInsets.only(
        left: focus.left,
        right: focus.right,
        bottom: inset,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: inset > 0,
        child: RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution(widget.attribution)],
        ),
      ),
    );
  }
}
