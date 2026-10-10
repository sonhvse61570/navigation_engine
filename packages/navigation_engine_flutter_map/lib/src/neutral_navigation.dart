import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'flutter_map_navigation_view.dart';

/// A complete navigation screen on flutter_map, themed by the app: the map,
/// the route overview, turn-by-turn guidance and the arrival, bound to
/// [flow] and [session].
///
/// It shows, per [NavigationFlowController.state]:
/// - idle: [idleBuilder]'s overlay, or nothing;
/// - loading, overview, error: [MapboxStyleRoutePanel] at the bottom;
/// - navigating: [MapboxStyleManeuverBanner] at the top (once there is
///   guidance), [MapboxStyleSpeedLimit] at the bottom start,
///   [MapboxStyleTripProgress] at the bottom, and
///   [MapboxStyleRecenterButton] at the bottom end once the user has moved
///   the map;
/// - arrived: [MapboxStyleArrivalPanel].
///
/// The colours come from the app's [Theme]: by day
/// `MapboxStyleColors.fromColorScheme(Theme.of(context).colorScheme)`, at
/// night the same of the dark [ColorScheme.fromSeed] of the theme's primary
/// colour. [dayColors] / [nightColors] replace them. They reach the panels,
/// the banner, the route lines and the route option labels.
/// [dayRouteColors] / [nightRouteColors] override the selected option and
/// the session's route line; the other options use
/// [MapboxStyleColors.alternative].
///
/// While navigating, the alternates the flow finds are drawn in
/// [MapboxStyleColors.alternative], each with a bubble worded by [strings]
/// ([NavigationStrings.minFaster], [NavigationStrings.minSlower],
/// [NavigationStrings.similarEta]): the text in the accent colour for a
/// faster one, in the muted text colour otherwise, on the surface; a tap on
/// one switches to it. Search pins are drawn in [MapboxStyleColors.warning],
/// and the destination pin at the end of the route. [onMapTap] and
/// [onMapLongPress] give the app the taps on the map itself.
///
/// The map is a [FlutterMapNavigationView] with the [tileUrlTemplate] tiles
/// ([nightTileUrlTemplate] at night, when set): it attaches itself to
/// [session] and ticks it while on screen. Its [attribution] stays above
/// the panels. The pieces and the flow binding
/// (the states, the back, the overview padding, the step sheet, the
/// recenter) are a [MapboxStyleFlowScaffold]. The app owns, starts and
/// disposes [session] and [flow].
class NeutralNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const NeutralNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    required this.userAgentPackageName,
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.nightTileUrlTemplate,
    this.attribution = 'OpenStreetMap contributors',
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors,
    this.nightColors,
    this.speedLimitSign = SpeedLimitSign.circular,
    this.idleBuilder,
    this.onEnd,
    this.dayRouteColors,
    this.nightRouteColors,
    this.puck = const CarPuck(),
    this.focus = 0.7,
    this.initialZoom = 17,
    this.onMapReady,
    this.children = const [],
    this.onMapTap,
    this.onMapLongPress,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// Sent as the tile requests' user agent, as tile servers require; see
  /// [FlutterMapNavigationView.userAgentPackageName].
  final String userAgentPackageName;

  /// The tile URL template (by default OpenStreetMap's).
  final String tileUrlTemplate;

  /// The tile URL template used at night. When null, [tileUrlTemplate] is
  /// used at night too.
  final String? nightTileUrlTemplate;

  /// The tiles' attribution, shown on the map above the panels; see
  /// [FlutterMapNavigationView.attribution]. Change it with
  /// [tileUrlTemplate] to what the tile provider requires.
  final String attribution;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  /// When null they come from the theme's [ColorScheme]
  /// ([MapboxStyleColors.fromColorScheme]).
  final MapboxStyleColors? dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  /// When null they come from the dark [ColorScheme.fromSeed] of the
  /// theme's primary colour. Apps with a `darkTheme` should pass
  /// `MapboxStyleColors.fromColorScheme(darkTheme.colorScheme)`.
  final MapboxStyleColors? nightColors;

  /// The shape of the speed limit sign.
  final SpeedLimitSign speedLimitSign;

  /// Builds the overlay shown while the flow is idle, such as a search bar;
  /// it fills the screen above the map. Nothing is shown when null.
  final WidgetBuilder? idleBuilder;

  /// Called by the end button and by the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// The route line colours by day. When null they come from the day
  /// colours: `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? dayRouteColors;

  /// The route line colours at night. When null they come from the night
  /// colours: `RouteColors(driven: alternative, ahead: accent)`.
  final RouteColors? nightRouteColors;

  /// The vehicle drawn on the map; see [FlutterMapNavigationView.puck].
  final Widget puck;

  /// Where the vehicle sits on the screen while followed; see
  /// [FlutterMapNavigationView.focus].
  final double focus;

  /// The zoom of the map before the first camera move.
  final double initialZoom;

  /// Called once the map is ready, with its controller, after the route
  /// overview is drawn on it; see [FlutterMapNavigationView.onMapReady].
  final void Function(MapController controller)? onMapReady;

  /// The app's own layers (markers, polygons, …), drawn above the route;
  /// see [FlutterMapNavigationView.children].
  final List<Widget> children;

  /// Called with the place the user taps on the map, but not on what the
  /// screen draws (a route option, an alternate, a pin); see
  /// [FlutterMapNavigationView.onMapTap].
  final void Function(GeoPoint point)? onMapTap;

  /// Called with the place the user long-presses on the map, such as to pin
  /// a destination of the app's own while idle; see
  /// [FlutterMapNavigationView.onMapLongPress].
  final void Function(GeoPoint point)? onMapLongPress;

  @override
  State<NeutralNavigation> createState() => _NeutralNavigationState();
}

