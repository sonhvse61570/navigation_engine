import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'flutter_map_navigation_map.dart';

/// A ready-made navigation map on flutter_map: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter.
///
/// Attaches itself as [NavigationSession.map] while mounted. The app owns
/// the session (create, start, dispose).
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
    this.labelColors = const RouteLabelColors(),
    this.alternativeRouteColor = const Color(0xFF9AA0A6),
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
  /// left).
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

  @override
  State<FlutterMapNavigationView> createState() =>
      _FlutterMapNavigationViewState();
}

class _FlutterMapNavigationViewState extends State<FlutterMapNavigationView> {
  final _map = FlutterMapNavigationMap();
  final LayerHitNotifier<Object> _optionHits = ValueNotifier(null);

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
      ..labelColors = widget.labelColors;
  }

  void _onOptionTap() {
    final hit = _optionHits.value?.hitValues.firstOrNull;
    _optionHits.value = null;
    if (hit is int) widget.onRouteOptionTap?.call(hit);
  }

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
      puck: widget.puck,
      recenterButton: widget.recenterButton,
      mapBuilder: (context, padding) {
        _map.focusOffset = (padding.top - padding.bottom) / 2;
        _map.mapPadding = padding;
        return LayoutBuilder(
          builder: (context, constraints) {
            _reportViewport(constraints.biggest);
            return _buildMap(context, colors, markerSize, tileUrlTemplate);
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
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrlTemplate,
          userAgentPackageName: widget.userAgentPackageName,
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
        ValueListenableBuilder(
          valueListenable: _map.routeOptionLabels,
          builder: (context, labels, _) => labels.isEmpty
              ? const SizedBox.shrink()
              : MarkerLayer(markers: labels),
        ),
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
        _attribution(context),
      ],
    );
  }

  /// The attribution, above [FlutterMapNavigationView.bottomInset]. What
  /// covers the bottom keeps its content above the bottom safe area, so the
  /// safe area counts only without it. The wrappers are the same whatever
  /// the inset, so an inset change keeps the attribution's state (an open
  /// popup stays open).
  Widget _attribution(BuildContext context) {
    final inset = math.max(0.0, widget.bottomInset);
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
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
