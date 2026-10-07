import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'mapbox_navigation_map.dart';

/// A ready-made navigation map on Mapbox: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter.
///
/// Call `MapboxOptions.setAccessToken(...)` before building it. Attaches
/// itself as [NavigationSession.map] while mounted; the app owns the session.
/// The compass and the scale bar are turned off.
///
/// ## How the session is driven
///
/// The view's [NavigationMapFrame] ticks the session only while it is on
/// screen. A full-screen route pushed on top mutes it: no guidance and no
/// reroute until the user returns. Show a session in one view at a time; two
/// frames on one session tick it twice. To keep guidance running off-screen,
/// call [NavigationSession.tick] yourself, for example from a `Timer` or your
/// own `Ticker`.
class MapboxNavigationView extends StatefulWidget {
  const MapboxNavigationView({
    super.key,
    required this.session,
    required this.initialCenter,
    this.initialZoom = 17,
    this.styleUri = MapboxStyles.STANDARD,
    this.routeColors = const RouteColors(),
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.recenterButton,
    this.focus = 0.7,
    this.onMapCreated,
  });

  final NavigationSession session;
  final GeoPoint initialCenter;
  final double initialZoom;
  final String styleUri;

  /// The route line colours and widths; changes are applied to the lines.
  final RouteColors routeColors;

  /// The vehicle while the camera follows it (a widget over the map). A
  /// [CarPuck]'s size and colour are also used for the marker drawn on the
  /// map itself; for any other widget pass [vehicleImage] so the two look
  /// the same.
  final Widget puck;

  /// Renders the PNG of the vehicle marker drawn by the map, at the device
  /// pixel ratio. Defaults to rendering [puck] when it is a [CarPuck] (see
  /// `vehicleImageFor`), otherwise the default [CarPuck]. Read once, when the
  /// view is created.
  final VehicleImageBuilder? vehicleImage;
  final Widget Function(VoidCallback recenter)? recenterButton;
  final double focus;

  /// Gives the app the map, e.g. to add its own layers.
  final void Function(MapboxMap map)? onMapCreated;

  @override
  State<MapboxNavigationView> createState() => _MapboxNavigationViewState();
}

class _MapboxNavigationViewState extends State<MapboxNavigationView> {
  late final _map = MapboxNavigationMap(
    routeColors: widget.routeColors,
    vehicleImage: widget.vehicleImage ?? vehicleImageFor(widget.puck),
  );

  /// Created once: a new viewport state on every rebuild would move the
  /// camera back to the initial position.
  late final _initialViewport = CameraViewportState(
    center: toPoint(widget.initialCenter),
    zoom: widget.initialZoom,
  );

  @override
  void initState() {
    super.initState();
    widget.session.map = _map;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _map.pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(MapboxNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
    _map.routeColors = widget.routeColors;
    // MapWidget reads styleUri only when the map is created.
    if (old.styleUri != widget.styleUri) _map.changeStyle(widget.styleUri);
  }

  @override
  void dispose() {
    if (identical(widget.session.map, _map)) widget.session.map = null;
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NavigationMapFrame(
      session: widget.session,
      vehicleMarkers: _map,
      focus: widget.focus,
      puck: widget.puck,
      recenterButton: widget.recenterButton,
      mapBuilder: (context, padding) {
        _map.padding = padding;
        return MapWidget(
          styleUri: widget.styleUri,
          viewport: _initialViewport,
          onMapCreated: (map) {
            _map
              ..onMapCreated(map)
              ..hideOrnaments();
            widget.onMapCreated?.call(map);
          },
          onStyleLoadedListener: (_) => unawaited(_map.onStyleLoaded()),
        );
      },
    );
  }
}
