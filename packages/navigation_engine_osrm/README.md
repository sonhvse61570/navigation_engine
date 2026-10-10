# navigation_engine_osrm

Routes for [navigation_engine](https://pub.dev/packages/navigation_engine)
from an [OSRM](https://project-osrm.org) server: a `RouteProvider` that
asks OSRM's route service for the best route and its alternatives, with
manoeuvres, lanes and per-segment durations. Pure Dart, on `http`.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_osrm: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';

final router = OsrmRouteProvider(
  baseUrl: Uri.parse('https://osrm.example.com'), // your server
  userAgent: 'my_app/1.0',
);

// Rerouting during navigation:
final session = NavigationSession(fixes: source, routeProvider: router);

// A route overview: the best route first, then up to 2 alternatives.
final routes = await router.routes(from, to, heading: fix.heading);

// When done:
router.close();
```

## Quick start with any map adapter

`GeolocatorFixSource` (navigation_engine_geolocator) and
`OsrmRouteProvider` (navigation_engine_osrm) plug into the session and the
flow controller, so the same code drives every map adapter: only the
drop-in screen changes. With MapLibre:

```dart
import 'package:navigation_engine_geolocator/navigation_engine_geolocator.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';

final source = GeolocatorFixSource();
final router = OsrmRouteProvider(userAgent: 'my_app/1.0');
final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

MapLibreStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
  styleString: 'https://tiles.openfreemap.org/styles/liberty',
);

session.start(); // asks for the permission; the vehicle shows at the first fix
await flow.preview(to: destination); // OSRM's routes; the user taps Start

// When done: the flow, then the session, then the source and the router.
flow.dispose();
session.dispose();
source.dispose();
router.close();
```

The adapter's library re-exports `NavigationSession`, `GeoPoint` and
`NavigationFlowController`. For another map, swap the import and the
screen:

| Map | Package | Screen |
| --- | --- | --- |
| Google Maps | `navigation_engine_google_maps` | `GoogleStyleNavigation(session: …, flow: …, initialCenter: …)` (set up the Maps API key) |
| MapLibre | `navigation_engine_maplibre` | `MapLibreStyleNavigation(…, styleString: …)` |
| flutter_map | `navigation_engine_flutter_map` | `NeutralNavigation(…, userAgentPackageName: …)` |
| Mapbox | `navigation_engine_mapbox` | `MapboxStyleNavigation(…)` (set the access token first) |

## The demo server

Without `baseUrl` the provider uses OSRM's public demo server,
`https://router.project-osrm.org` (`OsrmRouteProvider.demoServer`). It is
for testing only:

- it is rate limited (about one request per second) and has no
  availability guarantee;
- it serves only the `driving` profile;
- it sees the coordinates of every request.

An app should use its own OSRM server or a hosted one. Set `userAgent` to
your app's name: the demo server's policy asks apps to identify themselves.

## Options

| Option | Default | |
| --- | --- | --- |
| `baseUrl` | `demoServer` | The server. A path prefix (`https://example.com/osrm/`) and query parameters (an API key) are kept. |
| `profile` | `driving` | The server's profile name. |
| `timeout` | 12 s | Bounds each request, the body included; the request is then aborted. |
| `geometries` | `OsrmGeometries.geojson` | `polyline6` is about three times smaller on the wire, with the same precision. |
| `speedLimits` | `false` | Asks for `annotations=true` and reads `maxspeed`. Turn it on only for a server that sends `maxspeed`: mainline OSRM, the demo server included, does not, and the answer would only grow. Off asks for `duration,distance` only. |
| `userAgent` | `navigation_engine_osrm/0.1.0`; null on the web | The `User-Agent` header; null sends none. On the web it defaults to null: a browser that honours the header would send a CORS preflight the server may not answer. |
| `client` | a new `http.Client` | Injected clients stay yours to close; `close()` closes only the one the provider created. |

## What is requested

`GET {baseUrl}/route/v1/{profile}/{lng},{lat};{lng},{lat}` with
`alternatives=N` (`false` for `route()`), `steps=true`,
`geometries=geojson` or `polyline6`, `overview=full` and
`annotations=duration,distance` (the default) or `annotations=true`
(with `speedLimits`). OSRM's grammar has no
`maxspeed` value, so `true` is the only way to ask for speed limits; it
also brings annotations the provider does not read, a larger answer. A
heading is sent as the start's
`bearings` (`{heading},45;`), so a reroute leaves the way the vehicle faces
instead of starting with a U-turn. OSRM servers allow 3 alternatives by
default and answer `TooBig` for more.

## What a route holds

- **Geometry:** the full route polyline.
- **Steps:** one `RouteStep` per OSRM step, placed on the route at its
  manoeuvre location (so its `distance` is measured along the route).
  - `maneuver.type` maps onto `ManeuverType`: `depart`, `arrive`, `turn`,
    `new name`, `continue`, `merge`, `on ramp`, `off ramp`, `fork`,
    `end of road`; `roundabout` and `rotary` become `roundabout`, and
    `exit roundabout` and `exit rotary` become `exitRoundabout`;
    `notification` and `use lane` become `continueOn`; `roundabout turn`,
    and any type OSRM adds later, become `turn`, as OSRM asks.
  - `maneuver.modifier` maps onto `ManeuverModifier`.
  - The road name is `name`, or `ref` when the road has no name.
  - Lanes come from the manoeuvre's intersection (`intersections[0].lanes`):
    the arrows painted (`indications`; `none` reads as straight), whether
    the lane is valid for the manoeuvre, and the arrow to follow in it.
- **Durations:** the `duration` annotation of each segment, scaled so each
  leg adds up to OSRM's leg duration (the annotations leave out the time
  of the turns). Without annotations the engine estimates the durations.
- **Speed limits** (only with `speedLimits: true`, off by default): the
  `maxspeed` annotation of each segment in m/s, from `{speed, unit}` in
  km/h or mph; `{unknown: true}`, `{none: true}` and speeds that are not
  positive are no limit. Mainline OSRM, the public demo server included,
  sends no `maxspeed`, even with `annotations=true`: turn the option on
  only for a server that does. Without limits the routes have none, and
  the engine shows no speed-limit sign.
- **Summary:** the legs' `summary`, such as "Lý Tự Trọng, Nguyễn Hữu Cảnh".

The engine has no field for a roundabout's exit number, which OSRM sends
as `maneuver.exit`; it is not kept.

## Errors

Every failure the provider detects throws an `OsrmException`:

| Exception | When |
| --- | --- |
| `OsrmCodeException` | OSRM answered with an error `code`: `NoRoute`, `NoSegment` (a point far from any road), `TooBig`, `InvalidQuery`, … The `code`, the server's message and the HTTP status are kept. |
| `OsrmHttpException` | An HTTP error without an OSRM code: a gateway error, or 429 when the demo server's rate limit is hit. |
| `OsrmTimeoutException` | No full answer within `timeout`. It is also a `TimeoutException`. |
| `OsrmFormatException` | The answer is not UTF-8, not JSON, or not shaped as OSRM's; the message names the field. |

Transport failures (offline, DNS, TLS) arrive as the `http` client throws
them, usually as `http.ClientException`. A point that is not finite throws
`ArgumentError`, and a closed provider throws `StateError`, both before any
request. A `NavigationSession` reports a failed reroute as a
`RerouteFailed` event.

## Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network needed.
