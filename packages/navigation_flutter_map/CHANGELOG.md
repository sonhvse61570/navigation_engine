## 0.1.0

- Initial release.
- `FlutterMapNavigationView` and `FlutterMapNavigationMap`: the follow
  camera, the route line, the vehicle marker (`markerSize`; a `CarPuck`
  uses its own size), day and night tiles (`night`,
  `nightTileUrlTemplate`), the app's own layers (`children`) and
  `onMapReady` with the `MapController`. The attribution keeps above
  `bottomInset`.
- `FlutterMapNavigationMap` implements `RoutePreviewMap`: a casing and a
  line per route option (`hitValue` = the route's index, the selected one
  on top, the others in `alternativeRouteColor`) and `RouteLabelBubble`
  labels (`routeLabel`, `labelColors`), tappable through
  `onRouteOptionTap`. `fitRoutes` honours `mapPadding` and waits for the
  map and `viewportSize`.
- `NeutralNavigation`: a complete navigation screen
  (`MapboxStyleFlowScaffold` of navigation_engine_flutter) themed from the
  app's `ColorScheme`, by day and, from the dark scheme of the same seed,
  at night (an app with a dark theme passes
  `MapboxStyleColors.fromColorScheme(darkTheme.colorScheme)` as
  `nightColors`). `userAgentPackageName` is required; `tileUrlTemplate`,
  `nightTileUrlTemplate` and `attribution` describe the tiles;
  `onMapReady` and `children` reach the map. The attribution stays above
  the panels.
- `FlutterMapNavigationMap` implements `AlternateRoutesMap`: grey lines
  (`alternateLines`) under the route options and the route, in
  `alternateColor` and 70 % as wide, and `RouteLabelBubble` bubbles
  (`alternateLabels`; `alternateLabel`, `setAlternateLabelColors`) at
  `min(divergence + 400 m, the middle of the rest)`; a tap on a line or a
  bubble calls `onTap`, unless it was drawn for an older list.
- `FlutterMapNavigationMap` implements `SearchPinsMap` (`searchPins`,
  `pinColor`, `pinPainter`; the shared `paintSearchPin`) and
  `DestinationPinMap` (`destinationPin`, `destinationPinPainter`; the
  shared `paintDestinationPin`): image markers at `pixelRatio`, above the
  route and its labels, below the app's layers and the vehicle, anchored at
  the pin's tip. A failed render removes the pins and is reported through
  `FlutterError`.
- `FlutterMapNavigationView.onMapTap` and `onMapLongPress`
  (`MapOptions.onTap` / `onLongPress`): a tap on a feature the adapter
  draws is not a map tap (its layer wins flutter_map's gesture arena,
  also when a newer list moves or removes the pressed marker; map taps
  also go through `MapTapGuard`, as on the other adapters); a map tap is
  delivered one turn of the event loop later. A press on a pin, a bubble
  or a route option label ends as a tap on what was pressed, or as
  nothing: it is reported only while that place, alternate or option is
  still shown (at the same index, for an alternate or an option), never
  for another marker, never after the view is gone, and never as a map
  tap. `NeutralNavigation` forwards both.
- `FlutterMapNavigationView.horizontalFocus`, forwarded to
  `NavigationMapFrame` (the camera follows it); the attribution keeps
  clear of a side panel, left or right, in LTR and RTL. The view also takes
  `alternateLabel`, `alternateColor`, `fasterLabelColors`,
  `slowerLabelColors` and `searchPinColor`, so a `GoogleStyleFlowScaffold`
  can drive it; it ignores the scaffold's traffic and satellite switches
  (raster tiles have neither). `NeutralNavigation` draws the alternates in
  its theme's colours and its strings' words.
- `NeutralNavigation` words and colours the alternates' bubbles with
  `alternateRouteLabel` and `alternateLabelColorsOf` from
  navigation_engine_flutter, shared with the other adapters (no visible
  change).
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors` and `CarPuck` from
  navigation_engine_flutter; and, for the map interfaces,
  `SearchPinsMap`, `DestinationPinMap`, `AlternateRoutesMap`,
  `AlongRoutePlace`, `AlternateRoute`, `paintSearchPin` and
  `paintDestinationPin`.
- `FlutterMapNavigationMap.routeLabel`: a change while options are shown
  rebuilds the labels. A change of the attribution's bottom inset keeps
  its state (an open popup stays open).
- Alternate lines are drawn only where the alternate differs from the
  route (`alternateLinePoints`: 40 m before it leaves the route to 40 m
  after it rejoins it): a tap on the route where they share the road is a
  map tap on every adapter.
- The library re-exports `RouteLabelColors`, the type of the view's
  `labelColors`, `fasterLabelColors` and `slowerLabelColors`.
- Colours left unset come from the shared `MapDefaultColors` (the same
  values as before), so every adapter looks the same without them.
- Alternate bubbles are placed with `alternateLabelDistance`: on a short
  detour the bubble sits at the middle of the part that differs, on the
  drawn line, not on the road it shares with the route.
