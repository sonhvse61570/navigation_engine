## 0.1.0

- Initial release.
- `VietmapStyles.url(style, apiKey:)`: the `style.json` URLs of Vietmap's
  `tm` (street, the default), `lm` (light), `dm` (dark, for night) and
  `hm` (hybrid) styles, with the tile key in the query; and
  `VietmapStyles.attribution`, `© VIETMAP`, since the styles carry none.
- `VietmapRouteProvider`, a `RouteProvider` on route v4: two `point`s
  (lat,lng), `vehicle` (`car`, `motorcycle`, `truck` with its `capacity`,
  `container`), `alternative`, `heading` and `points_encoded=true`. Each
  path becomes a route: the precision-5 polyline; a step per instruction,
  at the start of its `interval`, with GraphHopper's `sign` codes mapped to
  manoeuvres and `street_name` (else `street_ref`) as the road; and each
  instruction's `time` spread over its interval by length as per-segment
  durations (the path's `time` spread over the path when the intervals do
  not tile it).
- `VietmapPlaceSearch`, a `PlaceSearchProvider`: autocomplete v4
  (suggestions with a `ref_id` and no position), `resolve` through place
  v4, and `reverse` through reverse v4.
- Both take `apiKey` (null sends none, for a proxy that adds it),
  `baseUrl`, `headers`, `timeout` (12 s, after which the request is
  aborted), `userAgent` (null by default on the web, to avoid a CORS
  preflight) and an injected `http.Client`; `close()` closes only a client
  they created.
- Typed errors: `VietmapCodeException` (Vietmap codes such as
  `ZERO_RESULTS`), `VietmapHttpException` (with hints for 401, 403, 423 and
  429), `VietmapTimeoutException` (also a `TimeoutException`) and
  `VietmapFormatException` (the message names the field); the search wraps
  them in `VietmapSearchException`, a `PlaceSearchException`. The key is
  replaced by `REDACTED` (raw or percent-encoded) in every server string
  an exception quotes (the code, the messages, the reason phrase, the
  body) and in a transport error's URL and message; a malformed field is
  described, never quoted.
- Works on the web: the polyline decoder is safe under dart2js (its tests
  also run on node, `dart test -p node -t js`).
