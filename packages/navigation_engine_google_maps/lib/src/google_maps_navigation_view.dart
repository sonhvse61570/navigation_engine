import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_maps_navigation_map.dart';

/// A ready-made navigation map on Google Maps: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter.
///
/// Needs the app's Google Maps API key configured as for any
/// google_maps_flutter app. Attaches itself as [NavigationSession.map] while
/// mounted; the app owns the session.
///
/// ## How the session is driven
///
/// The view's [NavigationMapFrame] ticks the session only while it is on
/// screen. A full-screen route pushed on top mutes it: no guidance and no
/// reroute until the user returns. Show a session in one view at a time; two
/// frames on one session tick it twice. To keep guidance running off-screen,
/// call [NavigationSession.tick] yourself, for example from a `Timer` or your
/// own `Ticker`.
class GoogleMapsNavigationView extends StatefulWidget {
  const GoogleMapsNavigationView({
    super.key,
    required this.session,
    required this.initialCenter,
    this.initialZoom = 17,
    this.routeColors = const RouteColors(),
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.recenterButton,
    this.focus = 0.7,
    this.markers = const {},
    this.onMapCreated,
  });

  final NavigationSession session;
  final GeoPoint initialCenter;
  final double initialZoom;

  /// The route line colours and widths; changes redraw the route.
  final RouteColors routeColors;

  /// The vehicle while the camera follows it (a widget over the map). A
  /// [CarPuck]'s size and colour are also used for the marker drawn by the
  /// map itself; for any other widget pass [vehicleImage] so the two look
  /// the same.
  final Widget puck;

  /// Renders the PNG of the vehicle marker drawn by the map, at the device
  /// pixel ratio (the marker keeps the puck's logical size on any density).
  /// Defaults to rendering [puck] when it is a [CarPuck] (see
  /// `vehicleImageFor`), otherwise the default [CarPuck]. Read once, when the
  /// view is created. If it throws, the default Google marker is kept.
  final VehicleImageBuilder? vehicleImage;
  final Widget Function(VoidCallback recenter)? recenterButton;
  final double focus;

  /// The app's own markers, drawn next to the vehicle marker. Do not use the
  /// ids `navigation_engine_vehicle`, `navigation_engine_driven` or
  /// `navigation_engine_ahead`: the adapter owns them (the last two are
  /// route polyline ids).
  final Set<Marker> markers;
  final void Function(GoogleMapController controller)? onMapCreated;

  @override
  State<GoogleMapsNavigationView> createState() =>
      _GoogleMapsNavigationViewState();
}

class _GoogleMapsNavigationViewState extends State<GoogleMapsNavigationView> {
  late final _map = GoogleMapsNavigationMap(routeColors: widget.routeColors);
  late final VehicleImageBuilder _image =
      widget.vehicleImage ?? vehicleImageFor(widget.puck);
  double? _ratio;

  @override
  void initState() {
    super.initState();
    widget.session.map = _map;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio == _ratio) return;
    _ratio = ratio;
    _image(ratio).then(
      (png) {
        // A newer ratio may have been asked for while this one rendered.
        if (mounted && _ratio == ratio) {
          _map.vehicleIcon = vehicleIconFrom(png, pixelRatio: ratio);
        }
      },
      // Keep the default marker when the puck image cannot be rendered.
      onError: (Object _) {},
    );
  }

  @override
  void didUpdateWidget(GoogleMapsNavigationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      if (identical(old.session.map, _map)) old.session.map = null;
      widget.session.map = _map;
    }
    _map.routeColors = widget.routeColors;
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
      mapBuilder: (context, padding) => ValueListenableBuilder(
        valueListenable: _map.polylines,
        builder: (context, polylines, _) => ValueListenableBuilder(
          valueListenable: _map.vehicleMarker,
          builder: (context, vehicle, _) => GoogleMap(
            initialCameraPosition: CameraPosition(
              target: toLatLng(widget.initialCenter),
              zoom: widget.initialZoom,
            ),
            padding: padding,
            compassEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            polylines: polylines,
            markers: {...widget.markers, ?vehicle},
            onMapCreated: (c) {
              _map.onMapCreated(c);
              widget.onMapCreated?.call(c);
            },
          ),
        ),
      ),
    );
  }
}
