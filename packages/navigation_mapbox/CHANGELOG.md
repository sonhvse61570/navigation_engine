## 0.1.0

- Initial release.
- `MapboxNavigationView` and `MapboxNavigationMap`: the follow camera, the
  route line (re-styled when `routeColors` change) and the vehicle image
  rendered at the device pixel ratio (`vehicleImage`). The compass and the
  scale bar are off; the logo and the attribution button keep above
  `bottomInset` (`placeOrnaments`).
- Night: `lightPreset` sets the Standard style's light preset without a
  style reload, and is applied first when a style loads, so a night start
  shows no day. `MapboxNavigationView.night` uses the Standard style's
  `night` preset, or loads `nightStyleUri` on other styles.
- Camera zooms (`CameraTarget`, `initialZoom`) use the Google Maps scale:
  the adapter shows them one level lower, as Mapbox's 512 px tiles need,
  so every provider frames a zoom alike.
- `MapboxNavigationMap` implements `RoutePreviewMap`: route options as
  GeoJSON sources and line layers (`navigation_engine_option_*`) below the
  session's route, the muted ones under the selected one; duration labels
  from `paintRouteLabel` in a symbol layer (`routeLabel`, `labelColors`);
  taps through tap interactions on the option and label layers only
  (`onRouteOptionTap`). Options survive style reloads, clearing removes
  their sources, layers and label images, colour changes restyle them,
  and `fitRoutes` accounts for the camera padding (with a pending fit).
- `MapboxStyleNavigation`: a complete navigation screen
  (`MapboxStyleFlowScaffold` of navigation_engine_flutter) on
  `MapboxNavigationView`; night is the Standard style's `night` light
  preset, or `nightStyleUri`; `onMapCreated` hands the app the map. The
  logo and the attribution stay above the panels.
- `MapboxNavigationMap` implements `AlternateRoutesMap`: one GeoJSON
  line layer (`navigation_engine_alternates`) under the route options and
  the route, in `alternateColor` and 70 % as wide, and bubbles
  (`alternateLabel`, `setAlternateLabelColors`) in a symbol layer at
  `min(divergence + 400 m, the middle of the rest)`; a tap on a line or a
  bubble calls `onTap`, unless it was drawn for an older list. A failed
  bubble render drops the bubbles and is reported through `FlutterError`.
- `MapboxNavigationMap` implements `SearchPinsMap` (`pinColor`,
  `pinPainter`; the shared `paintSearchPin`) and `DestinationPinMap`
  (`destinationPinPainter`; the shared `paintDestinationPin`): symbol
  layers above the route and below the vehicle, anchored at the pin's tip,
  in a fixed order whatever order they come in. Alternates, bubbles and
  pins are drawn again after a style reload (also on Standard with a light
  preset). A route option tap counts only while the line or label tapped
  stands for the option now at its index.
- `MapboxNavigationView.onMapTap` and `onMapLongPress`, and
  `MapboxNavigationMap.onMapTap` / `onMapLongPress`: tap and long-tap
  interactions on the map itself (`TapInteraction.onMap`,
  `LongTapInteraction.onMap`, added once per map). A tap on a feature the
  adapter draws is not a map tap (the layer interactions stop it, and a
  `MapTapGuard` drops the map tap of its gesture anyway); a map tap is
  delivered one turn of the event loop later. The web has no long tap.
  `MapboxStyleNavigation` forwards both.
- `MapboxNavigationView.horizontalFocus`, forwarded to
  `NavigationMapFrame`; the logo is placed bottom left and the attribution
  button bottom right on every platform (on Android the attribution moves
  from beside the logo to the bottom right), each kept clear of a side
  panel (`MapboxNavigationMap.setSideInsets`). The view also takes
  `alternateLabel`, `alternateColor`, `fasterLabelColors`,
  `slowerLabelColors` and `searchPinColor`, so a `GoogleStyleFlowScaffold`
  can drive it; it ignores the scaffold's traffic and satellite switches
  (the Standard style has no switch for them). `MapboxStyleNavigation`
  draws the alternates in its colours and words.
- `MapboxStyleNavigation` words and colours the alternates' bubbles with
  `alternateRouteLabel` and `alternateLabelColorsOf` from
  navigation_engine_flutter, shared with the other adapters (no visible
  change).
- The library re-exports the names its drop-in takes:
  `NavigationSession` and `GeoPoint` from navigation_engine;
  `NavigationFlowController`, `NavigationStrings`, `MapboxStyleColors`,
  `SpeedLimitSign`, `RouteColors`, `CarPuck` and `VehicleImageBuilder`
  from navigation_engine_flutter; and, for the map interfaces,
  `SearchPinsMap`, `DestinationPinMap`, `AlternateRoutesMap`,
  `AlongRoutePlace`, `AlternateRoute`, `paintSearchPin` and
  `paintDestinationPin`.
- A new selection restyles and reorders the route option lines in place
  and keeps the labels until the new ones are ready (no flicker); a failed
  layer move is reported and redone on the next update, and a clear still
  removes the layer. The label image cache drops the least recently used
  image.
- On the Standard style the view sets the light preset (`day` or
  `night`) at each style load; `MapboxNavigationMap.lightPreset` sets
  another one for a custom view.
- Alternate lines are drawn only where the alternate differs from the
  route (`alternateLinePoints`: 40 m before it leaves the route to 40 m
  after it rejoins it): a tap on the route where they share the road is a
  map tap on every adapter.
- `showAlternates([])` is `clearAlternates()`: no empty layer is left and
  the old bubbles go at once.
- The library re-exports `RouteLabelColors`, the type of the view's
  `labelColors`, `fasterLabelColors` and `slowerLabelColors`.
- Colours left unset come from the shared `MapDefaultColors` (the same
  values as before), so every adapter looks the same without them.
- Alternate bubbles are placed with `alternateLabelDistance`: on a short
  detour the bubble sits at the middle of the part that differs, on the
  drawn line, not on the road it shares with the route.
- `MapboxDirectionsRouteProvider`, a `RouteProvider` on the Directions API
  v5: `profile` (`MapboxDirectionsProfile.drivingTraffic`, the default,
  `driving`, `walking`, `cycling`), coordinates as `lon,lat` with full
  precision, `alternatives`, `steps=true`, `geometries` (`polyline6`, the
  default, or `geojson`), `overview=full`,
  `annotations=duration,distance` (plus `maxspeed` on the driving
  profiles, the only ones Mapbox documents it for), `bearings` from the
  heading (with none for the destination) and an optional `language` (the language of
  Mapbox's instruction text, which this package does not read). The answers
  are read by `navigation_osrm`'s `OsrmResponseParser`
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
  run on JavaScript (`flutter test --platform chrome --tags js`).
