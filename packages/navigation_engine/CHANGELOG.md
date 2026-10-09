## 0.1.0

- `FollowCamera` defaults sit closer and flatter, like the common driving
  apps: `zoomSlow` 18.7, `zoomFast` 17.1 (each half a level closer) and
  `tilt` 35° (was 50°).
- `FollowCamera.headingUp` (default `true`): when false the camera stays
  north-up and flat (bearing 0, tilt 0), with the zoom logic unchanged.
- `NavigationSession.followChanges` and `FollowCamera.headingUpChanges`
  emit each change of `follow` and `headingUp`, so a UI can show it
  without waiting for a frame. `FollowCamera.dispose` ends its stream; a
  session disposes the camera it created.
- Initial release: route snapping, predict-and-correct motion
  (`RouteMotionEngine`, `FreeMotionEngine`), `FollowCamera`, turn-by-turn
  guidance with English and Vietnamese formatters, `NavigationSession`, and
  the `FixSource` / `RouteProvider` / `NavigationMap` extension points.
- `NavigationSession.pause()` / `resume()`: stop and restart the fix source
  without losing the route, the vehicle or the guidance progress.
- Fixes without a speed: the motion engines estimate it from the previous
  fixes, so the vehicle still moves smoothly.
- `RouteMotionEngine` stops trusting a reported speed that does not match
  how far the fixes move (mock-location apps often report 0), once the
  vehicle drifts 15 m from the fixes, and uses the estimate instead; the
  vehicle no longer falls behind and jumps ahead.
- `testing.dart`: `GpsSimulator`, `SimulatedFixSource`, `sampleRoute`.
- `NavigationSession.map` can be set after construction (map views attach
  themselves); the new map gets the route line at once.
- No reroute request while the session is paused.
- The speed estimate restarts after a gap of more than 10 s between fixes.
- `NavigationSession.guidance` emits null when guidance ends (route removed
  or motion reset).
- Trip data: per-segment durations (`segmentDurations`, else speed limits,
  else `fallbackSpeed`) with `duration`, `durationAt` and
  `remainingDuration`; `segmentSpeedLimits` and `speedLimitAt`;
  `summary`; `RouteStep.lanes` (`Lane`, `LaneDirection`).
- `RouteProvider` is an abstract class to extend: `routes()` returns
  alternatives (by default only the best route).
- `GuidanceFormatter.duration`, `clockTime` and `speed`, with English
  defaults and Vietnamese overrides.
- `SunTimes`: sunrise and sunset at a position, for day / night styles.
- `testing.dart`: `sampleRoute` gets durations, synthetic speed limits and
  lanes; `sampleRouteAlternatives`.
- `splitDuration` is exported, for third-party `GuidanceFormatter`s.
- `NavRoute.fromPoints` throws `ArgumentError` for a `fallbackSpeed` that is
  not positive and finite, and for invalid per-segment durations or speed
  limits.
- `GuidanceFormatter.speedValue` and `speedUnit` (whole km/h by default)
  let a UI show the number and the unit apart, and another unit such as mph;
  `speed()` composes them and reads as before.
- `testing.dart`: `GpsSimulator.setRoute(route, keepPosition: true)` places
  the car by its nearest point on the whole new route, for a switch onto a
  route that shares the road (an alternate picked mid trip); the default
  still searches the new route's first 150 m, as a reroute starts at the
  car.
- "Then" step: `GuidanceState.thenStep` now shows the next manoeuvre
  whenever the current step goes straight on (a depart, new name, continue
  or turn whose modifier is straight or none), however far it is (the
  arrival when no manoeuvre is left); otherwise the next manoeuvre within
  `NavGuidance.thenWithin`, whose default is now 300 m (was 100 m). Both
  skip straight-on steps, so it never reads "then continue straight"; a
  roundabout, ramp, fork, merge or end of the road is a manoeuvre even
  going straight.
  Speech keeps its 100 m reach: `GuidanceAnnouncement.thenStep` follows
  the new `NavGuidance.spokenThenWithin` (default 100 m) alone.
