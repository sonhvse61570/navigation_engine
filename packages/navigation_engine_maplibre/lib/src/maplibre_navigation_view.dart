import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'maplibre_navigation_map.dart';

/// A ready-made navigation map on MapLibre: follows [session]'s vehicle
/// heading-up, draws the route and the vehicle, and offers recenter. Its
/// map is a [RoutePreviewMap], an [AlternateRoutesMap], a [SearchPinsMap]
/// and a [DestinationPinMap] too: a [NavigationFlowController] on
/// [session] draws its route options (see [routeLabel],
/// [onRouteOptionTap]) and alternates (see [alternateLabel]) here, and a
/// navigation scaffold its pins.
///
/// ## Under a Google-style scaffold
///
/// A `GoogleStyleFlowScaffold`'s `mapBuilder` can build this view from its
/// `GoogleStyleMapLayers`: [horizontalFocus] from `horizontalFocus`,
/// [bottomInset] from `bottomOverlay`, [routeColors], [routeLabel] and
/// [alternateLabel] from the fields of the same names, and the colours
/// ([labelColors], [alternativeRouteColor], [alternateColor],
/// [fasterLabelColors], [slowerLabelColors], [searchPinColor]) from
/// `colors`. MapLibre has no traffic layer and no satellite map type of its
/// own: both come from the style, so the view ignores `traffic` and
/// `satellite`; an app with a satellite style can pass it as [styleString]
/// when `satellite` is on.
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
    this.labelColors = MapDefaultColors.routeLabels,
    this.alternativeRouteColor = const Color(0xFF9AA0A6),
    this.bottomInset = 0,
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
  /// a footer): the MapLibre attribution button keeps 8 above it
  /// (`attributionButtonMargins`), as the map's data providers require it
  /// to stay visible. The view shows no logo (maplibre_gl's `logoEnabled`
  /// defaults to false); `logoViewMargins` follows all the same.
  final double bottomInset;

  /// Called with the place the user taps on the map
  /// (`MapLibreMap.onMapClick`). A tap on a feature the adapter draws (a
  /// route option or its label, an alternate or its bubble, a search pin or
  /// the destination pin) does not call it: the SDK reports none for it,
  /// and a map tap that comes in the same frame after such a tap, or that
  /// such a tap follows in the same turn of the event loop, is dropped
  /// anyway. A tap is delivered one turn of the event loop after the SDK
  /// reports it, and not once the view is gone. A tap on the route line
  /// itself is a map tap, also where an alternate shares the road (the
  /// alternate's line is drawn only where it differs). A touch on the map
  /// still stops following the vehicle.
  final void Function(GeoPoint point)? onMapTap;

  /// Called with the place the user long-presses on the map
  /// (`MapLibreMap.onMapLongClick`; a double click on the web), wherever it
  /// is, such as to pin a destination of the app's own
  /// ([DestinationPinMap.showDestinationPin]).
  final void Function(GeoPoint point)? onMapLongPress;

  /// Where the followed vehicle sits across the map, as a fraction of the
  /// width (see [NavigationMapFrame.horizontalFocus]). It is physical: 0 is
  /// the left edge in both text directions, so a caller that places it
  /// beside a start-side panel mirrors it in RTL. The camera insets that
  /// move the focus also keep the attribution button (bottom right) clear
  /// of a panel on the right (a focus below 0.5). The view shows no logo
  /// (maplibre_gl's `logoEnabled` defaults to false); its margin (bottom
  /// left) still moves clear of a panel on the left (a focus above 0.5).
  final double horizontalFocus;

  /// The text of the bubble on each alternate route drawn while navigating
  /// (see [MapLibreNavigationMap.alternateLabel]); null draws none.
  /// Forwarded to the map.
  final String Function(AlternateRoute alternate)? alternateLabel;

  /// The colour of the alternate routes drawn while navigating. When null
  /// the map's own colour is kept; forwarded to
  /// [MapLibreNavigationMap.alternateColor].
  final Color? alternateColor;

  /// The bubble colours of a faster alternate route. When null the map's
  /// own are kept; see [MapLibreNavigationMap.setAlternateLabelColors].
  final RouteLabelColors? fasterLabelColors;

  /// The bubble colours of a slower (or as fast) alternate route. When null
  /// the map's own are kept; see
  /// [MapLibreNavigationMap.setAlternateLabelColors].
  final RouteLabelColors? slowerLabelColors;

  /// The colour of the search pins. When null the map's own colour is
  /// kept; forwarded to [MapLibreNavigationMap.pinColor].
  final Color? searchPinColor;

  /// The margin of the attribution button (and of the logo, not shown)
  /// from the map's edges, above [bottomInset] and beside a side panel.
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

  // The SDK keeps the click callbacks of the map's creation: these read the
  // widget's when a click comes.
  void _onMapClick(Point<double> _, LatLng position) {
    if (widget.onMapTap == null) return;
    final point = GeoPoint(position.latitude, position.longitude);
    // Not the map's side of a tap one of the adapter's features took; read
    // the callback when the tap is delivered.
    dispatchMapTap(_map, () => widget.onMapTap?.call(point));
  }

  void _onMapLongClick(Point<double> _, LatLng position) => widget
      .onMapLongPress
      ?.call(GeoPoint(position.latitude, position.longitude));

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
      horizontalFocus: widget.horizontalFocus,
      puck: widget.puck,
      recenterButton: widget.recenterButton,
      mapBuilder: (context, padding) {
        _map.padding = padding;
        return LayoutBuilder(
          builder: (context, constraints) {
            _reportViewport(constraints.biggest);
            return _buildMap(padding);
          },
        );
      },
    );
  }

  /// Where the logo (bottom left; not shown) or the attribution button
  /// (bottom right) sits from its corner: above
  /// [MapLibreNavigationView.bottomInset], and beside the [side] inset of the
  /// focus padding (the panel on that side).
  Point<double> _ornamentMargins(double side) => Point(
    side + MapLibreNavigationView._ornamentMargin,
    widget.bottomInset + MapLibreNavigationView._ornamentMargin,
  );

  Widget _buildMap(EdgeInsets focus) {
    return MapLibreMap(
      styleString: widget._shownStyle,
      initialCameraPosition: CameraPosition(
        target: toLatLng(widget.initialCenter),
        zoom: toSdkZoom(widget.initialZoom),
      ),
      compassEnabled: false,
      myLocationEnabled: false,
      attributionButtonMargins: _ornamentMargins(focus.right),
      logoViewMargins: _ornamentMargins(focus.left),
      onMapClick: _onMapClick,
      onMapLongClick: _onMapLongClick,
      onMapCreated: (c) {
        _map.onMapCreated(c);
        widget.onMapCreated?.call(c);
      },
      onStyleLoadedCallback: _map.onStyleLoaded,
    );
  }
}
