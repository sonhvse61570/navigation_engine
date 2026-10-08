import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'maplibre_navigation_map.dart';

/// A ready-made navigation map on MapLibre: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter. It is
/// a [RoutePreviewMap] too: a [NavigationFlowController] on [session] draws
/// its route options here (see [routeLabel], [onRouteOptionTap]).
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
    this.nightStyleString,
    this.night = false,
    this.routeLabel,
    this.onRouteOptionTap,
    this.labelColors = const RouteLabelColors(),
    this.alternativeRouteColor = const Color(0xFF9AA0A6),
    this.bottomInset = 0,
  });

  final NavigationSession session;

  /// A style URL (e.g. `https://tiles.openfreemap.org/styles/liberty`),
  /// asset path or style JSON.
  final String styleString;
  final GeoPoint initialCenter;

  /// The first zoom, in the scale of [CameraTarget] zooms (the 256 dp world
  /// of Google Maps); the view converts it to MapLibre's.
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

  /// Gives the app the controller, e.g. to add its own layers (once the
  /// style has loaded). Called after the adapter has the controller: route
  /// options shown from here on, or before, are drawn once the style has
  /// loaded, and a fit waits for the view's size.
  final void Function(MapLibreMapController controller)? onMapCreated;

  /// The style used while [night] is true. When null, [styleString] is used
  /// at night too.
  final String? nightStyleString;

  /// Whether to show [nightStyleString] (when set). A switch reloads the
  /// style; the route, the vehicle and the route options are drawn again
  /// once it has loaded.
  final bool night;

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

  /// The height of what the app shows over the bottom of the map (a panel,
  /// a footer): the MapLibre attribution button and logo keep 8 above it
  /// (`attributionButtonMargins` and `logoViewMargins`), as the map's data
  /// providers require them to stay visible.
  final double bottomInset;

  /// The margin of the attribution button and the logo from the map's
  /// edges, above [bottomInset].
  static const double _ornamentMargin = 8;

  /// The style shown: [nightStyleString] at [night], otherwise [styleString].
  String get _shownStyle =>
      night ? nightStyleString ?? styleString : styleString;

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
  void didUpdateWidget(MapLibreNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
    _syncMap();
    if (old._shownStyle != widget._shownStyle) _map.onStyleChanging();
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
        return LayoutBuilder(
          builder: (context, constraints) {
            _reportViewport(constraints.biggest);
            return _buildMap();
          },
        );
      },
    );
  }

  /// Where the attribution button and the logo sit from their corner.
  Point<double> get _ornamentMargins => Point(
    MapLibreNavigationView._ornamentMargin,
    widget.bottomInset + MapLibreNavigationView._ornamentMargin,
  );

  Widget _buildMap() {
    return MapLibreMap(
      styleString: widget._shownStyle,
      initialCameraPosition: CameraPosition(
        target: toLatLng(widget.initialCenter),
        zoom: toSdkZoom(widget.initialZoom),
      ),
      compassEnabled: false,
      myLocationEnabled: false,
      attributionButtonMargins: _ornamentMargins,
      logoViewMargins: _ornamentMargins,
      onMapCreated: (c) {
        _map.onMapCreated(c);
        widget.onMapCreated?.call(c);
      },
      onStyleLoadedCallback: _map.onStyleLoaded,
    );
  }
}
