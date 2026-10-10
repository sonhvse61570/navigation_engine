## 0.1.0

- Initial release.
- `MapLibreNavigationView` and `MapLibreNavigationMap`: the follow camera,
  the route line (re-styled when `routeColors` change, keeping the
  colour's alpha) and the vehicle image rendered at the device pixel ratio
  (`vehicleImage`). Day and night styles (`night`, `nightStyleString`; a
  switch reloads the style). The attribution button keeps above
  `bottomInset` (the view shows no logo, maplibre_gl's default; its margin
  follows too).
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
  `onMapCreated` hands the app the controller. The attribution stays
  above the panels.
- `MapLibreNavigationMap` implements `AlternateRoutesMap`: one GeoJSON
  line layer (`navigation_engine_alternates`) under the route, in
  `alternateColor` and 70 % as wide, and bubbles (`alternateLabel`,
  `setAlternateLabelColors`) in a symbol layer at
  `min(divergence + 400 m, the middle of the rest)`; a tap on a line or a
  bubble calls `onTap`, unless it was drawn for an older list. A failed
  bubble render drops the bubbles and is reported through `FlutterError`.
- `MapLibreNavigationMap` implements `SearchPinsMap` (`pinColor`,
  `pinPainter`; the shared `paintSearchPin`) and `DestinationPinMap`
  (`destinationPinPainter`; the shared `paintDestinationPin`): symbol
  layers above the route and below the vehicle, anchored at the pin's tip.
  Alternates, bubbles and pins are drawn again after a style reload.
- `MapLibreNavigationView.onMapTap` and `onMapLongPress`
  (`MapLibreMap.onMapClick` / `onMapLongClick`): a tap on a feature the
  adapter draws is not a map tap (`MapTapGuard`, shared with the other
  adapters); a map tap is delivered one turn of the event loop later.
  `MapLibreStyleNavigation` forwards both.
- `MapLibreNavigationView.horizontalFocus`, forwarded to
  `NavigationMapFrame`; the attribution button keeps clear of a side panel
  on the right (the view shows no logo, maplibre_gl's default; its margin
  follows a panel on the left). The view also takes `alternateLabel`,
  `alternateColor`, `fasterLabelColors`, `slowerLabelColors` and
  `searchPinColor`, so a `GoogleStyleFlowScaffold` can drive it; it ignores
  the scaffold's traffic and satellite switches (the style decides).
  `MapLibreStyleNavigation` draws the alternates in its colours and words.
- `MapLibreStyleNavigation` words and colours the alternates' bubbles with
  `alternateRouteLabel` and `alternateLabelColorsOf` from
  navigation_engine_flutter, shared with the other adapters (no visible
  change).
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors`, `CarPuck` and `VehicleImageBuilder`
  from navigation_engine_flutter; and, for the map interfaces,
  `SearchPinsMap`, `DestinationPinMap`, `AlternateRoutesMap`,
  `AlongRoutePlace`, `AlternateRoute`, `paintSearchPin` and
  `paintDestinationPin`.
- A selection change keeps the route option labels drawn until the new
  ones are ready (no blink); the label image cache drops the least
  recently used image. A new controller (`onMapCreated`) drops a style
  load still running for the old one.
- Alternate lines are drawn only where the alternate differs from the
  route (`alternateLinePoints`: 40 m before it leaves the route to 40 m
  after it rejoins it): a tap on the route where they share the road is a
  map tap on every adapter.
- `showAlternates([])` is `clearAlternates()`: no empty layer is left and
  the old bubbles go at once.
- A tap on a route option line or label, or on a search pin, that the
  style still holds from an older list counts only for what is still
  shown: an option line or label only while its route is still the option
  at its index, a pin only while a place with its id is still shown (and
  with the newest `onTap`), as on the other adapters.
- The library re-exports `RouteLabelColors`, the type of the view's
  `labelColors`, `fasterLabelColors` and `slowerLabelColors`.
- Colours left unset come from the shared `MapDefaultColors` (the same
  values as before), so every adapter looks the same without them.
- Alternate bubbles are placed with `alternateLabelDistance`: on a short
  detour the bubble sits at the middle of the part that differs, on the
  drawn line, not on the road it shares with the route.
- Docs: the view shows no logo (maplibre_gl's `logoEnabled` defaults to
  false); only the attribution button is kept above `bottomInset` and
  clear of side panels.
