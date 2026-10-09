## 0.1.0

- Initial release.
- `GoogleMapsNavigationView` and `GoogleMapsNavigationMap`: the follow
  camera, the route line (re-drawn when `routeColors` change), the vehicle
  marker rendered at the device pixel ratio (`vehicleImage`), a map
  `style` and an optional recenter button (`showRecenterButton`).
- `GoogleMapsNavigationMap` implements `RoutePreviewMap`: route options
  with duration labels (`routeLabel`, `labelColors`, a `labelPainter`
  seam), the muted ones in `alternativeRouteColor`, selected by a tap
  (`onRouteOptionTap`). Fits honour the map widget's own padding
  (`mapPadding`, set by the view); their camera errors are reported
  through `FlutterError`. It owns the ids `navigation_engine_option_*`.
- `googleStyleNightMapStyle`: a ready-made dark map style.
- `GoogleStyle*` widgets: `GoogleStyleManeuverHeader`,
  `GoogleStyleLaneGuidance`, `GoogleStyleRecenterButton`,
  `GoogleStyleOverviewPanel` (Cancel while loading, `onClose` for a
  preview), `GoogleStyleStepList`, `GoogleStyleTripProgressBar`,
  `GoogleStyleCompassButton` (its glyph follows the camera; a tap
  switches heading up and north up) and `GoogleStyleRoundButton`
  (optional `surface`, `iconColor` and `elevation`), with
  `GoogleStyleColors` (`routeLabelColors`). Large text: the speed and the
  overview card's first line shrink to fit, the turn card's distance and
  the trip sheet's time left are clamped at 1.6x, and the rectangular
  speed limit sign keeps its text size.
- `GoogleStyleNavigation`: a drop-in navigation screen bound to a
  `NavigationFlowController`, built on `NavigationFlowScaffold`: day and
  night colours (`dayRouteColors`, `nightRouteColors`), `puck`,
  `vehicleImage`, `focus`, `initialZoom`, `markers` and `onMapCreated`;
  back handling, a live step list and a guarded Retry. The toggles
  `headerEnabled`, `footerEnabled`, `tripProgressBarEnabled`,
  `speedometerEnabled`, `speedLimitIconEnabled`, `recenterButtonEnabled`,
  `compassEnabled`, `routeOverviewButtonEnabled`, `reportButtonEnabled`
  and `searchButtonEnabled`, and the callbacks `onReportIncident` and
  `onAudioGuidanceChanged` (with `audioGuidance`), follow Google's
  navigation SDK. The app's own back ends plug in through
  `searchAlongRoute` (search along the route), `onAddStop` (a found place
  as a stop; the package adds none itself), `onShareTrip` and `onSettings`
  (their menu rows show only with a callback). Every control stays inside
  the safe area.
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `PlaceLabel`,
  `AlternateRoute`, `AlternateRoutesMap`, `SearchPinsMap`, `RouteColors`,
  `CarPuck`, `VehicleImageBuilder`, `RouteLabelColors`,
  `fitCameraToBounds`, `paintRouteLabel`, `laneDirectionIcon` and the
  Google-style pieces (see below) from navigation_engine_flutter.
- The Google-style UI lives in navigation_engine_flutter, as the
  Mapbox-style UI does: every piece that needs no Google map (the
  `GoogleStyle*` widgets, `GoogleStyleColors`, `AudioGuidance`,
  `IncidentType`, `SpeedLimitSignStyle`, `SpeedingLevel` and the
  `AlongRoute*` types) and the whole screen, `GoogleStyleFlowScaffold`.
  This library re-exports the pieces under the same names, so an app that
  imports only navigation_engine_google_maps compiles and behaves as
  before (one detail: an error the app's `onResults` throws in the search
  along the route is reported with the `FlutterError` library
  `navigation_engine_flutter`, was `navigation_engine_google_maps`).
  `GoogleStyleNavigation` keeps its constructor; it is now
  `GoogleStyleFlowScaffold` with a `GoogleMapsNavigationView` as its map.
  `GoogleStyleFlowScaffold` and `GoogleStyleMapLayers` are not re-exported
  (import navigation_engine_flutter to build the look on another map).
