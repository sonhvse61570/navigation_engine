## 0.1.0

- Initial release: `GoogleMapsNavigationView`, `GoogleMapsNavigationMap`.
- `vehicleImage` renders the vehicle marker at the device pixel ratio.
- `routeColors` changes redraw the route.
- `GoogleMapsNavigationMap` implements `RoutePreviewMap`: route options with duration labels, selection by tap, and fitting the camera to the routes. It owns the ids `navigation_engine_option_*`.
- `fitCameraToBounds` computes the camera that shows a set of points inside a padded viewport.
- `paintRouteLabel` renders the duration label bubble of a route option.
- `GoogleMapsNavigationView` gains `style`, `showRecenterButton`, `routeLabel`, `onRouteOptionTap` and `alternativeRouteColor`.
- `googleStyleNightMapStyle` is a ready-made dark map style.
- `GoogleStyle*` widgets: `GoogleStyleManeuverHeader`, `GoogleStyleLaneGuidance`, `GoogleStyleTripFooter`, `GoogleStyleSpeedometer`, `GoogleStyleRecenterButton`, `GoogleStyleOverviewPanel`, `GoogleStyleStepList` and `GoogleStyleArrivalPanel`, with `GoogleStyleColors`, `GoogleStyleStrings` (and `.vietnamese()`) and `SpeedLimitSign`.
- `GoogleStyleNavigation`: a drop-in navigation screen bound to a `NavigationFlowController`.
- `fitCameraToBounds` takes `mapPadding` (the map widget's own padding):
  the overview fit shows the routes in the middle of the padded viewport
  even when `GoogleMap.padding` moves the camera target.
  `GoogleMapsNavigationMap.mapPadding` is set by the view from its focus
  padding.
- `GoogleMapsNavigationMap.labelColors` (and the view's `labelColors`):
  route option labels in the theme's colours; the `labelPainter` seam gets
  the colours.
- Camera errors of route fits are reported through `FlutterError`.
- `GoogleStyleOverviewPanel`: a Cancel button while loading, and `onClose`
  (a close button) for a route preview.
- `GoogleStyleSpeedometer.formatter`: speeds and limits through
  `GuidanceFormatter.speedValue` / `speedUnit`.
- Large text: the speed bubble and the overview card's first line shrink to
  fit, the turn card's distance and the footer's time left are clamped at
  1.6×, and the rectangular speed limit sign keeps its normal text size.
- `GoogleStyleNavigation`: `dayRouteColors`, `nightRouteColors`, `puck`,
  `vehicleImage`, `focus` and `initialZoom`; the route lines and labels
  follow the day/night colours; back handling (cancel, close a preview,
  resume the trip); a live step list that closes when the flow moves on;
  a guarded Retry; progress ticks no longer rebuild the map view.
