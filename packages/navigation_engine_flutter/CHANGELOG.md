## 0.1.0

- Initial release.
- `NavigationMapFrame`: ticks a `NavigationSession` every display frame,
  keeps the vehicle at a focus point (`focusPadding`), stops following on a
  touch, offers a recenter button (`recenterTooltip`) and pauses the
  session in the background. While following, the puck points the
  vehicle's way: up when the camera is heading up, turned by the vehicle's
  bearing when it is north up.
- `CarPuck`, with `renderPng`, `toPngBytes` and `vehicleImageFor` for the
  vehicle image of native map markers; `VehicleMarkerMap`.
- `NavigationBanner`, `maneuverIcon`, `RouteColors` and GeoJSON helpers.
- `NavigationFlowController`: the states `FlowIdle`, `FlowLoading`,
  `FlowOverview`, `FlowNavigating`, `FlowArrived` and `FlowError`, with
  `TripProgress`, `SpeedInfo` and `NightMode`. `retry()` repeats the
  failed request (`FlowError.to` is its destination); `cancel()` returns
  to the state before the request; `closeOverview()` leaves a route
  preview; `isTripOverview` marks the running trip's own overview (a UI
  shows "Resume" there); `refreshOverview()` redraws the overview on a
  newly attached map; setting `overviewPadding` re-fits it.
- `RoutePreviewMap`: the interface of maps that show route options.
- `NavigationFlowScaffold`: the flow binding of a navigation screen
  without a look, with `NavigationMapConfig` for the map builder. It
  switches the pieces by state, guards the `NavigationFlowActions`, maps
  the back button, shows a live step sheet, offers top end and edge slots
  (bounded widths) and builds the map apart from progress ticks.
- `NavigationFlowScaffold` keeps every piece inside the safe area (start
  and end follow the text direction); the overview padding adds the
  panel's height and the top and side insets.
  `NavigationMapConfig.bottomOverlayHeight` gives the map the height of
  the panel, footer or arrival panel (with the speed's band while the
  speed shows), so the map keeps its attribution in view.
- The recenter button (`recenterBuilder`, nullable) stacks above the speed
  at the bottom start. At any other `recenterAlignment` it sits beside the
  speed, or above the speed's band when the two would share a row, and
  its region is never lower than a 48 dp touch target.
- Shared UI vocabulary for the map adapters: `laneDirectionIcon`,
  `SpeedLimitSign`, `fitCameraToBounds`, `paintRouteLabel` with
  `RouteLabelColors`, the `RouteLabelBubble` widget (it ignores the app's
  text scale, like the painted label) and `NavigationStrings` (with
  `.vietnamese()`).
- Mapbox-style pieces: `MapboxStyleManeuverBanner`,
  `MapboxStyleRoutePanel`, `MapboxStyleTripProgress`,
  `MapboxStyleSpeedLimit`, `MapboxStyleRecenterButton`,
  `MapboxStyleStepList` and `MapboxStyleArrivalPanel`, coloured by
  `MapboxStyleColors` (`day`, `night`, `fromColorScheme`,
  `routeLabelColors`). An original palette inspired by Mapbox's
  navigation apps; not an official Mapbox product.
- `MapboxStyleFlowScaffold`: `NavigationFlowScaffold` dressed with the
  Mapbox-style pieces, the shared screen of the adapters' Mapbox-style
  drop-ins. Its `mapBuilder` gets the colours, the route line colours and
  the route label of the moment.
- `NavigationFlowScaffold.headerBuilder` gets the guarded
  `NavigationFlowActions`, as `topEndBuilder` does.
- The scaffold shows a follow change through
  `NavigationSession.followChanges`, without waiting for a frame or a
  touch. The step sheet's background (`stepSheetColor`) and list follow
  the night mode while the sheet is open.
- The speed and the recenter button share one bottom: the footer or the
  bottom inset, whichever is higher, plus 16. At the bottom start the
  recenter button sits beside the speed where the stack would reach into
  the header, and is hidden where neither fits; it comes back once it
  fits.
- `recenterAlignment` is directional: in a right-to-left app the recenter
  button mirrors (bottom end is the bottom left).
