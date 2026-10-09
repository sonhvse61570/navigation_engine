import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_maps_navigation_map.dart';
import 'ui/google_style_colors.dart';

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
  /// Creates a Google map that shows and follows [session].
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
    this.style,
    this.showRecenterButton = true,
    this.routeLabel,
    this.onRouteOptionTap,
    this.alternativeRouteColor,
    this.labelColors,
    this.trafficEnabled = false,
    this.mapType = MapType.normal,
    this.alternateLabel,
    this.horizontalFocus = 0.5,
    this.bottomOverlay = 0,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// The zoom of the map before the first camera move.
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

  /// Builds the button shown while the camera does not follow the vehicle,
  /// given the callback that follows it again; null for the default one.
  final Widget Function(VoidCallback recenter)? recenterButton;

  /// Where the followed vehicle sits, as a fraction of the height (0 = top).
  final double focus;

  /// The app's own markers, drawn next to the vehicle marker. Do not use the
  /// ids `navigation_engine_vehicle`, `navigation_engine_driven`,
  /// `navigation_engine_ahead`, `navigation_engine_option_*`,
  /// `navigation_engine_alternate_*` or `navigation_engine_search_*`: the
  /// adapter owns them (some are polyline ids).
  final Set<Marker> markers;

  /// Called with the map's controller once the map is created.
  final void Function(GoogleMapController controller)? onMapCreated;

  /// The map style, a JSON array of style rules, passed to `GoogleMap.style`.
  /// [googleStyleNightMapStyle] is a ready-made dark one; null keeps the
  /// default look and an empty string clears a style that was set.
  final String? style;

  /// Whether the recenter button shows once the user has moved the map away
  /// from the vehicle. When false nothing is shown in its place (an app
  /// with its own recenter control, or one showing it in a panel).
  final bool showRecenterButton;

  /// The text of the label bubble drawn on each route option, such as its
  /// duration. Needed only for route options
  /// ([RoutePreviewMap.showRouteOptions], called by
  /// [NavigationFlowController]); when null no label bubbles are drawn.
  /// Forwarded to the map, so changes apply to the next options shown.
  final String Function(NavRoute route)? routeLabel;

  /// Called with the index of the route option the user taps, on its line or
  /// on its label bubble. Forwarded to the map.
  final void Function(int index)? onRouteOptionTap;

  /// The colour of the route options that are not selected. When null the
  /// map's own colour is kept (a muted grey by default); when set, changes
  /// redraw the options shown.
  final Color? alternativeRouteColor;

  /// The colours of the route option label bubbles: the selected one in
  /// `accent` / `onAccent`, the others in `surface` / `onSurface` (see
  /// [GoogleStyleRouteLabelColors.routeLabelColors]). When null the map's own
  /// colours are kept ([GoogleStyleColors.day] by default); when set, changes
  /// render the labels shown again. It also sets the alternate routes'
  /// colour ([GoogleStyleColors.alternative]), their bubble colours
  /// ([GoogleStyleRouteLabelColors.fasterLabelColors] and
  /// [GoogleStyleRouteLabelColors.slowerLabelColors]) and the search pins'
  /// colour ([GoogleStyleColors.warning]).
  final GoogleStyleColors? labelColors;

  /// Whether the map shows its traffic layer (`GoogleMap.trafficEnabled`).
  final bool trafficEnabled;

  /// The map type, such as [MapType.hybrid] for a satellite map with roads.
  final MapType mapType;

  /// The text of the bubble on each alternate route drawn while navigating
  /// (see [GoogleMapsNavigationMap.alternateLabel]); null draws none.
  /// Forwarded to the map.
  final String Function(AlternateRoute alternate)? alternateLabel;

  /// Where the followed vehicle sits across the map, as a fraction of the
  /// width (see [NavigationMapFrame.horizontalFocus]). It is physical: 0 is
  /// the left edge in both text directions, so a caller that places it
  /// beside a start-side panel mirrors it in RTL. The map padding that moves
  /// the focus also keeps the Google logo clear of that panel (a left inset
  /// above 0.5, a right inset below).
  final double horizontalFocus;

  /// The height of what the app shows over the bottom of the map (such as
  /// [NavigationMapConfig.bottomOverlayHeight]); 0 by default. The map
  /// padding's bottom grows by it, so the Google logo stays above it, as
  /// the Google Maps Platform terms require, and its top grows by as much,
  /// so the followed vehicle stays at [focus]. It is capped so the padded
  /// map keeps at least 48 dp of height.
  final double bottomOverlay;

  @override
  State<GoogleMapsNavigationView> createState() =>
      _GoogleMapsNavigationViewState();
}

