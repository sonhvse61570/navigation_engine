# navigation_engine

Smooth, map-agnostic turn-by-turn navigation for Dart and Flutter.

Phones report GPS about once a second, 0.3–1 s late and several metres off.
Drawing those fixes directly makes the vehicle jump, drift onto sidewalks and
spin at red lights. `navigation_engine` turns them into display-rate motion
that stays on the road, plus turn-by-turn guidance — without depending on any
map SDK.

## How it works

1. **Snap to the route.** Every fix becomes one number: metres driven along
   the route. Sideways noise disappears; corners follow the polyline. The
   search window is sized to the speed, so a fix near a U-turn never lands on
   the opposite carriageway.
2. **Predict, then correct.** The vehicle keeps moving at its speed every
   frame; a new fix only nudges it (absorbed over ~0.5 s, capped at 5 m/s,
   never backwards). Fix latency is compensated. Standing still holds still.
   Fixes without a speed get one estimated from the previous fixes.
3. **Heading from the road.** The bearing is the chord from 5 m behind to
   15 m ahead on the route, smoothed — not the GPS heading.
4. **Cheap rendering.** The camera moves every frame with at most one update
   in flight; the vehicle marker is a fixed widget at the camera centre.

## Quick start

```dart
import 'package:navigation_engine/navigation_engine.dart';

final session = NavigationSession(
  fixes: myFixSource,        // implements FixSource (GPS, simulator, …)
  map: myNavigationMap,      // implements NavigationMap (optional)
  routeProvider: myRouter,   // extends RouteProvider (optional: rerouting)
);
session.start(route: NavRoute.fromPoints(points, steps: steps));

// Once per display frame, e.g. from a Flutter Ticker:
session.tick(dt);

const formatter = EnglishGuidanceFormatter();
session.announcements.listen((a) => speak(formatter.announcement(a)));
session.guidance.listen((g) => g == null ? hideBanner() : showBanner(g));
session.events.listen((e) {
  if (e is Arrived) session.stop();
});

// App in the background, or the user taps pause:
session.pause(); // stops the FixSource, keeps the route and the progress
session.resume();

// When done (e.g. in State.dispose). Your FixSource is not disposed.
session.dispose();
```

`pause()` stops the fix source but keeps the run: the route, the vehicle and
the guidance progress stay, and `resume()` carries on. Use them rather than
stopping the `FixSource` yourself. `stop()` ends the run; the next `start()`
begins afresh. `guidance` emits `null` when the route is removed: hide the
banner.

Without a session, use the parts directly: `FixFilter` →
`RouteMotionEngine.onFix` / `tick` → `FollowCamera.update` →
`NavGuidance.update`.

## Trip data

Routes carry what a navigation UI shows besides the line:
- **Time**: `NavRoute.fromPoints(segmentDurations: …)` takes the router's
  per-segment durations; without them each segment is timed at its speed
  limit, else at `fallbackSpeed` (30 km/h). `duration`,
  `remainingDuration(distance)` and `durationAt` give remaining time and
  ETA.
- **Speed limits**: `segmentSpeedLimits` and `speedLimitAt(distance)`.
- **Lanes**: `RouteStep.lanes`, a `Lane` per lane with its arrows, whether
  it can be used and the arrow to follow.
- **Summary**: `summary` names the main roads ("via …"); derived from the
  steps when not given.
- **Alternatives**: `RouteProvider.routes()` returns the best route and
  alternatives (by default only the best).
- **Day or night**: `SunTimes.at(position, time)` gives sunrise and sunset
  where the vehicle is, for day and night map styles.
- Formatters also say durations, clock times and speeds
  (`duration`, `clockTime`, `speed`).

## Extension points

| Interface | Implement it to… |
|---|---|
| `FixSource` | feed fixes from the device GPS, a recording, a simulator |
| `RouteProvider` | compute routes and alternatives (OSRM, Google Routes, your back end); extend it |
| `NavigationMap` | render on Google Maps, Mapbox, flutter_map, … (~50 lines) |
| `GuidanceFormatter` | speak another language (English and Vietnamese included) |

New `ManeuverType` and `ManeuverModifier` values may be added in minor
versions, as routing providers add manoeuvre kinds. Give a `switch` over them
a default case, or expect to update it.

Planned companion packages: `navigation_engine_google_maps`,
`navigation_engine_mapbox`, `navigation_engine_flutter_map`,
`navigation_engine_geolocator`, `navigation_engine_osrm`.

## Testing your app

`package:navigation_engine/testing.dart` provides `GpsSimulator` (a
deterministic car + GPS model with noise, latency, multipath bias, outliers
and optional red lights), `SimulatedFixSource`, and `sampleRoute`, a real
5.5 km city drive (`sampleRouteRedLights` adds its two red lights:
`GpsSimulator(sampleRoute, stops: sampleRouteRedLights)`). Engines take the
current time as a parameter and the session takes an injectable clock, so
tests run on a virtual clock. `sampleRoute` carries OSRM durations plus
synthetic speed limits and lanes (the demo data has neither);
`sampleRouteAlternatives` holds the alternative OSRM returned.

## Limitations

- Distances use a local equirectangular projection: accurate to about a
  metre on city-scale routes at mid latitudes, degrading beyond a few tens
  of kilometres.
- Single-leg routes (no waypoints) for now.

## Example

See [`example/`](example/): a Flutter app on flutter_map with simulated GPS
(no API key), and `example/bin/console.dart`.

`sampleRoute`: route data © OpenStreetMap contributors, ODbL 1.0.
