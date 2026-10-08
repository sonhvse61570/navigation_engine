## 0.1.0

- Initial release.
- `MapLibreNavigationView` and `MapLibreNavigationMap`: the follow camera,
  the route line (re-styled when `routeColors` change, keeping the
  colour's alpha) and the vehicle image rendered at the device pixel ratio
  (`vehicleImage`). Day and night styles (`night`, `nightStyleString`; a
  switch reloads the style). The attribution button and the logo keep
  above `bottomInset`.
- Camera zooms (`CameraTarget`, `initialZoom`) use the Google Maps scale:
  the adapter shows them one level lower, as MapLibre's 512 px tiles
  need, so every provider frames a zoom alike.
- `MapLibreNavigationMap` implements `RoutePreviewMap`: route options as
  GeoJSON sources and line layers (`navigation_engine_option_*`) below the
  session's route, the muted ones under the selected one; duration labels
  from `paintRouteLabel` in a symbol layer (`routeLabel`, `labelColors`);
  taps through `onFeatureTapped`, from the option and label layers only
  (`onRouteOptionTap`). Options survive style reloads, colour changes
  restyle them, and `fitRoutes` accounts for the camera padding (with a
  pending fit).
- `MapLibreStyleNavigation`: a complete navigation screen
  (`MapboxStyleFlowScaffold` of navigation_engine_flutter) on
  `MapLibreNavigationView`, with `nightStyleString` at night;
  `onMapCreated` hands the app the controller. The attribution and the
  logo stay above the panels.
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors`, `CarPuck` and `VehicleImageBuilder`
  from navigation_engine_flutter.
