import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import '../google_maps_navigation_view.dart';
import 'night_map_style.dart';

/// A complete navigation screen in the style of the Google Maps app, bound
/// to [flow] and [session]: the map, the route overview, turn-by-turn
/// guidance and the arrival, in portrait and landscape, by day and night.
///
/// Per [NavigationFlowController.state]:
/// - **Idle:** [idleBuilder]'s overlay.
/// - **Loading, overview, error:** [GoogleStyleOverviewPanel].
/// - **Navigating:**
///   - [GoogleStyleManeuverHeader] at the top. A tap opens the step list
///     and a swipe previews the next step (Re-center ends the preview).
///   - The end column, anchored 16 above the trip sheet and growing
///     upwards: the report button, the compass, the search button, the
///     3-state sound button and the route-options button (the trip
///     overview with the alternates). A short column drops search, then
///     sound, then the compass, then the report; route options stay.
///   - The speed cluster at the bottom start, replaced by the Re-center
///     pill once the map is moved.
///   - [GoogleStyleTripSheet] at the bottom, with its close circle and its
///     menu (share, search along the route, directions, traffic and
///     satellite switches, settings).
///   - Alternate routes on the map with their time bubbles; a tap switches
///     to one.
/// - **Arrived:** the arrival header and [GoogleStyleArrivalSheet].
///
/// On a landscape screen at least 600 dp wide, the header and the sheet go
/// to a side panel on the start side ([NavigationFlowScaffold.landscapeSidePanel]).
///
/// A control shows when its toggle is on and its callback exists:
/// - [headerEnabled], [footerEnabled], [tripProgressBarEnabled] (off by
///   default);
/// - [speedometerEnabled], [speedLimitIconEnabled], [recenterButtonEnabled],
///   [compassEnabled], [routeOverviewButtonEnabled];
/// - [reportButtonEnabled] with [onReportIncident], [searchButtonEnabled]
///   with [searchAlongRoute];
/// - the sound button with [onAudioGuidanceChanged].
///
/// The app owns the audio ([audioGuidance]), reports, search and stops; the
/// library adds no stop itself.
///
/// The map is a [GoogleMapsNavigationView]; the flow binding is a
/// [NavigationFlowScaffold]. The app owns, starts and disposes [session] and
/// [flow].
class GoogleStyleNavigation extends StatefulWidget {
  /// Creates the navigation screen for [session] driven by [flow].
  const GoogleStyleNavigation({
    super.key,
    required this.session,
    required this.flow,
    required this.initialCenter,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.dayColors = GoogleStyleColors.day,
    this.nightColors = GoogleStyleColors.night,
    this.nightMapStyle = googleStyleNightMapStyle,
    this.speedLimitSignStyle = SpeedLimitSignStyle.vienna,
    this.speedingMinor,
    this.speedingMajor,
    this.idleBuilder,
    this.onEnd,
    this.markers = const {},
    this.onMapCreated,
    this.dayRouteColors,
    this.nightRouteColors,
    this.puck = const CarPuck(),
    this.vehicleImage,
    this.focus = 0.7,
    this.initialZoom = 17,
    this.headerEnabled = true,
    this.footerEnabled = true,
    this.tripProgressBarEnabled = false,
    this.speedometerEnabled = true,
    this.speedLimitIconEnabled = true,
    this.recenterButtonEnabled = true,
    this.compassEnabled = true,
    this.routeOverviewButtonEnabled = true,
    this.reportButtonEnabled = true,
    this.searchButtonEnabled = true,
    this.audioGuidance = AudioGuidance.sound,
    this.onAudioGuidanceChanged,
    this.onReportIncident,
    this.searchAlongRoute,
    this.onAddStop,
    this.onShareTrip,
    this.onSettings,
  });

  /// The session shown on the map. Owned by the app.
  final NavigationSession session;

  /// The flow whose state the screen shows. Owned by the app.
  final NavigationFlowController flow;

  /// Where the map is centred before the first camera move.
  final GeoPoint initialCenter;

  /// Formats the instructions, distances, durations, times and speeds.
  final GuidanceFormatter formatter;

  /// The words of the screen.
  final NavigationStrings strings;

  /// The colours used while [NavigationFlowController.isNight] is false.
  final GoogleStyleColors dayColors;

  /// The colours used while [NavigationFlowController.isNight] is true.
  final GoogleStyleColors nightColors;

  /// The map style used at night; null keeps the default map look.
  final String? nightMapStyle;

  /// The shape of the speed limit sign.
  final SpeedLimitSignStyle speedLimitSignStyle;

  /// Over the limit by this much (in the formatter's unit) is a minor
  /// speeding alert; see [GoogleStyleSpeedCluster.speedingLevel].
  final double? speedingMinor;

  /// Over the limit by this much is a major speeding alert.
  final double? speedingMajor;

  /// Builds the overlay shown while the flow is idle, such as a search bar.
  final WidgetBuilder? idleBuilder;

  /// Called by the close circle and the arrival's done button; when null
  /// they call [NavigationFlowController.stop].
  final VoidCallback? onEnd;

  /// The app's own markers, drawn on the map.
  final Set<Marker> markers;

  /// Called when the map controller is created, after the route overview is
  /// drawn on the new map.
  final void Function(GoogleMapController controller)? onMapCreated;

  /// The route line colours by day; when null, `RouteColors(driven:
  /// alternative, ahead: accent)` of [dayColors].
  final RouteColors? dayRouteColors;

  /// The route line colours at night; when null, from [nightColors].
  final RouteColors? nightRouteColors;