- `GoogleMapsNavigationMap` implements `SearchPinsMap` (it drew the search
  pins before; now through the shared interface).
- The compass shows a heading up / north up switch the app makes at once
  (`FollowCamera.headingUpChanges`); its tooltip is its one accessibility
  label.
- `GoogleStyleTripProgressBar`: the vehicle dot stays inside the bar at 0
  and 1, and an unbounded height gives a 120 high bar.
- `GoogleStyleLaneGuidance` draws the shared `LaneGuidanceRow`.
- The route label border of `GoogleStyleColors.routeLabelColors` is
  `onSurface` at 20 %, visible by day and at night. The label image cache
  drops the least recently used image.
- Google Maps parity for `GoogleStyleNavigation`:
  - a rebuilt `GoogleStyleManeuverHeader` (split distance, bold road,
    a lanes band or a "Then" tab, a tap for the step list, a swipe
    to preview steps in grey, a rerouting spinner, and `.arrival`);
  - the end column (`GoogleStyleControlStack`): the report button, the
    compass, search along the route, the 3-state `GoogleStyleSoundButton`
    (`AudioGuidance`) and route options, dropping by priority when the
    screen is short;
  - `GoogleStyleReportButton` (a pill, then a circle) and
    `GoogleStyleReportSheet` / `showGoogleStyleReportSheet` (`IncidentType`),
    with a "Report sent" toast;
  - `GoogleStyleSpeedCluster` (`SpeedLimitSignStyle.vienna` / `.us`,
    `SpeedingLevel` with `speedingMinor` / `speedingMajor`, a tap on the sign
    toggles the speedometer), replaced by the Re-center pill while it shows;
  - `GoogleStyleTripSheet` (close and route-options circles, the expanded
    menu `GoogleStyleSheetAction`: directions, search, share, traffic,
    satellite, settings) and `GoogleStyleArrivalSheet`; with `floating`
    they, and `GoogleStyleOverviewPanel`, round all four corners, as cards
    in the landscape side panel;
  - the trip progress bar restyled (12 dp, driven grey, remaining blue,
    destination dot), off by default and hidden under 552 dp of height;
  - search along the route: `AlongRouteSearch`, `AlongRouteQuery`,
    `AlongRouteCategory`, `AlongRoutePlace`, `GoogleStyleSearchAlongRoute`,
    `paintSearchPin`, with pins on the map; while it is open the search bar
    takes the header's place (the header and a step preview go, and the
    stack drops its search button), and `onBarHeight` reports the bar's
    height;
  - a landscape side panel (600 dp wide and up) with the follow focus beside
    it; the report button never sits under the sheet.
- Google Maps parity, final fixes:
  - the system back closes the sound pill, then the trip sheet's menu, then
    the search, one per back, before it leaves the screen
    (`GoogleStyleSoundButton.onOpenChanged`,
    `GoogleStyleTripSheet.onExpandedChanged`);
  - `GoogleMapsNavigationView.bottomOverlay` lifts the map padding's bottom
    and top alike, so the Google logo stays above the trip sheet, the speed
    cluster and the Re-center pill while the follow focus stays; the
    drop-in passes `NavigationMapConfig.bottomOverlayHeight`;
  - "Add stop" closes the search and follows again;
  - the search overlay follows night mode while open; shown search pins
    take a new `pinColor` and shown alternate bubbles take new
    `alternateLabel` texts (such as another language);
  - a new route while search results show (a reroute) clears them and runs
    the last search again along it (`GoogleStyleSearchAlongRoute`);
  - the report sheet closes when navigation ends, and no report is filed
    after that;
  - in the landscape side panel the open menu takes the column (the turn
    card hides meanwhile) and a `floating` sheet leaves the rows' cap to
    its parent, so at 915x412 it shows at least 4 rows;
  - a tap on the header's band (the lanes or "Then") opens the step list,
    as the card does; the search field's cursor is the `accent` token; the
    arrival header shows the last road when the destination's name is
    blank.
