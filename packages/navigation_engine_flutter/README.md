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
- **`NavigationFlowController`** — overview → navigation → arrival on top
  of a session: route options and selection, start / stop / back to
  overview, trip progress (remaining distance, time, ETA), speed and speed
  limit, rerouting, day or night. No widgets: provider-styled UIs listen to
  it. Maps that implement **`RoutePreviewMap`** draw the route options.

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
`fitRoutes`); no bundled adapter implements it yet.
