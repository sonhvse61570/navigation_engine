# navigation_engine_maplibre

A smooth turn-by-turn navigation view for MapLibre
([maplibre_gl](https://pub.dev/packages/maplibre_gl)), built on
[navigation_engine](https://pub.dev/packages/navigation_engine). No API key
needed with a free style such as OpenFreeMap.

```dart
void main() {
  // Android: let Flutter widgets (the vehicle puck) draw over the map.
  MapLibreMap.useHybridComposition = true;
  runApp(const App());
}

final session = NavigationSession(fixes: myFixSource)..start(route: route);

Stack(children: [
  MapLibreNavigationView(
    session: session,
    styleString: 'https://tiles.openfreemap.org/styles/liberty',
    initialCenter: route.points.first,
  ),
  NavigationBanner(session: session), // from navigation_engine_flutter
]);
```

The route and the vehicle marker are GeoJSON sources and layers
(`navigation_engine_*` ids) added when the style loads.

## Vehicle marker

While the camera follows the vehicle it is drawn by Flutter (`puck`); when
the user pans away it is a native symbol on the map. The native image is a
PNG rendered at the device pixel ratio (the view sets it from `MediaQuery`).
When `puck` is a `CarPuck`, that puck's size and colour are used. For any
other widget pass `vehicleImage` (a `VehicleImageBuilder`, for example
`(pixelRatio) => myRenderer(pixelRatio)`), otherwise the default `CarPuck`
is drawn on pan.

`routeColors` changes are applied to the route lines (colour, width and the
colour's alpha as line opacity). `vehicleImage` and `puck` are read once.

## Reserved ids

The adapter owns these ids on the map; do not reuse them for your own
sources, layers or images:

- sources: `navigation_engine_driven`, `navigation_engine_ahead`,
  `navigation_engine_vehicle`
- layers: `navigation_engine_driven-line`, `navigation_engine_ahead-line`,
  `navigation_engine_vehicle-symbol`
- image: `navigation_engine_puck`

## How the session is driven

The view's `NavigationMapFrame` ticks the session only while it is on
screen. A full-screen route pushed on top mutes it: no guidance and no
reroute until the user returns. Show a session in one view at a time; two
frames on one session tick it twice. To keep guidance running off-screen,
call `session.tick(dt)` yourself, for example from a `Timer` or your own
`Ticker`.
