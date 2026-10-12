# navigation_engine_mapbox_directions

[Mapbox](https://www.mapbox.com) routing and search for
[navigation_engine](https://pub.dev/packages/navigation_engine): a
`RouteProvider` on the
[Directions API](https://docs.mapbox.com/api/navigation/directions/) v5,
with lanes, per-segment durations and speed limits, and a
`PlaceSearchProvider` on the
[Search Box API](https://docs.mapbox.com/api/search/search-box/). Pure
Dart, on `http`; no Mapbox SDK and no native code. It works with any map
adapter; with `navigation_engine_mapbox` it completes a Mapbox-only stack.

Mapbox's Directions answers are in OSRM's format, so this package reads
them with `navigation_engine_osrm`'s `OsrmResponseParser`: steps,
manoeuvres, lanes and durations read exactly as OSRM's do.

> **Check Mapbox's terms before production use.** Your use of these APIs
> is governed by the [Mapbox Terms of Service](https://www.mapbox.com/legal/tos)
> and the [Product Terms](https://www.mapbox.com/legal/product-terms),
> which set what you may store or cache of the results, whether they may
> be shown on a map that is not Mapbox's, and the attribution you must
> show. Read them for your use case (and ask Mapbox when in doubt) before
> you ship; this package does not cache any answer.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_mapbox: ^0.1.0
  navigation_engine_mapbox_directions: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';
import 'package:navigation_engine_mapbox_directions/navigation_engine_mapbox_directions.dart';

final router = MapboxDirectionsRouteProvider(
  accessToken: token, // a public pk. token (see "Tokens")
  language: 'vi',
);
final search = MapboxSearch(accessToken: token, language: 'vi', country: 'vn');

final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

MapboxStyleNavigation(session: session, flow: flow /* , ... */);

// A destination search field, in one billing session:
final searchSession = PlaceSearchSession();
final suggestions = await search.autocomplete(
  'Hồ Hoàn Kiếm',
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

## Tokens

Both classes take an `accessToken`, sent as the `access_token` query
parameter. A **public token** (`pk.`) is enough: the Directions and Search
Box APIs need no secret scope, and a public token's default scopes work.
Never ship a secret token (`sk.`) in an app.

A public token in an app can be read by anyone, so:

- use a token for this app only, so that you can rotate it without
  touching your other apps;
- on the web, add URL restrictions to it in your Mapbox account (requests
  from other sites then answer HTTP 403). Mapbox calls them best effort,
  and they do not apply to mobile apps;
- or keep the token on your server: point `baseUrl` at a proxy that adds
  it, and pass `accessToken: null`. That is why `baseUrl` and `headers`
  can be set.

The package keeps the token out of its exception messages. Server text it
quotes (an HTTP error body and reason phrase, Mapbox's `code` and its
`message`) has the token replaced by `REDACTED`, as it is and
percent-encoded, in case a server or proxy echoes it. Transport errors
(`http.ClientException`) carry the request URL; the package replaces the
token in it, and in their message, with `REDACTED`.

## Billing

Check Mapbox's [pricing page](https://www.mapbox.com/pricing) for the
current free tiers and rates.

- **Directions:** billed per request. Each `route()` or `routes()` call
  is one request, alternatives included.
  - **Reroutes cost two requests each.** A `NavigationSession` calls
    `route()` on every reroute, and a `NavigationFlowController` then
    calls `routes()` for alternatives (`fetchAlternatesOnReroute`, true by
    default): two billed requests. While the vehicle stays off the route
    they can repeat every `rerouteInterval` (10 seconds by default), up to
    about 720 requests an hour.
  - **To cut the cost,** build the flow controller with
    `fetchAlternatesOnReroute: false`, which leaves one request per
    reroute.
- **Search Box `/suggest` and `/retrieve`:** billed per **session**. A
  session is any number of `/suggest` calls (up to 50) then one
  `/retrieve`, all with the same `session_token`; a session also ends
  when no `/retrieve` follows within 180 seconds. Create a
  `PlaceSearchSession` when the user starts typing, pass it to every
  `autocomplete` call and to the `resolve` of the chosen suggestion, then
  create a new one: reuse one session for a whole search, never one per
  keystroke. Debounce `autocomplete` as the user types (about 300 ms):
  Search Box allows 10 requests per second, and a session ends after 50
  `/suggest` calls. Mapbox requires a token on both calls, so a call made
  without a session gets a fresh token, and is billed as a session of its
  own.
- **Search Box `/reverse`:** billed per request.

## Routes: `MapboxDirectionsRouteProvider`

`GET {baseUrl}/directions/v5/mapbox/{profile}/{lon},{lat};{lon},{lat}?alternatives=…&steps=true&geometries=polyline6&overview=full&annotations=duration,distance[,maxspeed][&bearings={heading},45;][&language=…]&access_token=…`

- Coordinates are `lon,lat`, with every digit the `double` has (no
  rounding, no exponent).
- `annotations` adds `maxspeed` on the driving profiles only
  (`drivingTraffic`, `driving`): Mapbox documents it for those alone.
  Walking and cycling ask for `duration,distance`.
- `alternatives` is `false` for `route()` and for
  `routes(maxAlternatives: 0)`, else `true`; Mapbox sends up to two.
- The heading `route()` and `routes()` receive becomes the origin's
  `bearings` (`{heading},45`), so the route leaves the way the vehicle
  faces; the destination has none (the trailing `;`). A heading that is
  null or not finite sends no `bearings`.

| Option | Default | |
| --- | --- | --- |
| `accessToken` | required | The token, or null to send none (a proxy adds it). |
| `baseUrl` | `https://api.mapbox.com` | A path prefix and query parameters are kept. |
| `profile` | `MapboxDirectionsProfile.drivingTraffic` | `drivingTraffic` (`driving-traffic`), `driving`, `walking`, `cycling`. |
| `geometries` | `OsrmGeometries.polyline6` | `polyline6` (compact) or `geojson` (about three times larger). |
| `language` | none (English) | The language of Mapbox's turn-by-turn instruction text, such as `vi`. This package does not read that text (the engine words its own guidance), so the option does not change the returned routes, road names included; it is kept for parity with Mapbox's API. |
| `alternatives` | `true` | False: `routes()` never asks for alternatives. |
| `headers` | none | Added to every request (a proxy's token, say). They may replace `Accept` and `User-Agent`. |
| `timeout` | 12 s | Bounds each request, the body included; the request is then aborted. |
| `userAgent` | `navigation_engine_mapbox_directions/0.1.0`; null on the web | Null sends none. On the web it defaults to null: a browser would send a CORS preflight. |
| `client` | a new `http.Client` | Injected clients stay yours to close; `close()` closes only the one the provider created. |

What a route holds (see `navigation_engine_osrm`'s README for the
details of the parser):

- **Alternatives:** every `routes[]` entry, best first, up to
  `maxAlternatives + 1`.
- **Geometry:** the route's `geometry`, a precision-6 polyline or GeoJSON.
- **Steps:** one `RouteStep` at each step's `maneuver.location`, with its
  type and modifier (a type the parser does not know is a turn), its road
  name (`name`, else `ref`) and the lanes of its first intersection.
- **Lanes:** each lane's `indications`; a `valid` lane follows its
  `valid_indication` (else the manoeuvre's direction). Mapbox's
  lane-level `active` flag (a preferred lane, sent on `mapbox/driving`)
  is not read: the core `Lane` has no "preferred" field.
- **Durations:** the `duration` annotations, scaled so that each leg sums
  to its `duration`.
- **Speed limits** (driving profiles only): the `maxspeed` annotations,
  per segment: `{speed, unit}` in `km/h` or `mph` (converted), and
  `{unknown: true}` or `{none: true}` as no limit. Mapbox marks `maxspeed`
  as beta, and it is not sent on every road: the engine then estimates.
  Walking and cycling routes have none.
- **Summary and name:** the legs' `summary` values, joined; the name is
  `Mapbox {distance} m`.
- `voiceInstructions` and `bannerInstructions` are not asked for, and
  ignored if sent.

## Place search: `MapboxSearch`

It takes the same `accessToken`, `baseUrl`, `headers`, `timeout`,
`userAgent` and `client` options, and:

| Option | Default | |
| --- | --- | --- |
| `proximity` | none | Biases the suggestions towards a position when `autocomplete` has no `near`. |
| `country` | none | ISO 3166 alpha-2 codes, comma-separated, such as `vn` or `vn,la`. Sent to `/suggest` and `/reverse`. |
| `language` | none | An ISO 639-1 code, such as `vi`. Sent to every request. |
| `limit` | none (Mapbox's default) | The most suggestions, 1 to 10. |

- `autocomplete(query, near:, session:)` calls
  `/search/searchbox/v1/suggest` (`q`, `session_token`, `proximity={lon},{lat}`,
  `country`, `language`, `limit`). An empty query returns nothing without
  a request. Suggestions have the `mapbox_id` as their `id`, the `name` as
  their `title`, the `place_formatted` as their `subtitle`, and **no
  position**. Category suggestions (`feature_type` `category`, such as
  "Park"), which are not one place, are left out.
- `resolve(suggestion, session:)` calls
  `/search/searchbox/v1/retrieve/{mapbox_id}` (`session_token`,
  `language`). The place is the first feature: its point, its `name`
  (else the suggestion's title), and its `full_address` (else its
  `place_formatted`) as its address.
- `reverse(point)` calls `/search/searchbox/v1/reverse` (`longitude`,
  `latitude`, `country`, `language`, `limit=1`) and returns the first
  feature Mapbox returns, named by its `name` (else its address), or null
  when there is none. (The docs do not say how `/reverse` orders its
  features.) It is the Search Box's
  own reverse endpoint, so that one token and one API serve the whole
  search field.

## Errors

The route provider throws a `MapboxDirectionsException`:

| Exception | When |
| --- | --- |
| `MapboxDirectionsCodeException` | Mapbox answered with a `code` other than `Ok`: `NoRoute` and `NoSegment` (HTTP 200), `ProfileNotFound` (404), `InvalidInput` (422, with a `message` that says why), or another, with any status but 401 and 403. The code, the server's message and the HTTP status (`statusCode`) are kept. |
| `MapboxDirectionsHttpException` | Always for a 401 (a missing or bad token) or a 403 (URL restrictions or an account problem), even when the body has a `code`; and any other HTTP error without a code: 429 (rate limit), a proxy or server error. The message quotes the start of the body (its `code` and `message`), the token scrubbed. |
| `MapboxDirectionsTimeoutException` | No full answer within `timeout`. It is also a `TimeoutException`. |
| `MapboxDirectionsFormatException` | The answer is not UTF-8, not JSON, or not shaped as Mapbox's; the message names the field. For a route, its `cause` is the OSRM parser's `OsrmFormatException`. For an answer that is not JSON, the message is fixed and the `cause` (a `FormatException`) keeps only the offset: on the web the parser's own message quotes the body around the error, where part of a token could be. |

Transport failures (offline, DNS, TLS) arrive as the `http` client throws
them, usually as `http.ClientException`. A point that is not finite throws
`ArgumentError`, and a closed provider throws `StateError`, both before any
request.

The place search throws a `MapboxSearchException`, the
`PlaceSearchException` its interface promises (`Mapbox suggest failed`,
`Mapbox retrieve failed`, `Mapbox reverse failed`). Its `cause` says why:
one of the exceptions above, or the client's error (also a transport
failure); its `statusCode` is the cause's HTTP status.

## Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network and no token needed.
The package's own tests work that way, on fixtures hand-written to the
documented answers (none was recorded). Tests of what differs under
dart2js (the polyline decoding, the coordinates' text, the token scrub,
the web's `User-Agent`) also run on node:

```sh
dart test -p node -t js
```

A live smoke check against Mapbox runs only with a token in the
environment (six requests, billed to the token's account). It fetches a
raw Directions answer and fails on any manoeuvre type or modifier the
parser does not map, printing the values (and the `maxspeed` shapes) it
saw; it also checks real routes and a Search Box session:

```sh
MAPBOX_TOKEN=pk.... dart test -t live
```

Without the token those tests are skipped. The example
(`example/bin/main.dart`) also makes live requests with the same variable.