  /// The vehicle while the camera follows it; see
  /// [GoogleMapsNavigationView.puck].
  final Widget puck;

  /// Renders the vehicle marker drawn by the map; see
  /// [GoogleMapsNavigationView.vehicleImage].
  final VehicleImageBuilder? vehicleImage;

  /// Where the vehicle sits on the screen while followed, as a fraction of
  /// the height; see [GoogleMapsNavigationView.focus].
  final double focus;

  /// The zoom of the map before the first camera move.
  final double initialZoom;

  /// Whether the turn card shows.
  final bool headerEnabled;

  /// Whether the trip sheet shows while navigating.
  final bool footerEnabled;

  /// Whether the trip progress bar shows on the start edge (on screens at
  /// least 552 dp high). Off by default, as in Google's navigation SDK.
  final bool tripProgressBarEnabled;

  /// Whether the speedometer may show.
  final bool speedometerEnabled;

  /// Whether the speed limit sign may show.
  final bool speedLimitIconEnabled;

  /// Whether the Re-center pill shows once the user has moved the map.
  final bool recenterButtonEnabled;

  /// Whether the compass shows while the camera follows the vehicle.
  final bool compassEnabled;

  /// Whether the end column has its route-options button.
  final bool routeOverviewButtonEnabled;

  /// Whether the report button shows (with [onReportIncident]).
  final bool reportButtonEnabled;

  /// Whether the search button shows in the end column (with
  /// [searchAlongRoute]).
  final bool searchButtonEnabled;

  /// The audio state the sound button shows. Owned by the app.
  final AudioGuidance audioGuidance;

  /// Called with the audio state chosen in the sound pill; the sound button
  /// is hidden when null.
  final ValueChanged<AudioGuidance>? onAudioGuidanceChanged;

  /// Called with the incident chosen in the report sheet; the report button
  /// is hidden when null.
  final ValueChanged<IncidentType>? onReportIncident;

  /// Searches for places along the route; the search button and menu row
  /// are hidden when null.
  final AlongRouteSearch? searchAlongRoute;

  /// Called by the search's "Add stop" button; it is hidden when null.
  /// Afterwards the search closes and the camera follows again.
  final ValueChanged<AlongRoutePlace>? onAddStop;

  /// Called by the menu's "Share trip progress" row; hidden when null.
  final VoidCallback? onShareTrip;

  /// Called by the menu's "Settings" row; hidden when null.
  final VoidCallback? onSettings;

  @override
  State<GoogleStyleNavigation> createState() => _GoogleStyleNavigationState();
}

class _GoogleStyleNavigationState extends State<GoogleStyleNavigation> {
  /// Keeps the map view, and so the platform map, across rebuilds.
  final _mapKey = GlobalKey();

  @override
  Widget build(BuildContext context) => GoogleStyleFlowScaffold(
    session: widget.session,
    flow: widget.flow,
    formatter: widget.formatter,
    strings: widget.strings,
    dayColors: widget.dayColors,
    nightColors: widget.nightColors,
    dayRouteColors: widget.dayRouteColors,
    nightRouteColors: widget.nightRouteColors,
    speedLimitSignStyle: widget.speedLimitSignStyle,
    speedingMinor: widget.speedingMinor,
    speedingMajor: widget.speedingMajor,
    idleBuilder: widget.idleBuilder,
    onEnd: widget.onEnd,
    headerEnabled: widget.headerEnabled,
    footerEnabled: widget.footerEnabled,
    tripProgressBarEnabled: widget.tripProgressBarEnabled,
    speedometerEnabled: widget.speedometerEnabled,
    speedLimitIconEnabled: widget.speedLimitIconEnabled,
    recenterButtonEnabled: widget.recenterButtonEnabled,
    compassEnabled: widget.compassEnabled,
    routeOverviewButtonEnabled: widget.routeOverviewButtonEnabled,
    reportButtonEnabled: widget.reportButtonEnabled,
    searchButtonEnabled: widget.searchButtonEnabled,
    audioGuidance: widget.audioGuidance,
    onAudioGuidanceChanged: widget.onAudioGuidanceChanged,
    onReportIncident: widget.onReportIncident,
    searchAlongRoute: widget.searchAlongRoute,
    onAddStop: widget.onAddStop,
    onShareTrip: widget.onShareTrip,
    onSettings: widget.onSettings,
    mapBuilder: (context, config, layers) => GoogleMapsNavigationView(
      key: _mapKey,
      session: widget.session,
      initialCenter: widget.initialCenter,
      initialZoom: widget.initialZoom,
      routeColors: layers.routeColors,
      puck: widget.puck,
      vehicleImage: widget.vehicleImage,
      focus: widget.focus,
      horizontalFocus: layers.horizontalFocus,
      // Keeps the Google logo above the sheet, the speed and Re-center.
      bottomOverlay: layers.bottomOverlay,
      style: config.isNight ? widget.nightMapStyle : null,
      markers: widget.markers,
      // The scaffold shows the recenter button.
      showRecenterButton: false,
      trafficEnabled: layers.traffic,
      mapType: layers.satellite ? MapType.hybrid : MapType.normal,
      routeLabel: layers.routeLabel,
      alternateLabel: layers.alternateLabel,
      onRouteOptionTap: config.onRouteOptionTap,
      alternativeRouteColor: layers.colors.alternative,
      labelColors: layers.colors,
      onMapCreated: (controller) {
        config.onMapReady();
        widget.onMapCreated?.call(controller);
      },
    ),
  );
}
