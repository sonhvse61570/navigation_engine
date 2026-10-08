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
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors` and `CarPuck` from
  navigation_engine_flutter.
- `FlutterMapNavigationMap.routeLabel`: a change while options are shown
  rebuilds the labels. A change of the attribution's bottom inset keeps
  its state (an open popup stays open).
