# navigation_engine_flutter

Map-independent Flutter building blocks for
[navigation_engine](https://pub.dev/packages/navigation_engine) map views.
Use one of the adapters for a complete view:
`navigation_engine_google_maps`, `navigation_engine_mapbox`,
`navigation_engine_maplibre`, `navigation_engine_flutter_map`.

- **`NavigationMapFrame`** — ticks a `NavigationSession` every display
  frame, keeps the followed vehicle at a focus point (70 % of the height by
  default) by handing the map the right padding, draws a fixed vehicle puck
  while following, stops following when the user touches the map, offers a
  recenter button, and pauses the session while the app is in the
  background.
- **`VehicleMarkerMap`** — implemented by adapters to draw the vehicle as a
  native marker while not following.
- **`NavigationBanner`** — next manoeuvre, distance, follow-up hint, last
  prompt; any `GuidanceFormatter` (English and Vietnamese included).
- **`CarPuck`** — the arrow, as a widget or PNG bytes for native markers.
- **Shared UI vocabulary** — `NavigationStrings` (English and Vietnamese),
  `SpeedLimitSign`, `laneDirectionIcon`, `fitCameraToBounds`, and the route
  duration label as PNG bytes (`paintRouteLabel`) or a widget
  (`RouteLabelBubble`), coloured by `RouteLabelColors`.
- **`NavigationFlowController`** — overview → navigation → arrival on top
  of a session: route options and selection, start / stop / back to
  overview, trip progress (remaining distance, time, ETA), speed and speed
  limit, rerouting, day or night. No widgets: provider-styled UIs listen to
  it. Maps that implement **`RoutePreviewMap`** draw the route options.
- **`NavigationFlowScaffold`** — the flow binding of a navigation screen,
  without a look: a style passes builders for the map, the panel, the
  header, the footer, the speed, the arrival, the step list and the
  recenter button. It switches them by state, sets the overview padding
  from the panel, handles back, guards the actions it gives the pieces
  (`NavigationFlowActions`) and builds the map apart from progress ticks.
  `recenterAlignment` places the recenter button (bottom start by default,
  stacked above the speed); anywhere else it keeps above the speed's band.
  The alignment is directional, so in a right-to-left app the button
  mirrors (bottom end is the bottom left).
- **Mapbox-style UI** — `MapboxStyleFlowScaffold` is the scaffold dressed
  with ready-made pieces, the screen of the adapters' drop-ins
  (`MapboxStyleNavigation`, `MapLibreStyleNavigation`, `NeutralNavigation`).
  The pieces are public: `MapboxStyleManeuverBanner`, `MapboxStyleRoutePanel`,
  `MapboxStyleTripProgress`, `MapboxStyleSpeedLimit`,
  `MapboxStyleRecenterButton`, `MapboxStyleStepList` and
  `MapboxStyleArrivalPanel`. Their colours are `MapboxStyleColors`:
  `day`, `night`, or `MapboxStyleColors.fromColorScheme(colorScheme)` to
  follow an app's theme; `routeLabelColors` converts them for the route
  labels. The palette is original to this package; the look is inspired by
  Mapbox's navigation apps and is not an official Mapbox product.
- **Google-style UI** — `GoogleStyleFlowScaffold` is the scaffold dressed
  with the Google-style pieces, the screen of the Google Maps adapter's
  `GoogleStyleNavigation`. It works on any map: see
  [Google-style pieces](#google-style-pieces).

## Google-style pieces

`GoogleStyleFlowScaffold` is a whole navigation screen in the style of a
phone navigation app: a turn card with lanes and a "Then" tab, a step
preview, an end column (report, compass, search along the route, sound,
route options), a speed cluster, a trip sheet you drag up, alternate
routes, a landscape side panel, a toast and back handling. It owns the
flow binding and the look; you give it the map. Build the Google look on
any map with a `mapBuilder`:

```dart
GoogleStyleFlowScaffold(
  session: session,
  flow: flow,
  mapBuilder: (context, config, layers) => MyMap(
    night: config.isNight,
    onRouteTap: config.onRouteOptionTap,
    onReady: config.onMapReady,
    // What the screen asks of the map, every time it is built:
    traffic: layers.traffic,
    satellite: layers.satellite,
    followFocusX: layers.horizontalFocus, // 0..1 from the left
    attributionInset: layers.bottomOverlay,
    alternateColor: layers.colors.alternative,
    routeColors: layers.routeColors,
    routeLabel: layers.routeLabel,         // the text of a route bubble
    alternateLabel: layers.alternateLabel, // "2 min faster"
  ),
  idleBuilder: (_) => const MySearchBar(),
  searchAlongRoute: (query) => myPlaces.along(query.route, query.text),
  onAddStop: (place) => myTrip.addStop(place),
)
```

`GoogleStyleMapLayers` is what the screen asks of the map beyond the
`NavigationMapConfig`: the traffic and satellite switches of the trip
sheet's menu, the follow focus across the map (beside a landscape side
panel it is the middle of the uncovered part), how much of the map's
bottom the screen covers (keep the map's logo above it), and the colours,
route colours and bubble texts of the moment (day or night). Apply them
on every build; the map may be built again with equal layers, never for
progress ticks.

The scaffold uses three optional interfaces of the session's map when it
implements them, and works without them: `AlternateRoutesMap` (alternate
routes while navigating), `SearchPinsMap` (pins for the places found
along the route; a place focused from the list or a pin still moves the
camera through any map) and `DestinationPinMap` (see below).

The pieces are public, so a screen of your own can mix them:
`GoogleStyleManeuverHeader`, `GoogleStyleLaneGuidance`,
`GoogleStyleTripSheet`, `GoogleStyleSpeedCluster`,
`GoogleStyleRecenterButton`, `GoogleStyleTripProgressBar`,
`GoogleStyleCompassButton`, `GoogleStyleRoundButton`,
`GoogleStyleControlStack`, `GoogleStyleSoundButton`,
`GoogleStyleReportButton`, `GoogleStyleReportSheet`,
`GoogleStyleSearchAlongRoute`, `GoogleStyleOverviewPanel`,
`GoogleStyleStepList` and `GoogleStyleArrivalSheet` (with
`showGoogleStyleReportSheet`, `GoogleStyleSheetAction`, `SpeedingLevel`
and `SpeedLimitSignStyle`). Their colours are
`GoogleStyleColors` (`day`, `night`; `routeLabelColors` converts them for
the route labels), and the screen takes `dayColors` and `nightColors`
(and `dayRouteColors` / `nightRouteColors`) to replace them. The app owns
the audio (`AudioGuidance`), the reports (`IncidentType`), the search back
end (`AlongRouteQuery`, `AlongRoutePlace`) and the stops. The palette is
original to this package; the look is inspired by Google Maps and is not
an official Google product.

Some of these names are generic and carry no `Google` prefix:
`AudioGuidance`, `IncidentType`, `SpeedingLevel`, `SpeedLimitSignStyle`
and the `AlongRoute*` types. If an app's other packages define one of
them, import this library with `hide` or `as`.

## Flow controller

```dart
final flow = NavigationFlowController(session: session, routeProvider: router);
await flow.preview(to: destination); // FlowLoading, then FlowOverview
flow.select(1);                      // pick an alternative
flow.start();                        // FlowNavigating … FlowArrived
flow.tripProgress.addListener(() => print(flow.tripProgress.value?.eta));

// A failed request: offer "Retry" and "Cancel".
if (flow.state.value is FlowError) {
  await flow.retry(); // or flow.cancel()
}
```
The controller never ticks the session (the map view does) and never
disposes it.

- `preview()` and `previewRoutes()` throw while navigating. To plan a new
  destination, call `backToOverview()` first; resuming with `start()` keeps
  the running route (and follows a reroute made meanwhile).
- Failures land in `FlowError(error, previous, to)`: `cancel()` returns to
  the state before the request (the trip overview follows reroutes made meanwhile),
  and `retry()` repeats the failed request, with its origin, heading and
  alternatives.
- `closeOverview()` closes a route preview (an overview that is not the
  trip's own) back to `FlowIdle`, without touching the session; in the trip
  overview, `start()` resumes the trip instead.
- Resuming uses the route instance the session already runs; call `stop()`
  before replaying the same `NavRoute` instance from the start.
- Map-adapter errors are reported through `FlutterError`, never thrown.
- Call `refreshOverview()` after a map view attaches during the overview, so
  the new map draws the route options. Changing `overviewPadding` re-fits
  them.
- `stop()` stops the app's session too. To keep showing the vehicle
  afterwards, call `session.start()` again.

### Destination, step preview and alternates

```dart
await flow.preview(to: to, destination: const PlaceLabel(name: 'Landmark 81'));
flow.start();
flow.previewStep(3);            // camera on step 3; follow off for 10 s
flow.alternates.value;          // AlternateRoute(route, timeDelta, divergence)
flow.selectAlternate(0);        // switch, no route request
```

- **Destination:** a `PlaceLabel` (a name and an optional address) passed
  to `preview` or `previewRoutes` rides on `FlowOverview`, `FlowNavigating`
  and `FlowArrived`, for an arrival card.
- **Step preview:** `previewStep` turns follow off and moves the camera
  once to that step's manoeuvre (`previewedStep` holds its index); a
  Re-center, `endStepPreview`, a reroute, an alternate, arrival, stop or
  `stepPreviewTimeout` (10 s) ends it. When the user touches the map during
  a preview, call `endStepPreview(refollow: false)`: the camera stays where
  the user moves it.
- **Alternates:** the unselected routes of the overview are kept as
  `alternates` while navigating, each dropped 20 m past where it leaves the
  route, and requested again after a reroute (one more `routes` request per
  reroute; `fetchAlternatesOnReroute: false` turns it off);
  `selectAlternate` switches the session to one without a route request,
  placing the vehicle on it (a refetched alternate starts where the vehicle
  was), and maps that implement `AlternateRoutesMap` draw them.

## A screen in your own style

`NavigationFlowScaffold` has no look. Give it the map and one builder per
piece; it does the state switching, padding, back and guarded actions:

```dart
NavigationFlowScaffold(
  session: session,
  flow: flow,
  mapBuilder: (context, config) => ValueListenableBuilder<double>(
    // The panel, footer or arrival height, with the speed's band while the
    // speed shows: keep the attribution above it.
    valueListenable: config.bottomOverlayHeight,
    builder: (context, bottomInset, _) => MyMap(
      night: config.isNight,
      onRouteTap: config.onRouteOptionTap, // select a route in the overview
      onReady: config.onMapReady,          // draw the overview on a new map
      attributionInset: bottomInset,
    ),
  ),
  panelBuilder: (context, state, actions) => MyPanel(state, actions),
  headerBuilder: (context, guidance, actions) =>
      MyTurnCard(guidance, onTap: actions.showSteps),
  footerBuilder: (context, progress, rerouting, actions) =>
      MyFooter(progress, onEnd: actions.end),
  arrivalBuilder: (context, route, actions) => MyArrival(onDone: actions.end),
  stepListBuilder: (context, route, step) => MySteps(route, step),
  recenterBuilder: (context, recenter) => MyRecenter(onTap: recenter),
  recenterAlignment: AlignmentDirectional.bottomEnd,
)
```

The scaffold builds the map only when the flow's state or the night mode
changes, so progress ticks do not rebuild a platform map. Keep the map's own
recenter button off. `config.bottomOverlayHeight` changes without a rebuild
of the map: listen to it where the map's attribution and logo are placed,
so map providers' terms are met above the panels.

The pieces keep inside the safe area, landscape notches included: the
header and the bottom pieces take their edge's insets (give the panel, the
footer and the arrival panel a `SafeArea` for the bottom inset), the edge
and top end slots and the recenter button the side insets.

A style may opt into more, all off by default: `recenterReplacesSpeed`
(the recenter button takes the speed's place while it shows),
`bottomEndBuilder` (a piece at the bottom end, such as a report button,
lifted above the speed when the two do not fit side by side),
`arrivalHeaderBuilder` (a card at the top while arrived) and
`landscapeSidePanel` (on a wide landscape screen, see `usesSidePanel` and
`sidePanelWidth`, the header and the footer move to a column on the start
side). The Google-style drop-in uses them; the other drop-ins use none of
them.

### What the drop-ins give the app's map

The adapters' drop-in screens are built on these scaffolds. Each adapter's
library re-exports the names its drop-in takes (`NavigationSession`,
`GeoPoint`, `NavigationFlowController`, `NavigationStrings`,
`SpeedLimitSign`, `RouteColors`, `CarPuck`, …), so an app imports only the
adapter. The app reaches the map through:

| Drop-in | Package | Map callback | App content on the map |
| --- | --- | --- | --- |
| `GoogleStyleNavigation` | navigation_engine_google_maps | `onMapCreated(GoogleMapController)` | `markers` |
| `MapboxStyleNavigation` | navigation_engine_mapbox | `onMapCreated(MapboxMap)` | layers through the `MapboxMap` |
| `MapLibreStyleNavigation` | navigation_engine_maplibre | `onMapCreated(MapLibreMapController)` | layers through the controller |
| `NeutralNavigation` | navigation_engine_flutter_map | `onMapReady(MapController)` | `children` (flutter_map layers) |

Each callback runs after the route overview is drawn on the new map.

A map builder also gets `config.startOverlayWidth`: the width a landscape
side panel covers on the map's start side (0 without one). It changes
without a new config; shift the follow focus to the middle of the rest.

### The destination pin

When the session's map implements `DestinationPinMap`
(`showDestinationPin(GeoPoint?)`, null clears), both styled scaffolds (any
`NavigationFlowScaffold`) pin the end of the selected route in the
overview, while navigating and arrived. The pin moves when the selection,
an alternate or a reroute changes the route, is shown again for a new
flow and on a map that reports itself ready (a new session's map gets it
once it reports itself ready), and is removed when the flow goes back to
idle and while a request loads or has failed, as the route options are (a
cancel back to the overview shows it again). While the flow shows no pin
the app may pin a place of its own through the same interface, such as
one the user long-pressed; the flow's pin replaces it once the overview
shows:

```dart
GoogleStyleNavigation(
  // …
  onMapLongPress: (point) {
    if (session.map case final DestinationPinMap pin) {
      pin.showDestinationPin(point);
    }
    flow.preview(to: point);
  },
);
```

Every adapter draws the same marker, `paintDestinationPin` (a red pin of
this package's own design, as PNG bytes for native marker images), as it
draws the search results with `paintSearchPin`.

## Shared vocabulary

Used by every adapter. The Google Maps package re-exports
`NavigationStrings`, `fitCameraToBounds`, `paintRouteLabel`,
`RouteLabelColors`, `laneDirectionIcon`, `paintSearchPin` and
`paintDestinationPin`; the others re-export `NavigationStrings`,
`SpeedLimitSign`, `paintSearchPin` and `paintDestinationPin`. Import this
package for the rest:

- `NavigationStrings`: the words of the UIs, English by default and
  `NavigationStrings.vietnamese()`. Distances, durations and speeds come from
  the `GuidanceFormatter`.
- `fitCameraToBounds`: the camera (centre and zoom on a 256 dp world) that
  shows a set of points inside a padded viewport. Adapters whose SDK uses a
  512 px world (MapLibre, Mapbox) convert it by one zoom level.
- `paintRouteLabel` and `RouteLabelBubble`: the route duration bubble as PNG
  bytes for native map images, or as a widget; `RouteLabelColors` colours
  them.
- `SpeedLimitSign`: the circular or rectangular speed limit sign.
- `laneDirectionIcon`: the arrow of a lane direction.
- `paintSearchPin` and `paintDestinationPin`: the search result pin and the
  destination pin as PNG bytes for native marker images, anchored at their
  tip.
- `alternateRouteLabel(alternate, strings)`: the bubble text of an
  alternate route from its time difference in whole minutes, "2 min faster"
  (`NavigationStrings.minFaster`), "+3 min" (`minSlower`) or "Similar ETA"
  (`similarEta`). Every drop-in passes it as its view's `alternateLabel`.
- `alternateLabelColorsOf(colors)`: the bubble colours (`faster`, `slower`)
  of the alternates in `MapboxStyleColors`, the text in the accent or the
  muted text colour on the surface. The MapLibre, flutter_map and Mapbox
  drop-ins pass them as their views' `fasterLabelColors` and
  `slowerLabelColors`.
- `MapTapGuard`: keeps the map tap of a gesture from the app when a feature
  the adapter draws took it (see Writing an adapter).

## How the session is driven

The frame ticks the session only while it is on screen. A full-screen route pushed
on top mutes it: no guidance and no reroute until the user returns. Show a
session in one view at a time; two frames on one session tick it twice. To
keep guidance running off-screen, call `session.tick(dt)` yourself, for
example from a `Timer` or your own `Ticker`.

## Writing an adapter

```dart
class MyNavigationMap implements NavigationMap, VehicleMarkerMap { … }

NavigationMapFrame(
  session: session,
  vehicleMarkers: myMap,
  mapBuilder: (context, focusPadding) => MySdkMap(padding: focusPadding, …),
);
```
Attach the adapter with `session.map = myMap` while the view is mounted.
To draw route options for `NavigationFlowController`'s overview, also
implement `RoutePreviewMap` (`showRouteOptions`, `clearRouteOptions`,
`fitRoutes`); every bundled adapter implements it. Route option ids start
with `navigation_engine_option_`.

Three more optional interfaces give the screens their map features; every
bundled adapter implements all of them, and a screen works without them:

| Interface | Methods | Used for |
| --- | --- | --- |
| `AlternateRoutesMap` | `showAlternates(alternates, onTap:)`, `clearAlternates()` | the alternate routes while navigating, each with a bubble (`AlternateRoute`: the route, its time difference and where it leaves the route) |
| `SearchPinsMap` | `showSearchPins(places, focusedId:, onTap:)`, `clearSearchPins()` | the places found along the route (`AlongRoutePlace`) |
| `DestinationPinMap` | `showDestinationPin(point)` (null removes it) | the trip's destination, or a place the app pins itself |

Draw the pins with `paintSearchPin` and `paintDestinationPin`, so every
adapter looks the same. A drop-in words the alternates' bubbles with
`alternateRouteLabel` and, in Mapbox-style colours, colours them with
`alternateLabelColorsOf`.

A view's `onMapTap` must not fire for a tap on a feature the adapter draws
(a route option, an alternate, a bubble, a pin), and some SDKs report a map
tap as well for such a gesture. `MapTapGuard` drops it: call
`featureTapped()` from each tap on your own features, pass every map tap to
`dispatch`, and `dispose()` the guard with the map. A feature tap leaves a
one-shot token that the next map tap of the same frame spends; a map tap is
held for one turn of the event loop, and a feature tap in that turn drops
it. No wall clock is involved.

```dart
final guard = MapTapGuard();
// From each tap on an option line, alternate, bubble or pin:
guard.featureTapped();
// From the SDK's map tap:
guard.dispatch(() => widget.onMapTap?.call(point));
// When the map goes:
guard.dispose();
```

A long press is not guarded: `onMapLongPress` fires wherever it is.
