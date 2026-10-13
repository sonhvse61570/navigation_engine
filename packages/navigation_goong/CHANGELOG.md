## 0.1.0

- Initial release.
- `GoongStyles.url(style, mapTilesKey:)`: the style JSON URLs of Goong's
  `map` (`goong_map_web`, the default), `highlight`, `satellite`, and the
  `dark`, `navigationDay` and `navigationNight` styles, which only Goong's
  older docs list and which may not exist (`GoongStyle.mayNotExist`), with
  the Maptiles key in the query; and `GoongStyles.attribution`, `© Goong`.
- `GoongRouteProvider`, a `RouteProvider` on direction v2: `origin`,
  `destination` (lat,lng), `vehicle` (`car`, `bike`, `taxi`, `truck`,
  `hd`) and `alternatives`. Direction v2 takes no heading, so a reroute
  may suggest a U-turn. Each route of the Google-Directions-shaped answer
  becomes a `NavRoute`: the steps' precision-5 polylines joined, the shared
  joint points kept once; a step where each one starts, the first one the
  departure, with Google's `maneuver` strings (and Goong's own, such as
  `slight right`) mapped to manoeuvres, and the road name from a step
  `name` or from `html_instructions` (tags stripped, entities decoded, the
  `<b>` segment after "onto" or "on", or the words after "vào", "trên",
  "theo" or "từ"); an arrival at the end; and each step's
  `duration.value` spread over its segments by length.
- `GoongPlaceSearch`, a `PlaceSearchProvider`: autocomplete v2 (suggestions
  with a `place_id` and no position), `resolve` through place detail v2,
  and `reverse` through geocode v2 (`latlng`). A `PlaceSearchSession`'s
  token is sent as `sessiontoken` to autocomplete and place detail; a
  successful `resolve` ends the session.
- Both take `apiKey` (null sends none, for a proxy that adds it),
  `baseUrl`, `headers`, `timeout` (12 s, after which the request is
  aborted), `userAgent` (null by default on the web, to avoid a CORS
  preflight) and an injected `http.Client`; `close()` closes only a client
  they created.
- Typed errors: `GoongCodeException` (Goong's `status` / `error_message`,
  or an `error` object), `GoongHttpException` (with hints for 401, 403 and
  429), `GoongTimeoutException` (also a `TimeoutException`) and
  `GoongFormatException` (the message names the field); the search wraps
  them in `GoongSearchException`, a `PlaceSearchException`. The key is
  replaced by `REDACTED` (raw or percent-encoded) in every server string
  an exception quotes (the code, the server message, the reason phrase,
  the body) and in a transport error's URL and message.
- An answer that is not JSON gets the fixed message `invalid JSON`, and
  `GoongFormatException.cause` is a `FormatException` that keeps only the
  parser's offset: on the web the parser's own message quotes the body
  around the error, where part of the key could be.
- Works on the web: polylines are decoded with the core's
  `decodePolyline`, which is safe under dart2js, and the instruction
  parser's regular expressions are checked on JavaScript too
  (`dart test -p node -t js`).
