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
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`, …) and
the map interfaces' names (`SearchPinsMap`, `DestinationPinMap`,
`AlternateRoutesMap`, `AlongRoutePlace`, `AlternateRoute`, `paintSearchPin`,
`paintDestinationPin`), so
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

### Alternates, pins and map taps

`FlutterMapNavigationMap` also implements `AlternateRoutesMap`,
`SearchPinsMap` and `DestinationPinMap` (navigation_engine_flutter):

- **Alternate routes** while navigating: grey lines under the route
  (`alternateColor`, 70 % as wide), each with a `RouteLabelBubble`
  (`alternateLabel`, `fasterLabelColors` / `slowerLabelColors`) at most
  400 m past where it leaves the route, else at the middle of the rest. A
  tap on a line or a bubble switches to that alternate; a tap on one still
  drawn for an older list is ignored. Each line is drawn only from 40 m
  before the alternate leaves the route to 40 m after it rejoins it
  (`alternateLinePoints`), so a tap on the route where the two share the
  road is a map tap, as on every adapter (over those 40 m the route is on
  top and takes the tap). `NeutralNavigation` words the bubbles with its `strings`
  ("2 min faster") and colours them from the theme.
- **Search pins** (`showSearchPins`, `pinColor`), the focused one larger
  and on top; a tap calls `onTap` with the place.
- **The destination pin** (`showDestinationPin`): the shared red pin of
  `paintDestinationPin`. The scaffolds pin the end of the selected route in
  the overview, while navigating and arrived.

The pins are the PNGs of the shared painters (`paintSearchPin`,
`paintDestinationPin`) at the device pixel ratio, anchored at their tip and
upright when the map rotates, so they look the same as on the other
adapters.

`FlutterMapNavigationView.onMapTap` and `onMapLongPress` (forwarded by
`NeutralNavigation`) get the app's taps on the map as `GeoPoint`s
(`MapOptions.onTap` / `onLongPress`). A tap on a route option, an
alternate, a bubble or a pin is not a map tap: the feature's layer wins
flutter_map's gesture arena, also when a newer list (a focus change, a
new search) moves or removes the pressed marker during the press. A press
on a pin, a bubble or a route option label ends as a tap on what was
pressed, or as nothing: it is reported only while that place, alternate or
option is still shown (at the same index, for an alternate or an option),
never for another marker and never after the view is gone. The map
taps also go through `MapTapGuard`, as on the other adapters, for parity:
flutter_map never reports a map tap in the frame or turn of a feature tap,
so the guard changes nothing here. A map tap is delivered one turn of the
event loop after flutter_map reports it (which is after its double-tap
window); a long press at once, wherever it is.

### Side panels and Google-style screens

`horizontalFocus` moves the followed vehicle across the map (0.5 is the
centre), as `NavigationMapFrame.horizontalFocus`. It is physical (0 is the
left edge in both text directions). The attribution (bottom left) keeps
clear of the side panel the focus makes room for, on the left or the right,
in LTR and RTL, above `bottomInset`.

An app can build the view from a `GoogleStyleFlowScaffold`'s `mapBuilder`:

```dart
GoogleStyleFlowScaffold(
  session: session,
  flow: flow,
  mapBuilder: (context, config, layers) => FlutterMapNavigationView(
    key: mapKey, // keeps the map across rebuilds
    session: session,
    initialCenter: start,
    userAgentPackageName: 'com.example.app',
    night: config.isNight,
    horizontalFocus: layers.horizontalFocus,
    bottomInset: layers.bottomOverlay,
    routeColors: layers.routeColors,
    routeLabel: layers.routeLabel,
    alternateLabel: layers.alternateLabel,
    onRouteOptionTap: config.onRouteOptionTap,
    labelColors: layers.colors.routeLabelColors,
    alternativeRouteColor: layers.colors.alternative,
    alternateColor: layers.colors.alternative,
    fasterLabelColors: layers.colors.fasterLabelColors,
    slowerLabelColors: layers.colors.slowerLabelColors,
    searchPinColor: layers.colors.warning,
    recenterButton: (_) => const SizedBox.shrink(),
    onMapReady: (_) => config.onMapReady(),
  ),
)
```

Raster tiles have no traffic layer and no satellite imagery of their own,
so the view ignores `layers.traffic` and `layers.satellite`; an app with
satellite tiles can pass them as `tileUrlTemplate` (with their
`attribution`) while `layers.satellite` is on.

### Reserved ids

flutter_map has no style with ids, so the adapter reserves none: its
layers are plain `children` of the map. Bottom to top: the tiles, the
alternates, the route options, the session's route, the alternate bubbles,
the route option labels, the destination pin, the search pins, your own
`children`, the vehicle and the attribution. (The other adapters reserve
`navigation_engine_*` ids; see their READMEs.)

## Feature parity

What each map adapter supports. The map interfaces and helpers come from
navigation_engine_flutter; each adapter re-exports the interfaces' names.

| | Google Maps | MapLibre | flutter_map | Mapbox |
|---|---|---|---|---|
| Drop-in screen | `GoogleStyleNavigation` | `MapLibreStyleNavigation` | `NeutralNavigation` | `MapboxStyleNavigation` |
| Map tap and long press (`onMapTap`, `onMapLongPress`; a tap on a feature the adapter draws is not a map tap; a tap on the vehicle is) | yes | yes | yes | yes |
| When `onMapTap` is called | one turn of the event loop after the SDK reports the tap | one turn after the SDK reports it | after flutter_map's double-tap window (about 250 ms), then one turn | one turn after the SDK reports it |
| Search pins (`SearchPinsMap`) | yes | yes | yes | yes |
| Destination pin (`DestinationPinMap`) | yes | yes | yes | yes |
| Alternate routes (`AlternateRoutesMap`) | yes | yes | yes | yes |
| A tap on the route where an alternate shares the road | a map tap: each alternate is drawn only from 40 m before it leaves the route to 40 m after it rejoins it (`alternateLinePoints`) | the same | the same | the same |
| Colours left unset (`labelColors`, `alternateColor`, `fasterLabelColors`, `slowerLabelColors`, `searchPinColor`) | the shared day defaults, `MapDefaultColors` | the same | the same | the same |
| `horizontalFocus` (side panels) | view and drop-in (landscape panel) | view; the drop-in has no side panel | view; the drop-in has no side panel | view; the drop-in has no side panel |
| Traffic and satellite | yes: `trafficEnabled` and `mapType`, the Google-style menu's switches | from the style: pass a satellite or traffic style as `styleString` | from the tiles: pass satellite tiles as `tileUrlTemplate`; no traffic layer | from the style: pass `MapboxStyles.STANDARD_SATELLITE` as `styleUri`; traffic needs your own source and layers |
| Web | a long press is a right click | a long press is a double click, which first calls `onMapTap` twice and zooms in | as on mobile | no long press (Mapbox GL JS has none): `onMapLongPress` is never called |

The drop-ins pass their theme's colours, by day and at night. An app that
builds a view itself (from a `GoogleStyleFlowScaffold`'s `mapBuilder`, say)
passes `alternateColor`, `fasterLabelColors`, `slowerLabelColors` and
`searchPinColor` (and `labelColors`) to follow its theme and night mode;
left unset, every adapter uses the same day colours (`MapDefaultColors`).

The MapLibre, flutter_map and Mapbox views ignore `layers.traffic` and
`layers.satellite` when a `GoogleStyleFlowScaffold`'s `mapBuilder` builds
them: switch the style or the tiles yourself. For GPS fixes and routes with
any adapter, see `navigation_engine_geolocator` (`GeolocatorFixSource`) and
`navigation_engine_osrm` (`OsrmRouteProvider`).

## How the session is driven

The view ticks the session only while it is on screen. A full-screen route pushed
on top mutes it: no guidance and no reroute until the user returns. Show a
session in one view at a time; two frames on one session tick it twice. To
keep guidance running off-screen, call `session.tick(dt)` yourself, for
example from a `Timer` or your own `Ticker`.

OpenStreetMap's tile servers are for light use only — see the
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/);
set `tileUrlTemplate` to your own provider for production.
