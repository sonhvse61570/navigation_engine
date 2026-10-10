## 0.1.0

- Initial release.
- `OsrmRouteProvider`, a `RouteProvider` on an OSRM server's route
  service. `route()` asks for one route and `routes(maxAlternatives:)` for
  the best route and up to N alternatives (`alternatives=N`), with
  `steps=true` and `overview=full`; a heading is sent as the start's
  `bearings`.
- Options: `baseUrl` (default `demoServer`, OSRM's public demo server,
  which is for testing only: rate limited, and it sees the coordinates),
  `profile` (`driving`), `speedLimits` (default false:
  `annotations=duration,distance`; on: `annotations=true`, the only way
  OSRM sends `maxspeed`, for servers that send it; mainline OSRM and the
  demo server do not),
  `timeout` (12 s, after which the request is
  aborted), `geometries` (`geojson` or `polyline6`), `userAgent` (null by default
  on the web, to avoid a CORS preflight) and an
  injected `http.Client`. `close()` closes only a client the provider
  created.
- Steps become `RouteStep`s placed along the route: manoeuvre type and
  modifier (roundabout and rotary entries and exits, fork, merge, ramps,
  new name, continue, depart, arrive; unknown types as turns), road name
  falling back to `ref`, and lanes from the manoeuvre's intersection.
  Per-segment durations come from the annotations, scaled to each leg's
  duration; speed limits from `maxspeed` (km/h or mph; unknown and none
  are no limit) when the server sends it.
- Failures throw a sealed `OsrmException`: `OsrmCodeException` (OSRM
  codes such as `NoRoute` and `NoSegment`), `OsrmHttpException`,
  `OsrmTimeoutException` (also a `TimeoutException`) and
  `OsrmFormatException` (the message names the malformed field).
- Works on the web: the `polyline6` decoder is safe under dart2js (its
  tests also run on node, `dart test -p node -t js`).
