# navigation_engine_goong

[Goong](https://goong.io) for
[navigation_engine](https://pub.dev/packages/navigation_engine): map style
URLs for MapLibre, a `RouteProvider` on Goong's direction v2 API, and a
`PlaceSearchProvider` on its autocomplete, place detail and geocode v2
APIs. Pure Dart, on `http`; no Goong SDK and no native code. Goong has no
Flutter SDK of its own: its guides use plain MapLibre, as this package
does.

> **Check Goong's terms before production use.** Goong publishes no
> developer or API terms: `goong.io/terms` is the end-user licence of its
> desktop navigation product, and its old developer docs site is offline.
> Nothing public says whether a third-party renderer, caching or a
> particular credit is allowed or required. Ask Goong
> (https://goong.io/en/contact/) before you ship, and do not add tile
> prefetching or offline maps without their written permission.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_maplibre: ^0.1.0
  navigation_engine_goong: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_goong/navigation_engine_goong.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';

// The API key stays on your server: the proxy adds it.
final api = Uri.parse('https://maps-proxy.example.com/goong/');
final router = GoongRouteProvider(apiKey: null, baseUrl: api);
final search = GoongPlaceSearch(apiKey: null, baseUrl: api);

final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

MapLibreStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(21.0288, 105.8524),
  // The Maptiles key ships with the app: restrict it to your app in
  // Goong's console.
  styleString: GoongStyles.url(GoongStyle.map, mapTilesKey: tilesKey),
  // The same style at night: try GoongStyle.dark once it loads with your
  // key (it may not exist any more).
  nightStyleString: GoongStyles.url(GoongStyle.map, mapTilesKey: tilesKey),
  attributionText: GoongStyles.attribution, // '© Goong'
);

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

## Keys

Goong has two kinds of key:

- a **Maptiles key**, for the map styles and tiles. It ships with the app,
  so restrict it to your app (by domain or IP) in Goong's console.
  `GoongStyles.url` puts it in the style URL's query (`api_key=`).
- an **API key**, for the REST APIs (direction, autocomplete, place
  detail, geocode). A Maptiles key used on a REST API answers HTTP 403.

Keep the API key behind your back end or a proxy: point `baseUrl` at it
and pass `apiKey: null`, so the app sends no key. That is why `baseUrl`
and `headers` can be set. A key passed as `apiKey` is sent from the app as
the `api_key` query parameter, which anyone can read from the app or its
traffic: use it for development only.

The package keeps the key out of its exception messages. Server text it
quotes (an HTTP error body and reason phrase, Goong's `status` or error
`code`, its `error_message` or error `message`) has the key replaced by
`REDACTED`, as it is and percent-encoded, in case a server or proxy echoes
it. Transport errors (`http.ClientException`)
carry the request URL; the package replaces the key in it, and in their
message, with `REDACTED`.

## Styles

`GoongStyles.url(style, mapTilesKey: key)` gives
`https://tiles.goong.io/assets/{asset}.json?api_key=…`:

| `GoongStyle` | Asset | |
| --- | --- | --- |
| `map` | `goong_map_web` | The full map, every icon: the default, for day. |
| `highlight` | `goong_map_highlight` | Fewer icons. |
| `satellite` | `goong_satellite` | Satellite imagery. |
| `dark` | `goong_map_dark` | Dark, for night. **May not exist.** |
| `navigationDay` | `navigation_day` | For navigation by day. **May not exist.** |
| `navigationNight` | `navigation_night` | For navigation by night. **May not exist.** |

Goong's help centre documents the first three. The last three come from
its older mobile documentation and may no longer be served
(`GoongStyle.mayNotExist`): check that they load with your key before you
ship them, and fall back to `map` if they do not.

Goong publishes no attribution requirement, and whether its styles carry
an attribution string is unknown. Show `GoongStyles.attribution`
(`© Goong`) on the map as a courtesy, for example with `attributionText`
in `MapLibreNavigationView` or `MapLibreStyleNavigation`.

## Routes: `GoongRouteProvider`

`GET {baseUrl}/v2/direction?origin={lat},{lng}&destination={lat},{lng}&vehicle=…&alternatives=…&api_key=…`,
with `alternatives` `false` for `route()` and for
`routes(maxAlternatives: 0)`, else `true`.

**Goong has no heading parameter, so a reroute may suggest a U-turn.** The
`heading` that `route()` and `routes()` receive is ignored: direction v2
documents no heading, bearing or "avoid U-turn" option.

| Option | Default | |
| --- | --- | --- |
| `apiKey` | required | The API key, or null to send none (a proxy adds it). |
| `baseUrl` | `https://rsapi.goong.io/` | A path prefix and query parameters are kept. |
| `vehicle` | `GoongVehicle.car` | `car`, `bike`, `taxi`, `truck`, `hd` (ride-hailing). The v2 page lists `car` and `bike` (a bicycle, "xe đạp"; the live check should confirm); the others come from the v1 docs. |
| `headers` | none | Added to every request (a proxy's token, say). They may replace `Accept` and `User-Agent`. |
| `timeout` | 12 s | Bounds each request, the body included; the request is then aborted. |
| `userAgent` | `navigation_engine_goong/0.1.0`; null on the web | Null sends none. On the web it defaults to null: a browser would send a CORS preflight the server may not answer. |
| `client` | a new `http.Client` | Injected clients stay yours to close; `close()` closes only the one the provider created. |

The answer has Google Directions' shape. What a route holds:

- **Alternatives:** every `routes[]` entry, best first, up to
  `maxAlternatives + 1`. Goong decides how many alternatives it sends.
- **Geometry:** the steps' `polyline.points` (precision 5), joined in
  order. The point where one step ends and the next starts is kept once.
  When a route has no steps, its `overview_polyline` is used.
- **Steps:** one `RouteStep` where each step starts, then an arrival at
  the end. Goong ends a route with a step of no length ("Bạn đã đến điểm
  đích", maneuver `""`): that step becomes the arrival, whether its
  polyline is one point or several equal ones. The first step is
  always the departure, whatever its `maneuver` (Goong's documented first
  step says `right`). The other steps' `maneuver`:

  | `maneuver` | Manoeuvre |
  | --- | --- |
  | `turn-left` / `turn-right` (Goong: `left` / `right`) | `turn`, `left` / `right` |
  | `turn-slight-left` / `-right` (Goong: `slight left` / `right`) | `turn`, `slightLeft` / `slightRight` |
  | `turn-sharp-left` / `-right` (`sharp left` / `right`) | `turn`, `sharpLeft` / `sharpRight` |
  | `uturn-left`, `uturn-right`, `uturn` | `turn`, `uturn` |
  | `roundabout-left` / `roundabout-right` | `roundabout`, `left` / `right` |
  | `keep-left` / `keep-right`, `fork-left` / `fork-right` | `fork`, `slightLeft` / `slightRight` |
  | `merge` | `merge` |
  | `ramp-left` / `ramp-right` | `onRamp`, `left` / `right` |
  | `straight` | `continueOn`, `straight` |
  | `ferry`, `ferry-train` | `continueOn` |
  | none (absent, null or `""`) | `continueOn` |
  | any other | `turn`, no direction |

  Case, spaces and underscores do not matter (`slight right` is
  `turn-slight-right`). Goong does not publish its full list: its v2 page
  shows `right`, `left`, `slight right` and `""`. The fixtures are
  hand-written from the documentation, not recorded: record here any value
  a real answer uses that the table misses.
- **Road names:** a step's `name`, when Goong sends one; else read from
  `html_instructions`, with the tags stripped and the entities decoded.
  With Google's tags, it is the `<b>` segment after "onto" or "on"
  ("Turn `<b>`right`</b>` onto `<b>`Phạm Văn Đồng`</b>`"). In Goong's plain
  Vietnamese, it is what follows "vào", "trên", "theo" or "từ" ("Rẽ trái
  vào Hoàng Quốc Việt", "Bắt đầu đi từ Trần Cung"), up to a comma or a
  phrase that says where the road leads ("theo hướng", "về hướng",
  "hướng về", "hướng đến", "rồi", "toward"): "Rẽ phải vào Trần Duy Hưng
  theo hướng Big C" gives "Trần Duy Hưng". Words that lead onto a road
  ("onto", "vào") win over the others; "theo hướng" alone is a direction,
  not a road. An instruction that names no road ("Rẽ phải") gives an
  empty name.
- **Durations:** each step's `duration.value` (seconds) spread over its
  segments by length. The time of a step of no length goes to the segment
  before it. When a step with length has no duration, the legs'
  `duration.value` is spread over the whole route by length instead;
  without that either, the engine estimates the durations.
- **Summary:** the route's `summary` when Goong sends one, else the named
  road covering the longest distance.
- **Name:** `Goong {distance} m`, from the legs' `distance.value`, or from
  the route's length when a leg has none.
- **Lanes:** none; direction v2 documents no lane data.

## Place search: `GoongPlaceSearch`

It takes the same `apiKey`, `baseUrl`, `headers`, `timeout`, `userAgent`
and `client` options.

- `autocomplete(query, near:, session:)` calls autocomplete v2 (`input`;
  `location={lat},{lng}` for `near`; `sessiontoken` for the session). An
  empty query returns nothing without a request; `ZERO_RESULTS` is an
  empty list. Suggestions have the `place_id` as their `id`, the
  `structured_formatting.main_text` (else the `description`) as their
  `title`, the `secondary_text` (else the rest of the description) as
  their `subtitle`, and **no position**.
- `resolve(suggestion, session:)` calls place detail v2 (`place_id`, and
  the session's `sessiontoken`) for the position. The place's `name` is
  the result's name (else the suggestion's title) and its `address` the
  `formatted_address`.
- `reverse(point)` calls geocode v2 (`latlng={lat},{lng}`) and returns the
  first result (named by its `name`, else its `address`, else its
  formatted address), or null when there is none.

**Sessions save money.** Goong bills one autocomplete session (any number
of autocomplete calls, then at most one place detail call, all with the
same `sessiontoken`) as one request, and bills a reused token per request.
Create a `PlaceSearchSession` when the user starts typing, pass it to
every `autocomplete` call and to the `resolve` of the chosen suggestion,
then create a new one. A successful `resolve` ends its session: the
search sends that token no more, so later calls with it are billed one by
one, as Goong would anyway. (Goong's place detail v2 page does not list
`sessiontoken`; its session billing is documented for v1. The token is
sent to both; the live check should confirm v2 honours it.)

## Errors

The route provider throws a `GoongException`:

| Exception | When |
| --- | --- |
| `GoongCodeException` | Goong answered with an error code, in Google's shape (`status`: `ZERO_RESULTS` for no route, `NOT_FOUND`, `INVALID_REQUEST`, `OVER_QUERY_LIMIT`, `REQUEST_DENIED`, `UNKNOWN_ERROR`, …, with `error_message`) or as an error object (`{"error": {"code": "API_KEY_MISSING", "message": …}}`). The code, the server's message and the HTTP status are kept. |
| `GoongHttpException` | An HTTP error without a code: 401/403 (a missing, bad or blocked key, an unpaid account, or a Maptiles key on a REST API), 429 (rate limit), a proxy error. |
| `GoongTimeoutException` | No full answer within `timeout`. It is also a `TimeoutException`. |
| `GoongFormatException` | The answer is not UTF-8, not JSON, or not shaped as Goong's; the message names the field. For an answer that is not JSON it is the fixed `invalid JSON`, and `cause` keeps only the parser's offset: on the web the parser's own message quotes the body around the error, where part of the key could be. |

Transport failures (offline, DNS, TLS) arrive as the `http` client throws
them, usually as `http.ClientException`. A point that is not finite throws
`ArgumentError`, and a closed provider throws `StateError`, both before any
request.

The place search throws a `GoongSearchException`, the
`PlaceSearchException` its interface promises. Its `cause` says why: one of
the exceptions above, or the client's error (also a transport failure).

Goong documents no error bodies for v2; the shapes above are Google's,
which Goong says it follows, and the error object its servers answer a
request without a key with.

## Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network and no key needed.
The package's own tests work that way, on hand-written fixtures.

A live smoke check against Goong runs only with an API key in the
environment (five requests, billed to the key). It fetches a raw
direction v2 answer and fails on any `maneuver` value the table above
misses, printing the values it saw; it also checks that real routes have
no unknown manoeuvre and that road names are read from real instructions:

```sh
GOONG_API_KEY=... dart test -t live
```

Without the key those tests are skipped. The example
(`example/bin/main.dart`) also makes live requests with the same variable.
