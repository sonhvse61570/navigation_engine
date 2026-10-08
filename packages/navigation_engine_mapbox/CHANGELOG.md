## 0.1.0

- Initial release.
- `MapboxNavigationView` and `MapboxNavigationMap`: the follow camera, the
  route line (re-styled when `routeColors` change) and the vehicle image
  rendered at the device pixel ratio (`vehicleImage`). The compass and the
  scale bar are off; the logo and the attribution button keep above
  `bottomInset` (`placeOrnaments`).
- Night: `lightPreset` sets the Standard style's light preset without a
  style reload, and is applied first when a style loads, so a night start
  shows no day. `MapboxNavigationView.night` uses the Standard style's
  `night` preset, or loads `nightStyleUri` on other styles.
- Camera zooms (`CameraTarget`, `initialZoom`) use the Google Maps scale:
  the adapter shows them one level lower, as Mapbox's 512 px tiles need,
  so every provider frames a zoom alike.
- `MapboxNavigationMap` implements `RoutePreviewMap`: route options as
  GeoJSON sources and line layers (`navigation_engine_option_*`) below the
  session's route, the muted ones under the selected one; duration labels
  from `paintRouteLabel` in a symbol layer (`routeLabel`, `labelColors`);
  taps through tap interactions on the option and label layers only
  (`onRouteOptionTap`). Options survive style reloads, clearing removes
  their sources, layers and label images, colour changes restyle them,
  and `fitRoutes` accounts for the camera padding (with a pending fit).
- `MapboxStyleNavigation`: a complete navigation screen
  (`MapboxStyleFlowScaffold` of navigation_engine_flutter) on
  `MapboxNavigationView`; night is the Standard style's `night` light
  preset, or `nightStyleUri`; `onMapCreated` hands the app the map. The
  logo and the attribution stay above the panels.
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors`, `CarPuck` and `VehicleImageBuilder`
  from navigation_engine_flutter.
- A new selection restyles and reorders the route option lines in place
  and keeps the labels until the new ones are ready (no flicker); a failed
  layer move is reported and redone on the next update, and a clear still
  removes the layer. The label image cache drops the least recently used
  image.
- On the Standard style the view sets the light preset (`day` or
  `night`) at each style load; `MapboxNavigationMap.lightPreset` sets
  another one for a custom view.
