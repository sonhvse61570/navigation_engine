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

GPS (`navigation_engine_geolocator`) and routing (`navigation_engine_osrm`,
`navigation_engine_google_routes`) adapters will live next to them.

Development: `dart pub get` at the root, then `dart test` in a package.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[BSD 3-Clause](LICENSE)
