import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'maplibre_navigation_map.dart';

/// A ready-made navigation map on MapLibre: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter.
///
/// On Android set `MapLibreMap.useHybridComposition = true` before
/// `runApp()`, otherwise Flutter widgets (the vehicle puck) cannot be drawn
/// over the map. Attaches itself as [NavigationSession.map] while mounted;
/// the app owns the session.
///
/// ## How the session is driven
///
/// The view's [NavigationMapFrame] ticks the session only while it is on
/// screen. A full-screen route pushed on top mutes it: no guidance and no
/// reroute until the user returns. Show a session in one view at a time; two
/// frames on one session tick it twice. To keep guidance running off-screen,
/// call [NavigationSession.tick] yourself, for example from a `Timer` or your
/// own `Ticker`.
class MapLibreNavigationView extends StatefulWidget {
  const MapLibreNavigationView({
    super.key,
    required this.session,
    required this.styleString,
    required this.initialCenter,
    this.initialZoom = 17,
    this.routeColors = const RouteColors(),
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.recenterButton,
    this.focus = 0.7,
    this.onMapCreated,
  });

  final NavigationSession session;

  /// A style URL (e.g. `https://tiles.openfreemap.org/styles/liberty`),
  /// asset path or style JSON.
  final String styleString;
  final GeoPoint initialCenter;
  final double initialZoom;

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

  /// Gives the app the controller, e.g. to add its own layers.
  final void Function(MapLibreMapController controller)? onMapCreated;

  @override
  State<MapLibreNavigationView> createState() => _MapLibreNavigationViewState();
}

class _MapLibreNavigationViewState extends State<MapLibreNavigationView> {
  late final _map = MapLibreNavigationMap(
    routeColors: widget.routeColors,
    vehicleImage: widget.vehicleImage ?? vehicleImageFor(widget.puck),
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
  void didUpdateWidget(MapLibreNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
    _map.routeColors = widget.routeColors;
    if (old.styleString != widget.styleString) _map.onStyleChanging();
  }

  @override
  void dispose() {
    if (identical(widget.session.map, _map)) widget.session.map = null;
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
        return MapLibreMap(
          styleString: widget.styleString,
          initialCameraPosition: CameraPosition(
            target: toLatLng(widget.initialCenter),
            zoom: widget.initialZoom,
          ),
          compassEnabled: false,
          myLocationEnabled: false,
          onMapCreated: (c) {
            _map.onMapCreated(c);
            widget.onMapCreated?.call(c);
          },
          onStyleLoadedCallback: _map.onStyleLoaded,
        );
      },
    );
  }
}
