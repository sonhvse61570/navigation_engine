# navigation_engine

[![CI](https://github.com/sonhvse61570/navigation_engine/actions/workflows/ci.yml/badge.svg)](https://github.com/sonhvse61570/navigation_engine/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Smooth, map-agnostic turn-by-turn navigation for Dart and Flutter, split into small packages.

## Packages

| Package | Description |
|---|---|
| [`navigation_engine`](packages/navigation_engine) | Core: snapping, smooth motion, camera, guidance, session (pure Dart) |
| [`navigation_engine_flutter`](packages/navigation_engine_flutter) | Flutter building blocks: frame, follow/recenter, puck, banner |
| [`navigation_engine_flutter_map`](packages/navigation_engine_flutter_map) | View for flutter_map (no key) |
| [`navigation_engine_maplibre`](packages/navigation_engine_maplibre) | View for MapLibre (no key with free styles) |
| [`navigation_engine_google_maps`](packages/navigation_engine_google_maps) | View for Google Maps |
| [`navigation_engine_mapbox`](packages/navigation_engine_mapbox) | View for Mapbox |
| [`navigation_engine_geolocator`](packages/navigation_engine_geolocator) | GPS fixes from geolocator (`GeolocatorFixSource`) |
| [`navigation_engine_osrm`](packages/navigation_engine_osrm) | Routes from an OSRM server (`OsrmRouteProvider`, pure Dart) |
| [`navigation_engine_vietmap`](packages/navigation_engine_vietmap) | Vietmap: MapLibre styles, routes and place search (pure Dart) |
| [`navigation_engine_goong`](packages/navigation_engine_goong) | Goong: MapLibre styles, routes and place search (pure Dart) |
| [`navigation_engine_mapbox_directions`](packages/navigation_engine_mapbox_directions) | Mapbox: routes with lanes and speed limits (Directions API; speed limits on the driving profiles only, lanes without Mapbox's preferred-lane flag) and place search (Search Box API) (pure Dart) |
| [`navigation_engine_google_routes`](packages/navigation_engine_google_routes) | Google: routes (Routes API) and place search (Places API (New) and Geocoding), no lanes or speed limits (pure Dart) |

More routing adapters will live next to them.

Development: `dart pub get` at the root, then `dart test` in a package.

## Providers

| | Provider | Package | Key |
|---|---|---|---|
| Map tiles | OpenStreetMap, through flutter_map | `navigation_engine_flutter_map` | none |
| | OpenFreeMap, through MapLibre | `navigation_engine_maplibre` | none |
| | Vietmap, through MapLibre | `navigation_engine_maplibre` with `VietmapStyles` | tile key |
| | Goong, through MapLibre | `navigation_engine_maplibre` with `GoongStyles` | Maptiles key |
| | Google Maps | `navigation_engine_google_maps` | Maps SDK key |
| | Mapbox | `navigation_engine_mapbox` | access token |
| Routing | OSRM | `OsrmRouteProvider` (`navigation_engine_osrm`) | none; the public demo server is for testing only |
| | Vietmap | `VietmapRouteProvider` (`navigation_engine_vietmap`) | services key |
| | Goong | `GoongRouteProvider` (`navigation_engine_goong`) | API key |
| | Mapbox | `MapboxDirectionsRouteProvider` (`navigation_engine_mapbox_directions`) | access token |
| | Google | `GoogleRoutesRouteProvider` (`navigation_engine_google_routes`) | API key |
| Place search | Vietmap | `VietmapPlaceSearch` (`navigation_engine_vietmap`) | services key |
| | Goong | `GoongPlaceSearch` (`navigation_engine_goong`) | API key |
| | Mapbox | `MapboxSearch` (`navigation_engine_mapbox_directions`) | access token |
| | Google | `GooglePlacesSearch` (`navigation_engine_google_routes`) | API key |
| | Photon, or any geocoder | bring your own: implement `PlaceSearchProvider` (`navigation_engine`) | yours |

Vietmap and Goong publish no developer terms: check them with the provider
before production use (see each package's README). Keep their REST keys
behind your back end or a proxy; the packages take a `baseUrl` for that.

Google Routes, Places and Geocoding results (everything
`navigation_engine_google_routes` returns) must be shown on a Google map
(`navigation_engine_google_maps`), per Google Maps Platform's terms: see
`navigation_engine_google_routes`'s README.

Mapbox's terms also set which map the results may be shown on, as well as
what you may store and the attribution you must show: see
`navigation_engine_mapbox_directions`'s README, and read them for your
use case.

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
any adapter, see `navigation_engine_geolocator` (`GeolocatorFixSource`) and
`navigation_engine_osrm` (`OsrmRouteProvider`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[BSD 3-Clause](LICENSE)
