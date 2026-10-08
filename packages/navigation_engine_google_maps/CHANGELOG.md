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
  `GoogleStyleLaneGuidance`, `GoogleStyleTripFooter`,
  `GoogleStyleSpeedometer` (`formatter`, `showSpeed`, `showLimit`),
  `GoogleStyleRecenterButton`, `GoogleStyleOverviewPanel` (Cancel while
  loading, `onClose` for a preview), `GoogleStyleStepList`,
  `GoogleStyleArrivalPanel`, `GoogleStyleTripProgressBar`,
  `GoogleStyleCompassButton` (its needle follows the camera; a tap
  switches heading up and north up) and `GoogleStyleRoundButton`, with
  `GoogleStyleColors` (`routeLabelColors`). Large text: the speed bubble
  and the overview card's first line shrink to fit, the turn card's
  distance and the footer's time left are clamped at 1.6x, and the
  rectangular speed limit sign keeps its text size.
- `GoogleStyleNavigation`: a drop-in navigation screen bound to a
  `NavigationFlowController`, built on `NavigationFlowScaffold`: day and
  night colours (`dayRouteColors`, `nightRouteColors`), `puck`,
  `vehicleImage`, `focus`, `initialZoom`, `markers` and `onMapCreated`;
  back handling, a live step list and a guarded Retry. The toggles
  `headerEnabled`, `footerEnabled`, `tripProgressBarEnabled`,
  `speedometerEnabled`, `speedLimitIconEnabled`, `recenterButtonEnabled`,
  `compassEnabled` and `routeOverviewButtonEnabled`, and the callbacks
  `onMuteToggle` (with `muted`) and `onReportIncident`, follow Google's
  navigation SDK. The recenter button sits at the bottom start, above the
  speedometer; every control stays inside the safe area.
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`,
  `RouteColors`, `CarPuck`, `VehicleImageBuilder`, `RouteLabelColors`,
  `fitCameraToBounds`, `paintRouteLabel` and `laneDirectionIcon` from
  navigation_engine_flutter.
