## 0.1.0

- Initial release: `NavigationMapFrame`, `VehicleMarkerMap`,
  `NavigationBanner`, `CarPuck`, `maneuverIcon`, `focusPadding`,
  `RouteColors`, GeoJSON helpers.
- `CarPuck.renderPng` and `vehicleImageFor` render the vehicle image for
  native map markers; `NavigationMapFrame.recenterTooltip` sets the recenter
  button tooltip.
- `NavigationFlowController` (states `FlowIdle`, `FlowLoading`,
  `FlowOverview`, `FlowNavigating`, `FlowArrived`, `FlowError`),
  `TripProgress`, `SpeedInfo`, `NightMode` and the `RoutePreviewMap`
  interface for route-overview maps.
- `NavigationFlowController.cancel()` leaves `FlowLoading` or `FlowError`
  for the state before the request; `FlowError.to` is the requested
  destination, for a retry.
- `NavigationFlowController.refreshOverview()` redraws the overview on a
  newly attached map; setting `overviewPadding` re-fits it.
- `NavigationFlowController.isTripOverview` is true for the running trip's
  own overview (entered through `backToOverview`), signaling that a UI shows
  'Resume' instead of 'Start'.
- `NavigationFlowController.retry()` repeats the failed `preview()` request
  with its origin, heading and alternatives.
- `NavigationFlowController.closeOverview()` leaves a route preview
  (not the trip overview) for `FlowIdle`, leaving the session alone.
