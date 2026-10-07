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
    this.attribution = 'OpenStreetMap contributors',
    this.routeColors = const RouteColors(),
    this.puck = const CarPuck(),
    this.markerSize = 44,
    this.recenterButton,
    this.focus = 0.7,
    this.children = const [],
    this.onMapReady,
  });

  final NavigationSession session;
  final GeoPoint initialCenter;
  final double initialZoom;
  final String tileUrlTemplate;

  /// Sent as the tile requests' user agent, as tile servers require.
  final String userAgentPackageName;
  final String attribution;
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

  @override
  State<FlutterMapNavigationView> createState() =>
      _FlutterMapNavigationViewState();
}

class _FlutterMapNavigationViewState extends State<FlutterMapNavigationView> {
  final _map = FlutterMapNavigationMap();

  @override
  void initState() {
    super.initState();
    widget.session.map = _map;
  }

  @override
  void didUpdateWidget(FlutterMapNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
  }

  @override
  void dispose() {
    if (identical(widget.session.map, _map)) widget.session.map = null;
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.routeColors;
    final puck = widget.puck;
    final markerSize = puck is CarPuck ? puck.size : widget.markerSize;
    return NavigationMapFrame(
      session: widget.session,
      vehicleMarkers: _map,
      focus: widget.focus,
      puck: widget.puck,
      recenterButton: widget.recenterButton,
      mapBuilder: (context, padding) {
        _map.focusOffset = (padding.top - padding.bottom) / 2;
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
              urlTemplate: widget.tileUrlTemplate,
              userAgentPackageName: widget.userAgentPackageName,
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
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution(widget.attribution)],
            ),
          ],
        );
      },
    );
  }
}