- Google Maps parity, minor fixes:
  - an alternate's bubble sits at the middle of its own part but at most
    400 m past where it leaves the route
    (`GoogleMapsNavigationMap.alternateLabelLead`), so it shows near the
    car at follow zoom. This refines the spec's "midpoint ahead";
  - a touch on the map during a step preview ends it without following
    again: the preview's timer no longer pulls the camera back mid-pan;
  - the drop-in reads its size from its constraints, as the scaffold
    does, so both agree on the side panel inside a pane narrower than the
    screen;
  - the toast is centred in the map area beside the side panel, and is a
    live region for screen readers;
  - `GoogleStyleTripSheet.backClosesMenu`: a layer above the sheet (such
    as an open sound pill) can keep the back for itself; in the drop-in
    the open menu closes the pill instead;
  - the open report sheet follows a day/night switch;
  - the header's band and "Then" tab are flat like the card, and the
    header has no scroll actions for screen readers, only the step
    actions;
  - the report sheet spans the width it is given and lays out 4 tiles to a
    row on a 360 dp screen; a name wraps between words only, and scales
    down when one word would not fit its tile; the title is a header; the
    report button's
    label ellipsizes in a narrow parent, and a new `collapseAfter`
    starts its countdown again;
  - a search pin's outline lies wholly inside its image; the search's
    progress bar is labelled, its failed and empty messages are live
    regions, and giving or dropping `onBarHeight` keeps the field;
  - every public member has a doc comment (`public_member_api_docs` is
    on).
- `GoogleMapsNavigationMap` implements `AlternateRoutesMap` (grey lines
  under the route, "2 min faster" / "+3 min" bubbles, a tap switches) and
  draws search pins (`showSearchPins`, `clearSearchPins`); it owns the ids
  `navigation_engine_alternate_*` and `navigation_engine_search_*`.
  `GoogleMapsNavigationView` gains `trafficEnabled`, `mapType`,
  `alternateLabel` and `horizontalFocus`.
- `GoogleStyleColors` gains `guidancePreview`, `buttonSurface`,
  `buttonIcon`, `selectedTint`, `onSelectedTint`, `outline`,
  `speedometerSurface`, `speedometerText`, `speeding`, `progressDriven`,
  `compassNorth`, `switchThumb`, `switchTrackOff`, `closeOutline`, and
  `fasterLabelColors` / `slowerLabelColors`. The new tokens are optional:
  a custom `GoogleStyleColors` that leaves them out gets the day values,
  also at night, so a custom night theme should set them.
- Breaking:
  - `onMuteToggle` / `muted` are replaced by `onAudioGuidanceChanged` /
    `audioGuidance`;
  - `onReportIncident` takes an `IncidentType`;
  - `speedLimitSign` is now `speedLimitSignStyle`;
  - `tripProgressBarEnabled` defaults to false;
  - `GoogleStyleTripFooter`, `GoogleStyleArrivalPanel` and
    `GoogleStyleSpeedometer` are removed (use `GoogleStyleTripSheet`,
    `GoogleStyleArrivalSheet` and `GoogleStyleSpeedCluster`);
  - the steps button left the footer: tap the header, or use the sheet's
    Directions row;
  - new toggles: `reportButtonEnabled`, `searchButtonEnabled`;
  - `NavigationStrings.reportIncident` is renamed `report` (in
    navigation_engine_flutter);
  - the drop-in's header now carries the header actions (a tap opens the
    step list, a swipe previews steps), and
    `GoogleStyleManeuverHeader.state` is nullable (null for `.arrival`);
  - the library no longer re-exports `SpeedLimitSign` (the drop-in takes a
    `SpeedLimitSignStyle`).
