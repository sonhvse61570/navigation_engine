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
