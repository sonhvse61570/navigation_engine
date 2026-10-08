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

## Shared vocabulary

Used by every adapter. The Google Maps package re-exports all of it; the
others re-export `NavigationStrings` and `SpeedLimitSign`:

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
