# navigation_google_maps

A smooth turn-by-turn navigation view for Google Maps
([google_maps_flutter](https://pub.dev/packages/google_maps_flutter)), built
on [navigation_engine](https://pub.dev/packages/navigation_engine). It also
routes with the Google Routes API and searches places with Places API (New):
see [Routing and search](#routing-and-search).

Configure your Maps API key as for any google_maps_flutter app (Android
manifest `com.google.android.geo.API_KEY`, iOS `GMSServices.provideAPIKey`).
The example reads it from `example/android/local.properties`
(`MAPS_API_KEY=…`, gitignored).
On iOS, add `GMSServices.provideAPIKey("…")` in `AppDelegate.swift` before running.

```dart
final session = NavigationSession(fixes: myFixSource)..start(route: route);

Stack(children: [
  GoogleMapsNavigationView(
    session: session,
    initialCenter: route.points.first,
  ),
  NavigationBanner(session: session), // from navigation_engine_flutter
]);
```

Using your own `GoogleMap`? Use `GoogleMapsNavigationMap` directly: pass it
to the session (`map:`), call `onMapCreated`, and build `polylines` /
`vehicleMarker` from its listenables.

## Map taps and the destination pin

`onMapTap` and `onMapLongPress` (on `GoogleMapsNavigationView` and
`GoogleStyleNavigation`) get the place the user taps or long-presses, as a
`GeoPoint`. A tap on a feature the adapter draws (a route option or its
bubble, an alternate or its bubble, a search pin or the destination pin)
does not reach `onMapTap`. The Google Maps SDKs are documented to report
no map tap for a tap a marker took, and on Android for one a tappable
polyline took; should a platform report both for one gesture, the view
drops the map tap that comes after the feature tap in the same frame, or
that the feature tap follows in the same turn of the event loop. A map
tap is therefore delivered one turn of the event loop after the SDK
reports it. A tap on the route line itself (not tappable) is a map tap,
also where an alternate shares the road: alternates are drawn only where
they differ (`alternateLinePoints`). A tap on the vehicle is a map tap at
the vehicle, as on the other adapters (the SDK would take it as a marker
click). A long press always reaches `onMapLongPress`. A touch on the map still
stops following the vehicle.

`GoogleMapsNavigationMap` implements `DestinationPinMap`:
`showDestinationPin(point)` draws the shared red pin of
`paintDestinationPin` (from navigation_engine_flutter, this package's own
drawing, no Google asset), anchored at its tip; null removes it. The drop-in
pins the end of the selected route in the overview, while navigating and
arrived, and clears it when the flow goes back to idle. While idle, an app
can pin a long-pressed place itself:

```dart
GoogleStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: center,
  onMapLongPress: (point) {
    if (session.map case final DestinationPinMap pin) {
      pin.showDestinationPin(point);
    }
    flow.preview(to: point);
  },
);
```

## Colours of the labels, alternates and pins

`GoogleMapsNavigationView.labelColors` takes `RouteLabelColors`, the
colours of the route option bubbles, so the view can wear any look:
`GoogleStyleColors.day.routeLabelColors`,
`MapboxStyleColors.night.routeLabelColors` or your own. The alternate
routes and the search pins have their own parameters: `alternateColor`,
`fasterLabelColors`, `slowerLabelColors` and `searchPinColor`. Each one left
null keeps the map's own: by default the shared day colours of every
adapter (`MapDefaultColors`), not the Google-style ones.
`GoogleStyleNavigation` passes its theme's, by day and at night; a screen
of your own passes `GoogleStyleColors`' to keep the Google look.

## Google-style navigation UI

A complete navigation screen in the style of a phone navigation app: route
options on the map with duration labels, turn-by-turn guidance with lane
arrows, a speed cluster, a trip sheet, day and night themes, and an arrival
sheet.

The library re-exports what the screen takes from navigation_engine and
navigation_engine_flutter (`NavigationSession`, `GeoPoint`,
`NavigationFlowController`, `NavigationStrings`, `PlaceLabel`, …), so
the adapter is the only navigation_engine package to depend on (an app that
writes its own `FixSource` or `RouteProvider` adds navigation_engine):

```yaml
dependencies:
  navigation_google_maps: ^0.1.0
```

```dart
import 'package:navigation_google_maps/navigation_google_maps.dart';

final session = NavigationSession(fixes: myFixSource, routeProvider: provider);
final flow = NavigationFlowController(session: session, routeProvider: provider);

GoogleStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
);

session.start(); // the vehicle shows, and preview() starts from its position
await flow.preview(to: destination); // shows the route options; the user taps Start
```

The app owns, starts and disposes the `session`, and owns and disposes the `flow` (flow first, then the
session, then the fix source). Pass `idleBuilder` to show your own overlay,
such as a search bar, while the flow is idle.

There is always a way out. The loading spinner has a Cancel button, and a
route preview has a close button (`flow.closeOverview()`, back to idle; the
session is left as it was, and a Re-center button brings the camera back to
the vehicle). A back (the system back button or gesture) leaves
the screen only while idle, navigating or arrived; otherwise it closes what
is open: loading and errors cancel, a route preview closes, and the trip
overview resumes the trip. While navigating it first closes the sound pill,
the trip sheet's menu or the search along the route, one per back. Retry
runs only from the error state. The step
list follows the guidance and closes itself on arrival, stop or reroute.

`puck`, `vehicleImage`, `focus` and `initialZoom` are passed to the map
view (see Vehicle marker below).

### Controls

While navigating, the screen follows the Google Maps app:

- **Header:** a flat teal card with the next manoeuvre, its distance
  and the road. On a straight-on step (a continue, new name or turn whose
  modifier is straight or none) the road reads "toward" it and the
  distance hides over 1 km; a depart reads "toward" too. Under the card
  hang the lanes, in a band as wide as the card, or a "Then" tab with the
  manoeuvre after. Tap it for the step list. Swipe it to preview the next
  steps; the card turns grey, and Re-center (or 10 s) ends the preview.
- **End column**, anchored above the trip sheet at the end side (in
  landscape, at the bottom end of the map area): white, outlined buttons,
  top to bottom the report button (it opens "Add a report" with eight
  incident types), the compass (a red triangle over an "N", while
  following), search along the route, the 3-state sound button (sound,
  alerts only, muted) and route options. The route options open the trip
  overview with the alternate routes; Resume on another one switches to
  it. When the screen is short, the column drops search, then sound, then
  the compass, then the report: route options stay. When a row would meet
  the speed cluster or the Re-center pill (a wide pill in the bottom row),
  the column lifts to end 16 above them.
- **Speed cluster** at the bottom start (the limit sign and the
  speedometer, red when speeding; a white circle when the speedometer is
  alone). The Re-center pill takes its place once the map is moved.
- **Trip sheet:** close and the time left with "distance • arrival". Drag
  the sheet up for Share trip progress, Search along route, Directions,
  Show traffic on map and Show satellite map (switches that flip in place)
  and Settings. The sheet follows the finger and settles with a spring (a
  tap on its handle or time animates it); the floating controls fade out
  as it opens and come back as it closes.
- **Alternate routes** show on the map with "2 min faster" / "+3 min"
  bubbles. A tap switches to one.
- **Landscape** (600 dp wide and up): the header and the sheet move to a
  side panel, and the follow focus moves beside it.

A control shows when its toggle is on and its callback exists:

| Parameter | Mirrors the SDK's | Controls |
| --- | --- | --- |
| `headerEnabled` | `setNavigationHeaderEnabled` | the turn card |
| `footerEnabled` | `setNavigationFooterEnabled` | the trip sheet |
| `tripProgressBarEnabled` (default false) | `setNavigationTripProgressBarEnabled` | the progress bar on the start edge (screens 552 dp high and up) |
| `speedometerEnabled` | `setSpeedometerEnabled` | the speedometer |
| `speedLimitIconEnabled` | `setSpeedLimitIconEnabled` | the speed limit sign |
| `recenterButtonEnabled` | `setRecenterButtonEnabled` | the Re-center pill |
| `compassEnabled` | the map's compass setting | the compass, while following |
| `routeOverviewButtonEnabled` | `showRouteOverview` | the end column's route-options button |
| `reportButtonEnabled` + `onReportIncident` | `setReportIncidentButtonEnabled` | the report button |
| `searchButtonEnabled` + `searchAlongRoute` | — | the search button |
| `onAudioGuidanceChanged` (+ `audioGuidance`) | `setAudioGuidance` | the sound button |
| `onShareTrip`, `onSettings` | — | their menu rows |

The app owns the audio, the reports, the search back end
(`searchAlongRoute`) and the stops (`onAddStop`); the package adds no stop
itself, and goes back to guidance once `onAddStop` returns. Pass `PlaceLabel`s to `flow.preview(destination: …)` for the
arrival card. Speeding is minor 10 km/h over and major 20 km/h over (5 / 10
with an mph formatter); `speedingMinor` / `speedingMajor` change it.

The compass glyph turns with the camera bearing, and a tap switches between
heading up and north up (`session.camera.headingUp`). Its accessibility
label is its tooltip, the mode a tap switches to.

### Built on navigation_engine_flutter

`GoogleStyleNavigation` is a `NavigationFlowScaffold` (from
`navigation_engine_flutter`) dressed with the Google-style pieces. The
shared vocabulary lives in that package and is re-exported here, with what
the drop-in takes: `NavigationSession` and `GeoPoint` (navigation_engine),
`NavigationFlowController`, `NavigationStrings`, `PlaceLabel`,
`AlternateRoute`, `AlternateRoutesMap`, `SearchPinsMap`,
`DestinationPinMap`, `RouteColors`, `CarPuck`, `VehicleImageBuilder`,
`RouteLabelColors`, `fitCameraToBounds`, `paintRouteLabel`,
`paintSearchPin`, `paintDestinationPin`, `laneDirectionIcon`,
`AlongRouteCategory`,
`AlongRoutePlace`, `AlongRouteQuery`, `AlongRouteSearch`, `SpeedingLevel`,
`GoogleStyleSheetAction`, `showGoogleStyleReportSheet` and the Google-style
pieces listed below. To build a screen in another look, use the scaffold directly.

The Google-style pieces and the whole screen, `GoogleStyleFlowScaffold`,
live in `navigation_engine_flutter`, so they work on any map;
`GoogleStyleNavigation` is that scaffold with a `GoogleMapsNavigationView`
as its map. `GoogleMapsNavigationMap` implements `SearchPinsMap` and
`DestinationPinMap`, and draws the search pins and the destination pin. This library re-exports the pieces under the same names;
import `navigation_engine_flutter` for `GoogleStyleFlowScaffold` and
`GoogleStyleMapLayers`.

The UI is built from public pieces you can use on their own:

- `GoogleStyleNavigation`: the drop-in screen that binds the pieces to a flow.
- `GoogleStyleManeuverHeader`: the next manoeuvre, its distance and street.
- `GoogleStyleLaneGuidance`: the lane arrows before a manoeuvre.
- `GoogleStyleTripSheet`: the trip sheet: close, the time left with distance and arrival, optional route options, and a menu when dragged up.
- `GoogleStyleSpeedCluster`: the speed limit sign (`SpeedLimitSignStyle`) and the current speed, red when speeding.
- `GoogleStyleRecenterButton`: brings the camera back to the vehicle.
- `GoogleStyleTripProgressBar`: the share of the trip driven, a bar on the start edge.
- `GoogleStyleCompassButton`: a red triangle over an "N" that points to north, and a tap to switch heading up and north up.
- `GoogleStyleRoundButton`: the outlined round map button of the compass, search, sound and route options.
- `GoogleStyleControlStack`: a column of map buttons, dropping from the bottom (or by `priorities`) when it does not fit.
- `GoogleStyleSoundButton`: the 3-state sound button (`AudioGuidance`).
- `GoogleStyleReportButton` / `GoogleStyleReportSheet`: the report pill, then circle, and the "Add a report" sheet (`IncidentType`).
- `GoogleStyleSearchAlongRoute`: the search along the route, with its category chips and results.
- `GoogleStyleOverviewPanel`: the route options, loading and error states.
- `GoogleStyleStepList`: the list of steps of a route.
- `GoogleStyleArrivalSheet`: the destination and a Done button, on arrival.
- `googleStyleNightMapStyle`: a dark map style, used at night.
- `fitCameraToBounds` and `paintRouteLabel` (from `navigation_engine_flutter`, re-exported here): the camera fit and the route label bubble the overview uses.

### Theme and language

Colours come from `GoogleStyleColors`; pass your own to `dayColors` and
`nightColors` (`GoogleStyleColors.day` and `GoogleStyleColors.night` are the
defaults, switched by `flow.isNight`). They reach:

- the panels: the overview, the trip sheet, the speed cluster, the step
  list and the arrival (`surface`, `onSurface`, `accent`, …);
- the turn card (`guidance`, `guidanceSecondary`, `onGuidance`);
- the route lines: the selected route option and the route ahead in
  `accent`, the other options and the part already driven in `alternative`.
  Pass `dayRouteColors` / `nightRouteColors` (`RouteColors`) to choose the
  selected option and the session's route line yourself; the other options
  always use `alternative`;
- the route option labels: the selected one in `accent` / `onAccent`, the
  others in `surface` / `onSurface`.

At night the map also gets `nightMapStyle` (`googleStyleNightMapStyle` by
default).

Words come from `NavigationStrings`
(English by default; `NavigationStrings.vietnamese()` is included, or build
your own). Instructions, distances, durations, times and speeds come from a
core formatter, for example `formatter: const VietnameseGuidanceFormatter()`.
The speedometer shows `formatter.speedValue(…)` and `formatter.speedUnit`
(whole km/h by default); override both for another unit, such as mph:

```dart
GoogleStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: center,
  formatter: const VietnameseGuidanceFormatter(),
  strings: const NavigationStrings.vietnamese(),
  nightColors: GoogleStyleColors.night,
);

class MphFormatter extends EnglishGuidanceFormatter {
  const MphFormatter();

  @override
  String speedValue(double metresPerSecond) =>
      '${(metresPerSecond * 2.23694).round()}';

  @override
  String get speedUnit => 'mph';
}
```

Large text scales are supported: texts ellipsise or shrink to fit, and the
turn card's distance and the trip sheet's time left stop growing at 1.6×.

### Route option ids

Besides the ids listed under Reserved ids below, the route options use polylines and markers whose ids
all start with `navigation_engine_option_`. Do not reuse that prefix in your
own `markers` or `polylines`. Alternate routes use
`navigation_engine_alternate_*`, search pins use
`navigation_engine_search_*`, and the destination pin is
`navigation_engine_destination`.

The route options are drawn through `RoutePreviewMap`, which
`GoogleMapsNavigationMap` implements; `flow.preview` and `flow.select` use it.
Its route fits account for the map's own padding (`mapPadding`, the view's
focus padding), so the routes show in the middle of the space above the
panel.

### Trademark

This UI is inspired by Google Maps. It is not an official Google product and
is not affiliated with or endorsed by Google. It uses no Google logos or
assets.

## Vehicle marker

While the camera follows the vehicle it is drawn by Flutter (`puck`); when
the user pans away it is a native marker on the map. The marker icon is a PNG
rendered at the device pixel ratio (the view reads it from `MediaQuery` and
re-renders when it changes), so it keeps the puck's logical size on any
density. When `puck` is a `CarPuck`, that puck's size and colour are used. For
any other widget pass `vehicleImage` (a `VehicleImageBuilder`, for example
`(pixelRatio) => myRenderer(pixelRatio)`), otherwise the default `CarPuck` is
drawn on pan. If rendering fails, the default Google marker is kept.

`routeColors` changes redraw the route polylines (colours and widths).
`vehicleImage` and `puck` are read once.

## Reserved ids

The adapter owns these ids; do not reuse them in your own `markers` or
`polylines`:

- polylines: `navigation_engine_driven`, `navigation_engine_ahead`
- markers: `navigation_engine_vehicle`, `navigation_engine_destination`

## Feature parity

What each map adapter supports. The map interfaces and helpers come from
navigation_engine_flutter; each adapter re-exports the interfaces' names.

| | Google Maps | MapLibre | flutter_map | Mapbox |
|---|---|---|---|---|
| Drop-in screen | `GoogleStyleNavigation` | `MapLibreStyleNavigation` | `NeutralNavigation` | `MapboxStyleNavigation` |
| Map tap and long press (`onMapTap`, `onMapLongPress`; a tap on a feature the adapter draws is not a map tap; a tap on the vehicle is) | yes | yes | yes | yes |
| When `onMapTap` is called | one turn of the event loop after the SDK reports the tap | one turn after the SDK reports it | after flutter_map's double-tap window (about 250 ms), then one turn | one turn after the SDK reports it |
| Search pins (`SearchPinsMap`) | yes | yes | yes | yes |
| Destination pin (`DestinationPinMap`) | yes | yes | yes | yes |
| Alternate routes (`AlternateRoutesMap`) | yes | yes | yes | yes |
| A tap on the route where an alternate shares the road | a map tap: each alternate is drawn only from 40 m before it leaves the route to 40 m after it rejoins it (`alternateLinePoints`) | the same | the same | the same |
| Colours left unset (`labelColors`, `alternateColor`, `fasterLabelColors`, `slowerLabelColors`, `searchPinColor`) | the shared day defaults, `MapDefaultColors` | the same | the same | the same |
| `horizontalFocus` (side panels) | view and drop-in (landscape panel) | view; the drop-in has no side panel | view; the drop-in has no side panel | view; the drop-in has no side panel |
| Traffic and satellite | yes: `trafficEnabled` and `mapType`, the Google-style menu's switches | from the style: pass a satellite or traffic style as `styleString` | from the tiles: pass satellite tiles as `tileUrlTemplate`; no traffic layer | from the style: pass `MapboxStyles.STANDARD_SATELLITE` as `styleUri`; traffic needs your own source and layers |
| Web | a long press is a right click | a long press is a double click, which first calls `onMapTap` twice and zooms in | as on mobile | no long press (Mapbox GL JS has none): `onMapLongPress` is never called |

The drop-ins pass their theme's colours, by day and at night. An app that
builds a view itself (from a `GoogleStyleFlowScaffold`'s `mapBuilder`, say)
passes `alternateColor`, `fasterLabelColors`, `slowerLabelColors` and
`searchPinColor` (and `labelColors`) to follow its theme and night mode;
left unset, every adapter uses the same day colours (`MapDefaultColors`).

The MapLibre, flutter_map and Mapbox views ignore `layers.traffic` and
`layers.satellite` when a `GoogleStyleFlowScaffold`'s `mapBuilder` builds
them: switch the style or the tiles yourself. For GPS fixes and routes with
any adapter, see `navigation_geolocator` (`GeolocatorFixSource`) and
`navigation_osrm` (`OsrmRouteProvider`).

## How the session is driven

The view's `NavigationMapFrame` ticks the session only while it is on
screen. A full-screen route pushed on top mutes it: no guidance and no
reroute until the user returns. Show a session in one view at a time; two
frames on one session tick it twice. To keep guidance running off-screen,
call `session.tick(dt)` yourself, for example from a `Timer` or your own
`Ticker`.

## Routing and search

[Google Maps Platform](https://developers.google.com/maps) routing and
search for [navigation_engine](https://pub.dev/packages/navigation_engine):
a `RouteProvider` on the
[Routes API](https://developers.google.com/maps/documentation/routes) v2,
and a `PlaceSearchProvider` on the
[Places API (New)](https://developers.google.com/maps/documentation/places/web-service/op-overview)
and the
[Geocoding API](https://developers.google.com/maps/documentation/geocoding/overview).
The routing and search code is pure Dart, on `http`; it uses no Google SDK
and no native code, and imports neither Flutter nor the map SDK. The
package itself still depends on `google_maps_flutter`, so an app that adds
it for routing alone also ships the Google Maps SDK.

> **Show these results on a Google map.** Your use of these APIs is
> governed by the
> [Google Maps Platform Terms of Service](https://cloud.google.com/maps-platform/terms)
> and the
> [Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms).
> They forbid using Google Maps content, which includes the Routes and
> Places results this package returns, with a map that is not Google's
> ("No use with non-Google maps"). Draw the routes and places on a Google
> map, such as `navigation_google_maps`'s, not on a Mapbox,
> MapLibre or OpenStreetMap map. The terms also limit what you may store
> or cache of the results, and set the attribution to show; this package
> caches nothing. (Customers with a billing address in the European
> Economic Area have different terms: check the ones that apply to you.)
> Read them for your use case before you ship.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_google_maps: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_google_maps/navigation_google_maps.dart';

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

### API key

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

### Billing

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

### Routes: `GoogleRoutesRouteProvider`

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
| `userAgent` | `navigation_google_maps/0.1.0`; null on the web | Null sends none. On the web it defaults to null: a browser would send a CORS preflight. |
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

### Place search: `GooglePlacesSearch`

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

### Errors

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

### Testing

Pass a fake `http.Client`, such as `MockClient` from
`package:http/testing.dart`, as `client`: no network and no key needed.
The package's own tests work that way, on fixtures hand-written to the
documented answers (none was recorded). Tests of what differs under
dart2js (the polyline decoding, the coordinates' text, the key scrub, the
web's `User-Agent`) also run in Chrome:

```sh
flutter test --platform chrome --tags js
```

A live smoke check against Google runs only with a key in the environment
(six requests, billed to the key's project; the key must allow the three
APIs). It fetches a raw Routes answer in Ho Chi Minh City and fails on any
`maneuver` the package does not map, printing the values and the
instructions it saw; it also checks real routes, a Places session and a
reverse geocoding:

```sh
GOOGLE_ROUTES_KEY=... flutter test -t live test/routing
```

Without the key those tests are skipped.