- `LaneGuidanceRow`: the lane arrows of the styled banners.
- `MapboxStyleColors.day` text meets WCAG AA (4.5:1): the accent is
  `#2F5DE0` and the warning `#CF3339` (the end marker keeps `#E5484D`).
- `MapboxStyleColors` has `==` and `hashCode`; its `routeLabelColors`
  border is `onSurface` at 20 %, visible by day and at night.
- `NavigationStrings.copyWith`.
- `MapboxStyleTripProgress` shrinks the time left to half size at most,
  then ellipsizes it.
- `NavigationStrings`: the Google parity words (report and the 8
  incidents, sound states, search along the route, the trip menu, the
  alternate labels `minFaster` / `minSlower` / `similarEta`, `nextStep`,
  `previousStep`), in English and Vietnamese. Breaking: `reportIncident` is
  renamed `report`.
- `PlaceLabel`, and `destination` on `preview`, `previewRoutes`,
  `FlowOverview`, `FlowNavigating` and `FlowArrived`.
- Step preview: `NavigationFlowController.previewStep`, `endStepPreview`,
  `previewedStep` and `stepPreviewTimeout` (10 s); the camera moves once to
  the step (zoom 17, tilt 45), and a Re-center, a reroute, an alternate,
  arrival or stop ends it.
- Alternate routes while navigating: `alternates` (`AlternateRoute` with
  `timeDelta`, `divergence` and `minutesDelta`), `selectAlternate`,
  `refreshAlternates`; alternates are kept from the overview, dropped 20 m
  past where they leave the route (30 m apart), and fetched again after a
  reroute. Every drop-in's trip overview lists them after the current
  route (the alternates are flow data). Maps that implement the new
  `AlternateRoutesMap` draw them. Where an alternate leaves the route is
  found with a snap window that moves along the shared road, so a long
  shared stretch does not stall the UI.
- `NavigationFlowScaffold`: opt-in `recenterReplacesSpeed`,
  `bottomEndBuilder`, `arrivalHeaderBuilder` and `landscapeSidePanel`
  (`usesSidePanel`, `sidePanelWidth`); the top end slot is now bounded above
  the bottom end piece or the footer; a map-ready call also refreshes the
  alternates. `NavigationMapConfig.startOverlayWidth`. With the side panel,
  `bottomOverlayHeight` is the height of the speed and recenter group in
  the map area, and the footer may take the room an empty header leaves
  beyond its 60 % share of the column.
- `focusPadding(horizontal:)` and `NavigationMapFrame.horizontalFocus`.
- Minor fixes after the Google Maps parity work:
  - `NavigationFlowController.fetchAlternatesOnReroute` (default true):
    each reroute costs one more `routes(maxAlternatives: 2)` request for
    the alternates; false saves it;
  - `endStepPreview(refollow: false)` ends a preview without following
    again, for a touch on the map during a preview;
  - `selectAlternate`, and a Resume on another route of the trip overview,
    place the vehicle on the new route by where the two routes share the
    road, so a refetched alternate (which starts where the vehicle was)
    gets the right progress at once, and its time difference is right
    before the switch; the route left stays an alternate while it lies
    ahead of the vehicle;
  - where an alternate leaves the route is measured on the pass of the
    route it follows: on a U-turn or a loop a match on an earlier pass is
    never taken;
  - with `recenterReplacesSpeed`, `bottomOverlayHeight` counts the
    recenter button in the bottom layout as it counts the speed;
  - every public member has a doc comment (`public_member_api_docs` is
    on).
- `NavigationStrings.toward` ("toward" / "hướng về", in `copyWith`): the
  word before a road the route heads for. The traffic and satellite
  labels are now "Show traffic on map" / "Hiện giao thông trên bản đồ" and
  "Show satellite map" / "Hiện bản đồ vệ tinh".
- `NavigationBanner` and the Mapbox-style banner show the core's new "Then"
  step as they are: on a straight-on step they now show the next manoeuvre
  however far it is, and otherwise one within 300 m
  (`NavGuidance.thenWithin`, was 100 m), consistent with the Google-style
  header. When that step is the arrival, the Mapbox-style banner shows it
  with the flag and `NavigationBanner` still leaves it out. Speech is
  unchanged (`NavGuidance.spokenThenWithin`, 100 m).
