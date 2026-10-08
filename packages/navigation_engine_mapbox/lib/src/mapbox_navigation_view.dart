import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'mapbox_navigation_map.dart';

/// What a [MapboxNavigationView] shows by [night]: the style to load and
/// the Standard style's light preset (null leaves the light alone).
///
/// On [MapboxStyles.STANDARD] night is its `night` light preset (and day
/// its `day` one): no style reload, and [nightStyleUri] is not used. On any
/// other style night loads [nightStyleUri], or keeps [styleUri] when it is
/// null. Not part of the public API (hidden by the library export).
({String styleUri, String? lightPreset}) dayNightStyle(
  String styleUri,
  String? nightStyleUri, {
  required bool night,
}) {
  if (styleUri == MapboxStyles.STANDARD) {
    return (styleUri: styleUri, lightPreset: night ? 'night' : 'day');
  }
  return (
    styleUri: night ? nightStyleUri ?? styleUri : styleUri,
    lightPreset: null,
  );
}

/// A ready-made navigation map on Mapbox: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter. It is
/// a [RoutePreviewMap] too: a [NavigationFlowController] on [session] draws
/// its route options here (see [routeLabel], [onRouteOptionTap]).
///
/// Call `MapboxOptions.setAccessToken(...)` before building it. Attaches
/// itself as [NavigationSession.map] while mounted; the app owns the session.
/// The compass and the scale bar are turned off; the logo and the
/// attribution button keep above [bottomInset].
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
    this.night = false,
    this.nightStyleUri,
    this.routeLabel,
    this.onRouteOptionTap,
    this.labelColors = const RouteLabelColors(),
    this.alternativeRouteColor = const Color(0xFF9AA0A6),
    this.bottomInset = 0,
  });

  final NavigationSession session;
  final GeoPoint initialCenter;

  /// The first zoom, in the scale of [CameraTarget] zooms (the 256 dp world
  /// of Google Maps); the view converts it to Mapbox's.
  final double initialZoom;

  /// The style shown by day (and at night, unless [night] switches it; see
  /// [nightStyleUri]).
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

  /// Gives the app the map, e.g. to add its own layers (once the style has
  /// loaded). Called after the adapter has the map: route options shown
  /// from here on, or before, are drawn once the style has loaded, and a
  /// fit waits for the view's size.
  final void Function(MapboxMap map)? onMapCreated;

  /// Whether the map shows night. On [MapboxStyles.STANDARD] this is the
  /// style's `night` light preset, applied without a style reload; on other
  /// styles it loads [nightStyleUri] (when set). Either way the route, the
  /// vehicle and the route options stay.
  final bool night;

  /// The style loaded while [night] is true, for styles other than
  /// [MapboxStyles.STANDARD] (which switches its light preset instead).
  /// When null, [styleUri] is kept at night.
  final String? nightStyleUri;

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
  /// a footer): the Mapbox logo and the attribution button keep 8 above
  /// it, as Mapbox's terms require them to stay visible; see
  /// [MapboxNavigationMap.bottomInset]. Applied when the map is created and
  /// on each change.
  final double bottomInset;

  ({String styleUri, String? lightPreset}) get _dayNight =>
      dayNightStyle(styleUri, nightStyleUri, night: night);

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
  late final _initialViewport = toInitialViewport(
    widget.initialCenter,
    widget.initialZoom,
  );

  @override
  void initState() {
    super.initState();
    _syncMap();
    _map.lightPreset = widget._dayNight.lightPreset;
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
      ..bottomInset = widget.bottomInset;
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
  void didUpdateWidget(MapboxNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
    _syncMap();
    // MapWidget reads styleUri only when the map is created. The style
    // change comes first: a light preset for the new style then waits for
    // it to load.
    final shown = widget._dayNight;
    if (old._dayNight.styleUri != shown.styleUri) {
      _map.changeStyle(shown.styleUri);
    }
    _map.lightPreset = shown.lightPreset;
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
            return MapWidget(
              // Read only when the map is created; changes go through
              // changeStyle (see didUpdateWidget).
              styleUri: widget._dayNight.styleUri,
              viewport: _initialViewport,
              onMapCreated: (map) {
                _map
                  ..onMapCreated(map)
                  ..hideOrnaments()
                  ..placeOrnaments();
                widget.onMapCreated?.call(map);
              },
              onStyleLoadedListener: (_) => unawaited(_map.onStyleLoaded()),
            );
          },
        );
      },
    );
  }
}
