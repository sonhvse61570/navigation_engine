# navigation_engine_flutter_map

A smooth turn-by-turn navigation view for
[flutter_map](https://pub.dev/packages/flutter_map), built on
[navigation_engine](https://pub.dev/packages/navigation_engine).
No API key needed with OpenStreetMap tiles.

```dart
final session = NavigationSession(fixes: myFixSource)..start(route: route);

Stack(children: [
  FlutterMapNavigationView(
    session: session,
    initialCenter: route.points.first,
    userAgentPackageName: 'com.example.app',
  ),
  NavigationBanner(session: session), // from navigation_engine_flutter
]);
```

The view follows the vehicle heading-up at display rate, draws the route
(driven / ahead), keeps the vehicle at 70 % of the height, stops following
when the user touches the map and offers a recenter button. It attaches
itself as `session.map` while mounted. flutter_map has no tilt.
`onMapReady` hands you the `MapController`; the vehicle marker follows
`CarPuck.size` (or `markerSize` for a custom `puck`).

## Neutral navigation UI

`NeutralNavigation` is a complete navigation screen: the map, route options
with duration labels, turn-by-turn guidance with lanes, the speed and limit,
trip progress, a step list and an arrival panel, bound to a
`NavigationFlowController`. Its colours come from your app's theme.

The library re-exports what the screen takes from navigation_engine and
navigation_engine_flutter (`NavigationSession`, `GeoPoint`,
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`, …), so
the adapter is the only navigation_engine package to depend on (an app that
writes its own `FixSource` or `RouteProvider` adds navigation_engine):

```yaml
dependencies:
  navigation_engine_flutter_map: ^0.1.0
  flutter_map: ^8.3.2 # MapController and MarkerLayer
```

```dart
import 'package:flutter_map/flutter_map.dart' show MapController, MarkerLayer;
import 'package:navigation_engine_flutter_map/navigation_engine_flutter_map.dart';

final session = NavigationSession(fixes: myFixSource, routeProvider: provider);
final flow = NavigationFlowController(session: session, routeProvider: provider);

NeutralNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
  userAgentPackageName: 'com.example.app',
  nightTileUrlTemplate: 'https://tiles.example.com/dark/{z}/{x}/{y}.png',
  onMapReady: (MapController controller) {},
  children: [MarkerLayer(markers: myMarkers)], // your layers, above the route
);

session.start(); // the vehicle shows, and preview() starts from its position
await flow.preview(to: destination); // shows the route options; the user taps Start
```

The app owns, starts and disposes the `session` and the `flow` (flow first,
then the session, then the fix source). Pass `idleBuilder` for your own
overlay, such as a search bar, while the flow is idle. The screen is a
`MapboxStyleFlowScaffold` from `navigation_engine_flutter`, which documents
the pieces. Words come from `NavigationStrings` and numbers from `formatter`.

The attribution stays on the map, above the panel, the trip progress (and
the speed sign) and the arrival panel, as tile providers require. It reads `attribution`
(OpenStreetMap's by default): change it with `tileUrlTemplate`. With your
own `FlutterMapNavigationView`, set its `bottomInset`.

### Theme and night

By day the colours are `MapboxStyleColors.fromColorScheme` of the app's
`ColorScheme`: each text colour is the `on*` colour of its background, so the
contrast your scheme guarantees is kept (the banner uses the inverse surface
pair). At night, `flow.isNight`, the colours come from the dark
`ColorScheme.fromSeed` of the theme's primary colour. An app with its own
`darkTheme` should pass it, because a seed-derived scheme does not know your
dark palette:

```dart
NeutralNavigation(
  …,
  nightColors: MapboxStyleColors.fromColorScheme(darkTheme.colorScheme),
);
```

`dayColors` replaces the day colours the same way.

Night tiles: with a `nightTileUrlTemplate` the map switches to those tiles at
night; without it the day tiles are kept. `tileUrlTemplate` defaults to
OpenStreetMap's; `userAgentPackageName` is required and sent to the tile
server.

### Route options

`FlutterMapNavigationMap` implements `RoutePreviewMap`, so `flow.preview` and
`flow.select` draw the options (a casing and a line per route, with
`RouteLabelBubble` labels), and a tap on an option or its label selects that
route.

### Reserved ids

flutter_map has no style with ids, so the adapter reserves none: its route,
vehicle and route option layers are plain `children` of the map, and your
own `children` are drawn above the route options and the route, below the
vehicle. (The other adapters reserve
`navigation_engine_*` ids; see their READMEs.)

## How the session is driven

The view ticks the session only while it is on screen. A full-screen route pushed
on top mutes it: no guidance and no reroute until the user returns. Show a
session in one view at a time; two frames on one session tick it twice. To
keep guidance running off-screen, call `session.tick(dt)` yourself, for
example from a `Timer` or your own `Ticker`.

OpenStreetMap's tile servers are for light use only — see the
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/);
set `tileUrlTemplate` to your own provider for production.
