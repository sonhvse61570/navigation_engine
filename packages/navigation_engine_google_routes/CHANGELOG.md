## 0.1.0

- Initial release.
- `GoogleRoutesRouteProvider`, a `RouteProvider` on the Routes API v2
  (`POST /directions/v2:computeRoutes`): the key in `X-Goog-Api-Key`, a
  minimal `X-Goog-FieldMask` (`GoogleRoutesRouteProvider.fieldMask`), and
  a body with the origin and destination `latLng`, the origin's `heading`
  (an integer 0 to 359) when known, `travelMode` (`GoogleTravelMode.drive`,
  the default, or `twoWheeler`), `routingPreference`
  (`GoogleRoutingPreference.trafficAware`, the default, or
  `trafficUnaware`), `computeAlternativeRoutes`, an optional
  `languageCode`, `polylineQuality: HIGH_QUALITY` and
  `polylineEncoding: ENCODED_POLYLINE`. The routes keep Google's order;
  the step polylines are joined (each shared point kept once), else the
  route polyline is used; every documented `Maneuver` value is mapped
  (none on the first step departs, an unknown one is a turn); road names
  are read from the instructions, best effort (English and Vietnamese);
  the arrival is the last point; each step's `staticDuration` is spread
  over its segments by length and scaled to the route's `duration`.
  Routes v2 has no lanes and no speed limits.
- `GooglePlacesSearch`, a `PlaceSearchProvider`: Places API (New)
  `places:autocomplete` for `autocomplete` (place predictions only, with
  the `PlaceSearchSession`'s token as `sessionToken`, `languageCode`,
  `includedRegionCodes` and a `locationBias` circle), `places/{placeId}`
  with the Essentials field mask `id,formattedAddress,location` for
  `resolve` (ending the session; the place is named by the suggestion's
  title, or, with `fetchDisplayName: true`, by its `displayName`, a Pro
  field, with which a session ends at the "Place Details Enterprise +
  Atmosphere" SKU), and the Geocoding API's reverse
  geocoding (`latlng`, the cheapest documented option) for `reverse`.
- Both take `apiKey` (null sends none, for a proxy that adds it), base
  URLs (`routesBaseUrl`; `placesBaseUrl` and `geocodingBaseUrl`),
  `headers`, `timeout` (12 s, after which the request is aborted),
  `userAgent` (null by default on the web, to avoid a CORS preflight) and
  an injected `http.Client`; `close()` closes only a client they created.
  The search checks its options before it creates a client.
- Typed errors: `GoogleRoutesNoRouteException` (no route, the `{}`
  answer), `GoogleRoutesStatusException` (a Google RPC error other than
  401 and 403, or a Geocoding error status; with `statusCode`, `status`
  and the server's message), `GoogleRoutesHttpException` (always for 401
  and 403, with Google's status and message when sent (a missing key is a
  403; a key that is not valid is a 400 `INVALID_ARGUMENT`, a status
  exception); and HTTP errors
  that are not Google's), `GoogleRoutesTimeoutException` (also a
  `TimeoutException`) and `GoogleRoutesFormatException` (the message
  names the field; durations other than `"123s"` or `"12.5s"` are one);
  the search wraps them in `GooglePlacesSearchException`, a
  `PlaceSearchException`. The key is replaced by `REDACTED` (raw or
  percent-encoded) in every server string an exception quotes (the
  status, the server message, the reason phrase, the body, a malformed
  value) and in a transport error's URL and message. An answer that is
  not JSON gets a fixed message whose `cause` keeps only the parser's
  offset, since the web's parser quotes the body around the error.
- `sendHeading` (true by default) on `GoogleRoutesRouteProvider`: false
  sends no origin `heading`, even when the engine passes one, so that
  `GoogleRoutingPreference.trafficUnaware` can stay on the Essentials SKU.
  The Billing section explains that a reroute is two requests when the
  flow controller fetches alternatives.
- Works on the web: polylines are decoded with the core's
  `decodePolyline`, which is safe under dart2js, and coordinates are
  written the same as on the VM; those tests and the key scrub's also run
  on JavaScript (`dart test -p node -t js`).
