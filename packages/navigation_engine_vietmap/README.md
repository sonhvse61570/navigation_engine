# navigation_engine_vietmap

[Vietmap](https://maps.vietmap.vn) for
[navigation_engine](https://pub.dev/packages/navigation_engine): map style
URLs for MapLibre, a `RouteProvider` on Vietmap's route v4 API, and a
`PlaceSearchProvider` on its autocomplete, place and reverse v4 APIs. Pure
Dart, on `http`; no Vietmap SDK and no native code.

> **Check Vietmap's terms before production use.** Vietmap publishes no
> developer terms: they are accepted when you create a key in Vietmap's
> console. Nothing public says whether a third-party renderer, caching or a
> particular credit is allowed or required. Ask Vietmap
> (maps-api.support@vietmap.vn) before you ship, and do not add tile
> prefetching or offline maps without their written permission.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_maplibre: ^0.1.0
  navigation_engine_vietmap: ^0.1.0
```

```dart
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';
import 'package:navigation_engine_vietmap/navigation_engine_vietmap.dart';

// The services key stays on your server: the proxy adds it.
final api = Uri.parse('https://maps-proxy.example.com/vietmap/');
final router = VietmapRouteProvider(apiKey: null, baseUrl: api);
final search = VietmapPlaceSearch(apiKey: null, baseUrl: api);

final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

MapLibreStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
  // The tile key ships with the app: restrict it to your app in Vietmap's
  // console.
  styleString: VietmapStyles.url(VietmapStyle.tm, apiKey: tileKey),
  nightStyleString: VietmapStyles.url(VietmapStyle.dm, apiKey: tileKey),
  attributionText: VietmapStyles.attribution, // '© VIETMAP'
);

// A destination search field:
final suggestions = await search.autocomplete('Chợ Bến Thành', near: here);
final place = await search.resolve(suggestions.first); // its position
await flow.preview(to: place.position);

// When done:
router.close();
search.close();
```

## Keys

Vietmap has two kinds of key:

- a **tile key** ("public tile"), for the map styles and tiles. It ships
  with the app, so restrict it to your app in Vietmap's console.
  `VietmapStyles.url` puts it in the style URL's query (`apikey=`); Vietmap
  copies it into the tile URLs, so the map needs no header or request
  transform.
- a **services key**, for the REST APIs (route, autocomplete, place,
  reverse). Vietmap's documentation says to keep it on a server; REST calls
  with a tile key answer HTTP 423.

Keep the services key behind your back end or a proxy: point `baseUrl` at
it and pass `apiKey: null`, so the app sends no key. That is why `baseUrl`
and `headers` can be set. A key passed as `apiKey` is sent from the app as
the `apikey` query parameter, which anyone can read from the app or its
traffic: use it for development only.

The package keeps the key out of its exception messages. Server text it
quotes (an HTTP error body and reason phrase, Vietmap's `code` and
`messages`) has the key replaced by `REDACTED`, as it is and
percent-encoded, in case a server or proxy echoes it. A malformed field is
described in error messages (`a string`), never quoted. Transport errors (`http.ClientException`) carry the request URL; the
package replaces the key in it, and in their message, with `REDACTED`.

## Styles

`VietmapStyles.url(style, apiKey: tileKey)` gives
`https://maps.vietmap.vn/maps/styles/{style}/style.json?apikey=…`:

| `VietmapStyle` | |
| --- | --- |
| `tm` | The vector street map: the default, for day. |
| `lm` | The light vector map. |
| `dm` | The dark vector map: suggested for night. |
| `hm` | The hybrid map (satellite with labels). Vietmap may have to enable it for your key. |

Vietmap's styles carry no attribution string, so MapLibre's attribution
button says nothing about Vietmap. Show `VietmapStyles.attribution`
(`© VIETMAP`) on the map, for example with `attributionText` in
`MapLibreNavigationView` or `MapLibreStyleNavigation`. The tiles follow the
OpenMapTiles schema, which usually asks for an "© OpenMapTiles" credit as
well: ask Vietmap.

## Routes: `VietmapRouteProvider`

`GET {baseUrl}/route/v4?apikey=…&point={lat},{lng}&point={lat},{lng}` with
`vehicle`, `capacity` (when given), `alternative` (`false` for `route()`
and for `routes(maxAlternatives: 0)`, else `true`), `heading` (in whole
degrees, when known, so a reroute leaves the way the vehicle faces) and
`points_encoded=true`.

| Option | Default | |
| --- | --- | --- |
| `apiKey` | required | The services key, or null to send none (a proxy adds it). |
| `baseUrl` | `https://maps.vietmap.vn/api/` | A path prefix and query parameters are kept. |
| `vehicle` | `VietmapVehicle.car` | `car`, `motorcycle`, `truck`, `container`. |
| `capacity` | null | Gross weight in kg; required for `truck`. |
| `headers` | none | Added to every request (a proxy's token, say). They may replace `Accept` and `User-Agent`. |
| `timeout` | 12 s | Bounds each request, the body included; the request is then aborted. |
| `userAgent` | `navigation_engine_vietmap/0.1.0`; null on the web | Null sends none. On the web it defaults to null: a browser would send a CORS preflight the server may not answer. |
| `client` | a new `http.Client` | Injected clients stay yours to close; `close()` closes only the one the provider created. |

What a route holds:

- **Alternatives:** every `paths[]` entry, best first, up to
  `maxAlternatives + 1`. Vietmap decides how many alternatives it sends.
- **Geometry:** the path's `points`, a precision-5 encoded polyline.
- **Steps:** one `RouteStep` per instruction, placed at the first vertex
  of its `interval`. The road name is `street_name` (else `street_ref`).
  The `sign` gives the manoeuvre (GraphHopper's codes):

  | `sign` | Manoeuvre |
  | --- | --- |
  | 0 on the first instruction | `depart` |
  | -98, -8, 8 | `turn`, `uturn` |
  | -7 / 7 | `fork`, `slightLeft` / `slightRight` (keep left / right) |
  | -3 / 3 | `turn`, `sharpLeft` / `sharpRight` |
  | -2 / 2 | `turn`, `left` / `right` |
  | -1 / 1 | `turn`, `slightLeft` / `slightRight` |
  | 0 | `continueOn`, `straight` |
  | 4 | `arrive` |
  | 5 (via point; the provider sends none) | `continueOn` |
  | 6 | `roundabout` |
  | -6 | `exitRoundabout` |
  | any other | `turn`, no direction |

  Vietmap does not publish its sign table (its docs link to a Figma file);
  the table above is GraphHopper's, which route v4's answers follow. The
  fixtures are hand-written from the documentation, not recorded: record
  here any code a real answer uses differently.
- **Durations:** each instruction's `time` (milliseconds) spread over the
  segments of its interval by length. The time of an instruction without
  segments goes to the segment before it. When the intervals do not cover
  every segment once, in order (or there are no instructions), the path's
  `time` is spread over the whole path by length instead; without a
  positive `time`, the engine estimates the durations.
- **Summary:** the named road covering the longest distance.
- **Lanes:** none; route v4 sends no lane data. The roundabout exit number
  (`exit_number`) has no field in the engine and is not kept.

## Place search: `VietmapPlaceSearch`

It takes the same `apiKey`, `baseUrl`, `headers`, `timeout`, `userAgent`
and `client` options.

- `autocomplete(query, near:)` calls autocomplete v4
  (`text`, and `focus={lat},{lng}` for `near`; a `near` that is not
  finite throws `ArgumentError`). A query shorter than 2 characters (the
  minimum Vietmap's documentation asks for) returns nothing without a
  request. Suggestions have the
  `ref_id` as their `id`, the place's name (else its address, else its
  display) as their `title`, the rest of the display as their `subtitle`,
  and **no position**.
- `resolve(suggestion)` calls place v4 (`refid=` the `ref_id`) for the
  position. Each place call is a billed transaction: resolve only the
  suggestion the user picks.
- `reverse(point)` calls reverse v4 (`lat`, `lng`) and returns the first
  place, or null when there is none.

Vietmap does not bill per session: `PlaceSearchSession`s are accepted and
ignored. Addresses come in the server's default format, the two-level
(ward, city) one of Vietnam's 2025 administrative reform.

## Errors

The route provider throws a `VietmapException`:

| Exception | When |
| --- | --- |
| `VietmapCodeException` | Vietmap answered with an error `code`: `ZERO_RESULTS` (no route), `INVALID_REQUEST`, `OVER_DAILY_LIMIT`, `MAX_POINTS_EXCEED`, `ERROR_UNKNOWN`, … The `code`, the server's `messages` and the HTTP status are kept. |
| `VietmapHttpException` | An HTTP error without a code: 401/403 (a missing or bad key), 423 (a tile key on a REST API), 429 (rate limit), a proxy error. |
| `VietmapTimeoutException` | No full answer within `timeout`. It is also a `TimeoutException`. |
| `VietmapFormatException` | The answer is not UTF-8, not JSON, or not shaped as Vietmap's; the message names the field. For an answer that is not JSON it is the fixed `invalid JSON`, and `cause` keeps only the parser's offset: on the web the parser's own message quotes the body around the error, where part of the key could be. |

Transport failures (offline, DNS, TLS) arrive as the `http` client throws
them, usually as `http.ClientException`. A point that is not finite throws
`ArgumentError`, and a closed provider throws `StateError`, both before any
request.

The place search throws a `VietmapSearchException`, the
`PlaceSearchException` its interface promises. Its `cause` says why: one of
the exceptions above, or the client's error (also a transport failure).

## Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network and no key needed.
The package's own tests work that way, on hand-written fixtures.

A live smoke check against Vietmap runs only with a services key in the
environment (five requests, billed to the key). It fetches a raw route v4
answer and fails on any `sign` code the table above misses, printing the
codes it saw; it also checks that real routes have no unknown manoeuvre
and that they carry road names:

```sh
VIETMAP_SERVICES_KEY=... dart test -t live
```

Without the key those tests are skipped. The example
(`example/bin/main.dart`) also makes live requests with the same variable.
