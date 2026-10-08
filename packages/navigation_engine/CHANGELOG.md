## 0.1.0

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
