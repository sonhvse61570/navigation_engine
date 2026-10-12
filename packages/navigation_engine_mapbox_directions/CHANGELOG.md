## 0.1.0

- Initial release.
- `MapboxDirectionsRouteProvider`, a `RouteProvider` on the Directions API
  v5: `profile` (`MapboxDirectionsProfile.drivingTraffic`, the default,
  `driving`, `walking`, `cycling`), coordinates as `lon,lat` with full
  precision, `alternatives`, `steps=true`, `geometries` (`polyline6`, the
  default, or `geojson`), `overview=full`,
  `annotations=duration,distance` (plus `maxspeed` on the driving
  profiles, the only ones Mapbox documents it for), `bearings` from the
  heading (with none for the destination) and an optional `language` (the language of
  Mapbox's instruction text, which this package does not read). The answers
  are read by `navigation_engine_osrm`'s `OsrmResponseParser`
  (`providerName: 'Mapbox'`): manoeuvres, road names, lanes, durations
  scaled to each leg, and, on the driving profiles, per-segment speed
  limits from `maxspeed` (`km/h` and `mph`; `unknown` and `none` as no
  limit).
  `voiceInstructions` and `bannerInstructions` are ignored.
- `MapboxSearch`, a `PlaceSearchProvider` on the Search Box API:
  `/suggest` for `autocomplete` (category suggestions left out), `/retrieve/{mapbox_id}` for `resolve`, both with the
  `PlaceSearchSession`'s token as `session_token` (a fresh token without
  one), and `/reverse` for `reverse`; with `proximity`, `country`,
  `language` and `limit` options.
- Both take `accessToken` (null sends none, for a proxy that adds it),
  `baseUrl`, `headers`, `timeout` (12 s, after which the request is
  aborted), `userAgent` (null by default on the web, to avoid a CORS
  preflight) and an injected `http.Client`; `close()` closes only a client
  they created.
- Typed errors: `MapboxDirectionsCodeException` (a `code` other than
  `Ok`, with its `message` and HTTP status), `MapboxDirectionsHttpException`
  (always for 401 and 403, even with a `code` in the body; with hints
  for 401, 403, 422 and 429), `MapboxDirectionsTimeoutException`
  (also a `TimeoutException`) and `MapboxDirectionsFormatException` (the
  message names the field; for a route, its `cause` is the parser's
  `OsrmFormatException`); the search wraps them in `MapboxSearchException`,
  a `PlaceSearchException`. The token is replaced by `REDACTED` (raw or
  percent-encoded) in every server string an exception quotes (the code,
  the server message, the reason phrase, the body) and in a transport
  error's URL and message. An answer that is not JSON gets a fixed message
  whose `cause` keeps only the parser's offset, since the web's parser
  quotes the body around the error.
- Works on the web: polylines are decoded with the core's
  `decodePolyline`, which is safe under dart2js, and coordinates are
  written the same as on the VM; those tests and the token scrub's also
  run on JavaScript (`dart test -p node -t js`).
