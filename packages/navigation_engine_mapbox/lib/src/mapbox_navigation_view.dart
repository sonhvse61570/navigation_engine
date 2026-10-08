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
  ///
  /// On [MapboxStyles.STANDARD] the view owns the light preset: `day` by
  /// day and `night` at night, set at each style load, so a preset set on
  /// the `MapboxMap` (such as `dusk`) does not stay. For another preset use
  /// your own [MapboxNavigationMap] and its
  /// [MapboxNavigationMap.lightPreset].
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

/// What a [MapboxNavigationView] does with its [MapboxNavigationMap], apart
/// from building the SDK's map: it creates the adapter, attaches it to the
/// session, forwards the view's parameters, switches day and night, places
/// the ornaments once the map exists, reports the view's size and detaches
/// on dispose. The view and the tests' stand-in view share it, so the two
/// cannot drift. Not part of the public API (hidden by the library export).
class MapboxViewBinding {
  /// Creates the adapter of [view] and attaches it to the view's session.
  /// The vehicle image is the view's, else [fallbackVehicleImage], else
  /// the view's puck rendered.
  MapboxViewBinding(
    MapboxNavigationView view, {
    VehicleImageBuilder? fallbackVehicleImage,
  }) : adapter = MapboxNavigationMap(
         routeColors: view.routeColors,
         vehicleImage:
             view.vehicleImage ??
             fallbackVehicleImage ??
             vehicleImageFor(view.puck),
       ) {
    _sync(view);
    adapter.lightPreset = view._dayNight.lightPreset;
    view.session.map = adapter;
  }

  /// The adapter the view draws with.
  final MapboxNavigationMap adapter;

  // What the adapter takes from the view's properties.
  void _sync(MapboxNavigationView view) {
    adapter
      ..routeLabel = view.routeLabel
      ..onRouteOptionTap = view.onRouteOptionTap
      ..routeColors = view.routeColors
      ..alternativeColor = view.alternativeRouteColor
      ..labelColors = view.labelColors
      ..bottomInset = view.bottomInset;
  }

  /// The view was rebuilt from [old] to [view].
  void update(MapboxNavigationView old, MapboxNavigationView view) {
    if (!identical(old.session, view.session)) {
      if (identical(old.session.map, adapter)) old.session.map = null;
      view.session.map = adapter;
    }
    _sync(view);
    // MapWidget reads styleUri only when the map is created. The style
    // change comes first: a light preset for the new style then waits for
    // it to load.
    final shown = view._dayNight;
    if (old._dayNight.styleUri != shown.styleUri) {
      adapter.changeStyle(shown.styleUri);
    }
    adapter.lightPreset = shown.lightPreset;
  }

  /// The map exists (the adapter has it): the compass and the scale bar
  /// go, the logo and the attribution keep above the bottom inset.
  void mapCreated() => adapter
    ..hideOrnaments()
    ..placeOrnaments();

  Size? _reportedSize;

  /// Tells the adapter the size of the map, after the frame (a pending fit
  /// moves the camera, which must not happen while building).
  void reportViewport(Size size, {required bool Function() mounted}) {
    if (size == _reportedSize) return;
    _reportedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted() && _reportedSize == size) adapter.viewportSize = size;
    });
  }

  /// The view of [view] is gone: detaches and disposes the adapter.
  void dispose(MapboxNavigationView view) {
    if (identical(view.session.map, adapter)) view.session.map = null;
    adapter.dispose();
  }
}

class _MapboxNavigationViewState extends State<MapboxNavigationView> {
  late final _binding = MapboxViewBinding(widget);
  MapboxNavigationMap get _map => _binding.adapter;

  /// Created once: a new viewport state on every rebuild would move the
  /// camera back to the initial position.
  late final _initialViewport = toInitialViewport(
    widget.initialCenter,
    widget.initialZoom,
  );

  @override
  void initState() {
    super.initState();
    _binding; // Creates the adapter and attaches it now.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _map.pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(MapboxNavigationView old) {
    super.didUpdateWidget(old);
    _binding.update(old, widget);
  }

  @override
  void dispose() {
    _binding.dispose(widget);
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
            _binding.reportViewport(
              constraints.biggest,
              mounted: () => mounted,
            );
            return MapWidget(
              // Read only when the map is created; changes go through
              // changeStyle (see MapboxViewBinding.update).
              styleUri: widget._dayNight.styleUri,
              viewport: _initialViewport,
              onMapCreated: (map) {
                _map.onMapCreated(map);
                _binding.mapCreated();
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
