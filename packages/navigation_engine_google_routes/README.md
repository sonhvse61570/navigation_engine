# navigation_engine_google_routes

[Google Maps Platform](https://developers.google.com/maps) routing and
search for [navigation_engine](https://pub.dev/packages/navigation_engine):
a `RouteProvider` on the
[Routes API](https://developers.google.com/maps/documentation/routes) v2,
and a `PlaceSearchProvider` on the
[Places API (New)](https://developers.google.com/maps/documentation/places/web-service/op-overview)
and the
[Geocoding API](https://developers.google.com/maps/documentation/geocoding/overview).
Pure Dart, on `http`; no Google SDK and no native code.

> **Show these results on a Google map.** Your use of these APIs is
> governed by the
> [Google Maps Platform Terms of Service](https://cloud.google.com/maps-platform/terms)
> and the
> [Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms).
> They forbid using Google Maps content, which includes the Routes and
> Places results this package returns, with a map that is not Google's
> ("No use with non-Google maps"). Draw the routes and places on a Google
> map, such as `navigation_engine_google_maps`'s, not on a Mapbox,
> MapLibre or OpenStreetMap map. The terms also limit what you may store
> or cache of the results, and set the attribution to show; this package
> caches nothing. (Customers with a billing address in the European
> Economic Area have different terms: check the ones that apply to you.)
> Read them for your use case before you ship.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_google_maps: ^0.1.0
  navigation_engine_google_routes: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';

final router = GoogleRoutesRouteProvider(apiKey: key, languageCode: 'vi');
final search = GooglePlacesSearch(
  apiKey: key,
  languageCode: 'vi',
  regionCodes: ['vn'],
);

final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

// On a Google map, as the terms ask.
GoogleStyleNavigation(session: session, flow: flow /* , ... */);

// A destination search field, in one billing session:
final searchSession = PlaceSearchSession();
final suggestions = await search.autocomplete(
  'Chợ Bến Thành',
  near: here,
  session: searchSession,
);
final place = await search.resolve(
  suggestions.first,
  session: searchSession, // ends the session
);
await flow.preview(to: place.position);

// When done:
router.close();
search.close();
```

## API key

Both classes take an `apiKey`. The Routes and Places APIs get it in the
`X-Goog-Api-Key` header; the Geocoding API, which takes no header, gets
it as the `key` query parameter.

These are Google Maps Platform **web services**, called with plain HTTP
requests, not through a Google SDK. That changes how a key can be
restricted (Google's
[API security best practices](https://developers.google.com/maps/api-security-best-practices)):

- **Enable the APIs and restrict the key to them.** Enable the Routes API,
  the Places API (New) and the Geocoding API (only those you use) for the
  key's project, with billing on, and give the key **API restrictions**
  that allow those APIs only. Use a key for this app alone, so that you
  can rotate it alone.
- **Android and iOS app restrictions work only if the app identifies
  itself, and even then only best effort.** Google's best practices list
  the Routes, Places (New) and Geocoding APIs under the API and IP-address
  restrictions for web services, and say "Android and iOS application
  restrictions may not be fully supported on older legacy Google Maps
  Platform services": treat the headers below as best effort, and a proxy
  holding an IP-restricted key (see below) as the dependable option. A key restricted to Android apps (package name and SHA-1
  certificate fingerprint) or iOS apps (bundle id) is accepted on a web
  service call only when the request carries the `X-Android-Package` and
  `X-Android-Cert` headers, or the `X-Ios-Bundle-Identifier` header. The
  SDKs send them; this package does not, so pass them through `headers`
  (the certificate is the SHA-1 digest in hexadecimal, without colons):

  ```dart
  final headers = Platform.isAndroid
      ? const {
          'X-Android-Package': 'com.example.app',
          // The signing certificate's SHA-1, as the key's restriction has it.
          'X-Android-Cert': 'DA39A3EE5E6B4B0D3255BFEF95601890AFD80709',
        }
      : const {'X-Ios-Bundle-Identifier': 'com.example.app'};
  final router = GoogleRoutesRouteProvider(apiKey: key, headers: headers);
  final search = GooglePlacesSearch(apiKey: key, headers: headers);
  ```

  Without them, a key with app restrictions gets HTTP 403 on every
  request. Anyone who reads the key from the app can send the same
  headers, so this only raises the bar.
- **The Geocoding API (`reverse`) needs its own arrangement.** It rejects
  keys with HTTP referrer restrictions ("API keys with referer restrictions
  cannot be used with this API"), and Google's best practices name a
  secure proxy for mobile use of it. Use one of:
  - a proxy that adds the key: point `geocodingBaseUrl` at it and pass
    `apiKey: null` (or a separate `GooglePlacesSearch` for the proxy);
  - a separate key restricted to the Geocoding API and to your proxy's or
    server's **IP addresses**;
  - or no `reverse` at all.
- **Web apps.** A key with HTTP referrer restrictions does not work with
  the Geocoding API (above). Use a proxy.
- **Recommended for mobile apps: a proxy.** A key in an app can be read by
  anyone. Google recommends a secure proxy between mobile clients and the
  web services: it holds an IP-restricted key, builds the requests
  itself rather than relaying arbitrary ones, and authenticates its
  clients. Point `routesBaseUrl`, `placesBaseUrl` and `geocodingBaseUrl`
  at it and pass `apiKey: null`, with your own credentials in `headers`:
  that is why those options exist.

How Google answers a key problem (the Routes and Places APIs): a missing
key, a disabled API, a restriction that refuses the request or billing
that is off is HTTP 403 `PERMISSION_DENIED`, a
`GoogleRoutesHttpException`; a key that is not valid is HTTP 400
`INVALID_ARGUMENT`, "API key not valid", a `GoogleRoutesStatusException`.
The Geocoding API answers `REQUEST_DENIED`, with HTTP 200.

The package keeps the key out of its exception messages. Server text it
quotes (an HTTP error body and reason phrase, Google's `status` and
`message`, the Geocoding `status` and `error_message`, a malformed value
in a route) has the key replaced by `REDACTED`, as it is and
percent-encoded, in case a server or proxy echoes it. An answer that is
not JSON gets a fixed message, and its `cause` keeps only the parser's
offset: on the web the parser's own message quotes the body around the
error, where part of a key could be. Transport errors (`http.ClientException`) carry the
request URL, which holds the key for the Geocoding API; the package
replaces it there, and in their message, with `REDACTED`.

## Billing

Google bills each API by SKU; see the
[pricing page](https://developers.google.com/maps/billing-and-pricing/pricing)
for the current rates and free monthly usage, and the
[SKU details](https://developers.google.com/maps/billing-and-pricing/sku-details)
for what triggers each one.

- **Routes (Compute Routes):** billed per request. Each `route()` or
  `routes()` call is one request, alternatives included.
  - **Reroutes cost two requests each.** A `NavigationSession` calls
    `route()` on every reroute, and a `NavigationFlowController` then
    calls `routes()` for alternatives (`fetchAlternatesOnReroute`, true by
    default): two billed requests. While the vehicle stays off the route
    they can repeat every `rerouteInterval` (10 seconds by default), up to
    about 720 requests an hour.
  - **Essentials:** a request that uses only basic features.
  - **Pro:** among others, `routingPreference` `TRAFFIC_AWARE` (the
    default here) and a waypoint `heading`. The engine passes the
    vehicle's bearing on every reroute and the flow controller passes the
    fix's heading when it previews a route, so by default the provider
    sends one (`sendHeading`, true by default).
  - **To cut the cost,** build the flow controller with
    `fetchAlternatesOnReroute: false` (one request per reroute), and to
    stay on Essentials build the provider with
    `routingPreference: GoogleRoutingPreference.trafficUnaware` **and**
    `sendHeading: false`, which sends no origin heading even though the
    engine passes one. (A route that starts in the right direction then
    depends on Google's own choice of the first road.)
  - **Enterprise:** among others, two-wheeler routing
    (`GoogleTravelMode.twoWheeler`).

  The field mask (`GoogleRoutesRouteProvider.fieldMask`) asks only for
  what the provider reads, as Google asks. None of its fields is listed
  among the Pro or Enterprise triggers (traffic on polylines, tolls and
  the like are not asked for), so it does not raise the SKU; a larger
  mask would only cost latency.
- **Places Autocomplete (New):** billed per session when the calls carry
  a session token. Create a `PlaceSearchSession` when the user starts
  typing, pass it to every `autocomplete` call and to the `resolve` of the
  chosen suggestion (its Place Details request ends the session), then
  create a new one: reuse one `PlaceSearchSession` for a whole search,
  never one per keystroke. Debounce `autocomplete` as the user types
  (about 300 ms), so that a session sends fewer requests: it bills its
  first 12 Autocomplete Requests, then the rest of the session is free.
  Google's
  [session pricing](https://developers.google.com/maps/documentation/places/web-service/session-pricing)
  depends on the fields of that Place Details request.
  - **By default, Essentials.** `resolve` asks for
    `id,formattedAddress,location` (`GooglePlacesSearch.detailsFieldMask`),
    Place Details Essentials fields, and names the place by the
    suggestion's title. Per the session pricing page, the terminating
    request is billed at the SKU "Places API Place Details Essentials",
    and the session's autocomplete requests at "Autocomplete Requests"
    up to a maximum of 12, then at "Autocomplete Session Usage" (no
    charge).
  - **`fetchDisplayName: true` leaves Essentials.** `resolve` then asks
    for `displayName` too (`detailsFieldMaskWithDisplayName`), a Place
    Details Pro field, and names the place by it. A session that ends
    with a Pro, Enterprise or Enterprise + Atmosphere Place Details
    request is billed differently, per the
    [session pricing page](https://developers.google.com/maps/documentation/places/web-service/session-pricing): its autocomplete requests at
    "Autocomplete Session Usage" (no charge), and the terminating request
    at the SKU "Place Details Enterprise + Atmosphere", whatever fields it
    asks for. That is the dearest Place Details SKU, not the Pro one.

  Calls without a session carry no token and are billed per request; a
  token used again after its session ended is billed as no token.
- **Geocoding (reverse):** billed per successful request (the Geocoding
  SKU, an Essentials SKU). It is the cheapest documented way to name a
  point: Nearby Search (New), the other candidate, is billed as Nearby
  Search Pro for the `displayName`, `formattedAddress` and `location`
  fields.

## Routes: `GoogleRoutesRouteProvider`

`POST {routesBaseUrl}/directions/v2:computeRoutes`, with the headers
`X-Goog-Api-Key` and `X-Goog-FieldMask: routes.distanceMeters,routes.duration,routes.staticDuration,routes.polyline.encodedPolyline,routes.routeLabels,routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.navigationInstruction`,
and the body:

```json
{
  "origin": {"location": {"latLng": {"latitude": 10.77243, "longitude": 106.69805}, "heading": 90}},
  "destination": {"location": {"latLng": {"latitude": 10.77978, "longitude": 106.69902}}},
  "travelMode": "DRIVE",
  "routingPreference": "TRAFFIC_AWARE",
  "computeAlternativeRoutes": true,
  "languageCode": "vi",
  "polylineQuality": "HIGH_QUALITY",
  "polylineEncoding": "ENCODED_POLYLINE"
}
```

- `heading` is the heading `route()` and `routes()` receive, as an
  integer from 0 to 359, on the origin only; a heading that is null or
  not finite sends none, as does a provider built with
  `sendHeading: false`.
- `routingPreference` is sent with both travel modes: the docs allow it
  with `DRIVE` and `TWO_WHEELER`.
- `computeAlternativeRoutes` is `false` for `route()` and for
  `routes(maxAlternatives: 0)`, else `true`; Google sends up to two
  alternatives.
- `languageCode` is sent only when set.

| Option | Default | |
| --- | --- | --- |
| `apiKey` | required | The key, or null to send none (a proxy adds it). |
| `routesBaseUrl` | `https://routes.googleapis.com` | A path prefix and query parameters are kept. |
| `travelMode` | `GoogleTravelMode.drive` | `drive` (`DRIVE`) or `twoWheeler` (`TWO_WHEELER`, a motorbike; Google asks apps to tell users these routes are in beta). |
| `routingPreference` | `GoogleRoutingPreference.trafficAware` | `trafficAware` (`TRAFFIC_AWARE`) or `trafficUnaware` (`TRAFFIC_UNAWARE`). |
| `languageCode` | none (Google's choice) | The instructions' language, such as `vi`; road names are read from them. |
| `alternatives` | `true` | False: `routes()` never asks for alternatives. |
| `sendHeading` | `true` | False: the origin never carries the vehicle's heading, even when the engine passes one; with `trafficUnaware`, a route request stays on the Essentials tier. |
| `headers` | none | Added to every request, after the package's own, which they may replace. |
| `timeout` | 12 s | Bounds each request, the body included; the request is then aborted. |
| `userAgent` | `navigation_engine_google_routes/0.1.0`; null on the web | Null sends none. On the web it defaults to null: a browser would send a CORS preflight. |
| `client` | a new `http.Client` | Injected clients stay yours to close; `close()` closes only the one the provider created. |

What a route holds:

- **Alternatives:** `routes[0]` is the best route (`DEFAULT_ROUTE`), the
  others alternatives (`DEFAULT_ROUTE_ALTERNATE`), in Google's order, up
  to `maxAlternatives + 1`.
- **Geometry:** the steps' polylines (precision 5, decoded with the core's
  `decodePolyline`) joined, a point two steps share kept once. When no
  step has a polyline, the route's polyline, with a departure and an
  arrival only.
- **Steps:** one `RouteStep` where each step starts, its `maneuver`
  mapped as below. A first step without a `maneuver` departs. The arrival
  is placed at the last point (a `DESTINATION` step is not a step of its
  own).
- **Road names (best effort):** Routes v2 sends no road name field, so
  the name is read from the step's `instructions`. Any tags are stripped
  and only the first line is read (later lines are notes such as
  "Destination will be on the left"). The name is what follows the last
  "onto" (Vietnamese "vào", "sang", "đi tiếp"), else the last "on"
  ("trên"), up to a comma or a phrase that says where the road leads
  ("toward", "về phía", "theo hướng"): "Turn left onto Pasteur" gives
  `Pasteur`, "Rẽ trái vào Pasteur" too. Otherwise the step has no road
  name. Other languages' instructions give none, so pass `languageCode`
  `en` or `vi` when you want road names.
- **Durations:** each step's `staticDuration` (`"123s"`, `"12.5s"`: any
  other form is a `GoogleRoutesFormatException`) is spread over its
  segments by length, then scaled so that the route takes its `duration`
  (its traffic-aware time, with `TRAFFIC_AWARE`; its `staticDuration` when
  it has no `duration`). A missing `distanceMeters` or `staticDuration` is
  0: Google omits zero values. With no time at all, the engine estimates.
- **Name:** `Google {distanceMeters} m`. The summary is the road the steps
  follow for the longest distance.
- **No lanes and no speed limits:** Routes v2 provides neither, so the
  routes have none (the engine estimates speeds where it needs them).

Manoeuvres, for every value of the documented `Maneuver` enum:

| `maneuver` | `ManeuverType` | `ManeuverModifier` |
| --- | --- | --- |
| `DEPART` (or none, on the first step) | `depart` | `none` |
| `TURN_LEFT`, `TURN_RIGHT` | `turn` | `left`, `right` |
| `TURN_SLIGHT_LEFT`, `TURN_SLIGHT_RIGHT` | `turn` | `slightLeft`, `slightRight` |
| `TURN_SHARP_LEFT`, `TURN_SHARP_RIGHT` | `turn` | `sharpLeft`, `sharpRight` |
| `UTURN_LEFT`, `UTURN_RIGHT` | `turn` | `uturn` |
| `STRAIGHT` | `continueOn` | `straight` |
| `RAMP_LEFT`, `RAMP_RIGHT` | `onRamp` | `slightLeft`, `slightRight` |
| `FORK_LEFT`, `FORK_RIGHT` | `fork` | `slightLeft`, `slightRight` |
| `MERGE` | `merge` | `none` |
| `ROUNDABOUT_LEFT`, `ROUNDABOUT_RIGHT` | `roundabout` | `left`, `right` |
| `NAME_CHANGE` | `newName` | `none` |
| `FERRY`, `FERRY_TRAIN`, `MANEUVER_UNSPECIFIED`, none | `continueOn` | `none` |
| `DESTINATION` | the arrival, at the last point | |
| any other value | `turn` | `none` |

## Place search: `GooglePlacesSearch`

It takes the same `apiKey`, `headers`, `timeout`, `userAgent` and
`client` options, and:

| Option | Default | |
| --- | --- | --- |
| `placesBaseUrl` | `https://places.googleapis.com` | For `autocomplete` and `resolve`. |
| `geocodingBaseUrl` | `https://maps.googleapis.com` | For `reverse`. |
| `proximity` | none | Biases the suggestions towards a position when `autocomplete` has no `near`. |
| `biasRadius` | 20 000 m | The bias circle's radius: more than 0, at most 50 000. |
| `regionCodes` | none | Up to 15 CLDR two-letter codes, such as `vn` (`includedRegionCodes`). |
| `languageCode` | none | Such as `vi`. Sent to every request. |
| `fetchDisplayName` | `false` | True: `resolve` asks for `displayName` (a Pro field) and names the place by it; a session it ends is billed at the "Place Details Enterprise + Atmosphere" SKU (see "Billing"). |

- `autocomplete(query, near:, session:)` sends
  `POST {placesBaseUrl}/v1/places:autocomplete`. The body is `input`,
  `sessionToken` (the session's token; none without a session),
  `languageCode`, `includedRegionCodes`, and
  `locationBias.circle` (`center` from `near`, else `proximity`, and
  `radius` from `biasRadius`). An empty query returns nothing without a
  request. Each `placePrediction` becomes a suggestion: `placeId` as the
  `id`, `structuredFormat.mainText` (else `text`) as the `title`, and
  `structuredFormat.secondaryText` as the `subtitle`. They have **no
  position**. `queryPrediction`s (a query, not a place) are left out.
- `resolve(suggestion, session:)` sends
  `GET {placesBaseUrl}/v1/places/{placeId}?sessionToken=…&languageCode=…`
  with `X-Goog-FieldMask: id,formattedAddress,location` (Essentials). The
  place has its `location` and its `formattedAddress`, and is named by the
  suggestion's title (else its address). With `fetchDisplayName: true`,
  the mask is `id,displayName,formattedAddress,location` and the
  place is named by its `displayName.text` (else as without it). It ends
  the session.
- `reverse(point)` sends
  `GET {geocodingBaseUrl}/maps/api/geocode/json?latlng={lat},{lng}&key=…&language=…`
  ([reverse geocoding](https://developers.google.com/maps/documentation/geocoding/requests-reverse-geocoding)).
  The place is the first result: its `formatted_address` (as its name and
  address), its `place_id` and its `geometry.location`. `ZERO_RESULTS` is
  null. Any other status but `OK` (`REQUEST_DENIED`, `OVER_QUERY_LIMIT`,
  `INVALID_REQUEST`, `UNKNOWN_ERROR`, …) fails, with Google's
  `error_message`. This is the cheapest documented reverse lookup (see
  "Billing").

## Errors

The route provider throws a `GoogleRoutesException`:

| Exception | When |
| --- | --- |
| `GoogleRoutesNoRouteException` | Google found no route: its answer has no `routes` (it answers `{}`). `statusCode` is 200. |
| `GoogleRoutesStatusException` | A Google RPC error, `{"error": {"code", "message", "status"}}`, with any HTTP error but 401 and 403: 400 `INVALID_ARGUMENT` (a bad request, or a key that is not valid: "API key not valid"), 404 `NOT_FOUND`, 429 `RESOURCE_EXHAUSTED`, 5xx `INTERNAL` or `UNAVAILABLE`, … `statusCode`, `status` and the server's message (`serverMessage`) are kept. For the search, also a Geocoding `status` other than `OK` and `ZERO_RESULTS`, with HTTP 200. |
| `GoogleRoutesHttpException` | Always for a 403 (`PERMISSION_DENIED`: a missing key, an API that is not enabled, key restrictions that refuse the request, or billing that is off) and a 401 (`UNAUTHENTICATED`: no valid credentials), with Google's `status` and message when the body has them; and any other HTTP error whose body is not a Google error (a proxy's, say), quoting the start of the body. |
| `GoogleRoutesTimeoutException` | No full answer within `timeout`. It is also a `TimeoutException`. |
| `GoogleRoutesFormatException` | The answer is not UTF-8, not JSON, or not shaped as Google's; the message names the field. For an answer that is not JSON, the message is fixed and the `cause` (a `FormatException`) keeps only the offset. |

The messages never hold the key. Transport failures (offline, DNS, TLS)
arrive as the `http` client throws them, usually as
`http.ClientException`. A point that is not finite throws `ArgumentError`,
and a closed provider throws `StateError`, both before any request.

The place search throws a `GooglePlacesSearchException`, the
`PlaceSearchException` its interface promises (`Google autocomplete
failed`, `Google place details failed`, `Google reverse geocoding
failed`). Its `cause` says why: one of the exceptions above, or the
client's error (also a transport failure); its `statusCode` is the
cause's HTTP status.

## Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network and no key needed.
The package's own tests work that way, on fixtures hand-written to the
documented answers (none was recorded). Tests of what differs under
dart2js (the polyline decoding, the coordinates' text, the key scrub, the
web's `User-Agent`) also run on node:

```sh
dart test -p node -t js
```

A live smoke check against Google runs only with a key in the environment
(six requests, billed to the key's project; the key must allow the three
APIs). It fetches a raw Routes answer in Ho Chi Minh City and fails on any
`maneuver` the package does not map, printing the values and the
instructions it saw; it also checks real routes, a Places session and a
reverse geocoding:

```sh
GOOGLE_ROUTES_KEY=... dart test -t live
```

Without the key those tests are skipped. The example
(`example/bin/main.dart`) also makes live requests with the same variable.