class _NeutralNavigationState extends State<NeutralNavigation> {
  /// Keeps the map view, and so the map, across rebuilds.
  final _mapKey = GlobalKey();

  // The theme's colours, by day and at night; derived again only when the
  // theme's scheme changes.
  ColorScheme? _scheme;
  late MapboxStyleColors _themeDay;
  late MapboxStyleColors _themeNight;

  void _syncTheme(ColorScheme scheme) {
    if (scheme == _scheme) return;
    _scheme = scheme;
    _themeDay = MapboxStyleColors.fromColorScheme(scheme);
    _themeNight = MapboxStyleColors.fromColorScheme(
      ColorScheme.fromSeed(
        seedColor: scheme.primary,
        brightness: Brightness.dark,
      ),
    );
  }

  // A method, not a closure: its tear-off stays equal across builds.
  String _alternateLabel(AlternateRoute alternate) =>
      alternateRouteLabel(alternate, widget.strings);

  @override
  Widget build(BuildContext context) {
    _syncTheme(Theme.of(context).colorScheme);
    return MapboxStyleFlowScaffold(
      session: widget.session,
      flow: widget.flow,
      formatter: widget.formatter,
      strings: widget.strings,
      dayColors: widget.dayColors ?? _themeDay,
      nightColors: widget.nightColors ?? _themeNight,
      dayRouteColors: widget.dayRouteColors,
      nightRouteColors: widget.nightRouteColors,
      speedLimitSign: widget.speedLimitSign,
      idleBuilder: widget.idleBuilder,
      onEnd: widget.onEnd,
      mapBuilder: (context, config, colors, routeColors, routeLabel) {
        final alternateColors = alternateLabelColorsOf(colors);
        return ValueListenableBuilder<double>(
          valueListenable: config.bottomOverlayHeight,
          builder: (context, bottomInset, _) => FlutterMapNavigationView(
            key: _mapKey,
            session: widget.session,
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            userAgentPackageName: widget.userAgentPackageName,
            tileUrlTemplate: widget.tileUrlTemplate,
            nightTileUrlTemplate: widget.nightTileUrlTemplate,
            attribution: widget.attribution,
            night: config.isNight,
            routeColors: routeColors,
            puck: widget.puck,
            focus: widget.focus,
            // The scaffold shows the recenter button.
            recenterButton: (_) => const SizedBox.shrink(),
            routeLabel: routeLabel,
            onRouteOptionTap: config.onRouteOptionTap,
            labelColors: colors.routeLabelColors,
            alternativeRouteColor: colors.alternative,
            alternateLabel: _alternateLabel,
            alternateColor: colors.alternative,
            fasterLabelColors: alternateColors.faster,
            slowerLabelColors: alternateColors.slower,
            searchPinColor: colors.warning,
            onMapTap: widget.onMapTap,
            onMapLongPress: widget.onMapLongPress,
            onMapReady: (controller) {
              config.onMapReady();
              widget.onMapReady?.call(controller);
            },
            // The attribution keeps above the panels.
            bottomInset: bottomInset,
            children: widget.children,
          ),
        );
      },
    );
  }
}