class _GoogleMapsNavigationViewState extends State<GoogleMapsNavigationView> {
  late final _map = GoogleMapsNavigationMap(routeColors: widget.routeColors);
  late final VehicleImageBuilder _image =
      widget.vehicleImage ?? vehicleImageFor(widget.puck);
  double? _ratio;
  Size? _viewport;

  void _forwardOptions() {
    _map
      ..routeLabel = widget.routeLabel
      ..onRouteOptionTap = widget.onRouteOptionTap
      ..alternateLabel = widget.alternateLabel;
    final alternative = widget.alternativeRouteColor;
    if (alternative != null) _map.alternativeColor = alternative;
    final labelColors = widget.labelColors;
    if (labelColors != null) {
      _map
        ..labelColors = labelColors.routeLabelColors
        ..alternateColor = labelColors.alternative
        ..pinColor = labelColors.warning
        ..setAlternateLabelColors(
          faster: labelColors.fasterLabelColors,
          slower: labelColors.slowerLabelColors,
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _forwardOptions();
    widget.session.map = _map;
  }

  // The map needs its size to fit routes; set after the frame, only when it
  // changed, because the layout is not over while the builder runs.
  void _viewportChanged(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.viewportSize = size;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio == _ratio) return;
    _ratio = ratio;
    _map.labelPixelRatio = ratio;
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
    _forwardOptions();
  }

  /// [focus] (the focus padding) with [GoogleMapsNavigationView.bottomOverlay]
  /// added to its bottom and its top: the SDK centres the camera in the
  /// padded view, so the centre (the focus) does not move, and the logo,
  /// at the padded bottom, clears the overlay.
  EdgeInsets _withBottomOverlay(EdgeInsets focus, double height) {
    final room = (height - focus.top - focus.bottom - _minMapHeight) / 2;
    final lift = math.min(widget.bottomOverlay, math.max(0.0, room));
    if (!(lift > 0)) return focus;
    return focus.copyWith(top: focus.top + lift, bottom: focus.bottom + lift);
  }

  /// The least height the padded map keeps.
  static const double _minMapHeight = 48;

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
      horizontalFocus: widget.horizontalFocus,
      puck: widget.puck,
      recenterButton: widget.showRecenterButton
          ? widget.recenterButton
          : (_) => const SizedBox.shrink(),
      mapBuilder: (context, focus) {
        return LayoutBuilder(
          builder: (context, box) {
            _viewportChanged(box.biggest);
            final padding = _withBottomOverlay(focus, box.maxHeight);
            // The SDK centres the camera target in the padded view: the next
            // route fit accounts for it. A plain field, so nothing moves now.
            _map.mapPadding = padding;
            return ListenableBuilder(
              listenable: Listenable.merge([
                _map.polylines,
                _map.routeOptionPolylines,
                _map.routeOptionMarkers,
                _map.alternatePolylines,
                _map.alternateMarkers,
                _map.searchMarkers,
                _map.vehicleMarker,
              ]),
              builder: (context, _) => GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: toLatLng(widget.initialCenter),
                  zoom: widget.initialZoom,
                ),
                style: widget.style,
                padding: padding,
                trafficEnabled: widget.trafficEnabled,
                mapType: widget.mapType,
                compassEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                polylines: {
                  ..._map.polylines.value,
                  ..._map.routeOptionPolylines.value,
                  ..._map.alternatePolylines.value,
                },
                markers: {
                  ...widget.markers,
                  ..._map.routeOptionMarkers.value,
                  ..._map.alternateMarkers.value,
                  ..._map.searchMarkers.value,
                  ?_map.vehicleMarker.value,
                },
                onMapCreated: (c) {
                  _map.onMapCreated(c);
                  widget.onMapCreated?.call(c);
                },
              ),
            );
          },
        );
      },
    );
  }
}