- The Google look (after screenshots of the Google Maps app):
  - the turn card is teal (`guidance` `#015F61` / night `#014446`, the band
    and the "Then" tab `guidanceSecondary` `#015053` / night `#013436`),
    flat, radius 20; a 48 dp icon with a small distance under it (hidden
    over 1 km on a straight-on step: a continue, new name or turn whose
    modifier is straight or none), the road in 28 w500, vertically
    centred, with "toward" before it on a straight-on step or a depart
    (`NavigationStrings.toward`), and no manoeuvre line; an empty road
    shows the instruction; rerouting uses the road's style;
  - the "Then" tab hangs under the card's bottom-start corner, hugging
    "Then" (24) and the next icon (40, an arrow about 26 across); the
    lanes band is as wide as the card; both are flat, round below (16);
  - `GoogleStyleRoundButton` is a 52 dp white circle (night `#303134`)
    with a 1 dp `outline` ring (an `outline` override) and elevation 1;
    the report button and the open sound pill match it;
  - the compass is a red `compassNorth` triangle over a bold "N", turning
    together;
  - one end column, anchored 16 above the trip sheet (in the side panel
    layout, at the bottom end of the map area) and growing upwards: the
    report button, the compass, search, sound and route options, top to
    bottom; while searching it hangs under the search bar. The
    route-options button moved there from the trip sheet
    (`routeOverviewButtonEnabled` governs it; hidden while searching),
    and the drop-in's sheet no longer has the fork. A short column drops
    search, then sound, then the compass, then the report, so route
    options stay reachable (`GoogleStyleControlStack.priorities`,
    `GoogleStyleControlStack.keep`). When a row would meet the speed
    cluster or the Re-center pill (a wide pill in the bottom row), the
    column lifts to end 16 above them (by their last laid size). Opening
    or closing the search keeps the members' state. The drop-in has no
    bottom end piece any more;
  - while the trip sheet's menu is open, the end column, the speed
    cluster or Re-center hide, as in Google Maps (an open sound pill
    closes);
  - the speedometer alone (no limit sign) is a 58 dp white circle;
  - the trip sheet: the time left in 24 w500 over "distance • arrival" in
    16; the close circle is white with a darker `closeOutline` ring; the
    menu rows are 64 dp, in Google's order (share, search, directions,
    traffic, satellite, settings), with grey 18 labels, dark icons, inset
    dividers, and a trailing classic switch drawn by the package (a large
    thumb with a soft shadow; on: `accent`) for the traffic and satellite
    toggles (instead of a check); a toggle row flips in place, the menu
    staying open.
- Trip sheet drag (`GoogleStyleTripSheet`): the sheet follows the finger,
  its height interpolated between the collapsed and the expanded height by
  the expanded fraction t, the menu clipped to it and fading in with t (its
  rows take taps only at t = 1). A release settles with a spring: a fling
  (200 dp/s or more) goes its way, a slower release goes to the nearer
  state (past halfway opens; under 32 dp it goes back). This replaces the
  old rule where any slow drag of 32 dp opened or closed it. A tap on the
  handle (new) or the time animates it in 250 ms, easing out; the system
  back closes it animated. `onExpandedChanged` now fires once the sheet
  settles; the new `onFractionChanged` reports t on every frame. A tap
  outside or a menu action still closes it at once.
- The drop-in's floating controls (the end column with Report, the speed
  cluster and Re-center) fade out with t and ignore pointers once t > 0,
  hidden at t = 1, instead of hiding at once. While t > 0 they keep their
  collapsed geometry and members (the sound button stays; its pill closes),
  so they fade in place under the rising sheet; in the landscape side panel
  the turn card gives way as soon as the sheet leaves its collapsed height,
  so the floating sheet grows upwards without a jump. While the sheet is
  not collapsed the map view keeps the bottom overlay of the collapsed
  sheet, so the camera's focus and the map padding do not move.
- `GoogleStyleSoundButton.canOpen` (default true): while false the pill
  closes and does not open.
- A drag that grabs the trip sheet mid-animation keeps the way it was
  heading on a slow release under 32 dp.
- The "Then" tab now shows on a straight-on step for the next manoeuvre
  however far it is (`NavGuidance`'s new rule, from the core); lanes still
  take the band first.
