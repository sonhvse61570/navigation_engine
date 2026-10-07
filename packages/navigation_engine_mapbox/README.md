# navigation_engine_mapbox

A smooth turn-by-turn navigation view for Mapbox
([mapbox_maps_flutter](https://pub.dev/packages/mapbox_maps_flutter)),
built on [navigation_engine](https://pub.dev/packages/navigation_engine).

Set your public access token before building the view:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(const String.fromEnvironment('MAPBOX_ACCESS_TOKEN'));
  runApp(const App());
}
// flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.…
```

```dart
final session = NavigationSession(fixes: myFixSource)..start(route: route);

Stack(children: [
  MapboxNavigationView(session: session, initialCenter: route.points.first),
  NavigationBanner(session: session), // from navigation_engine_flutter
]);
```

The camera padding that keeps the vehicle low on the screen travels with
every `setCamera`. The route and the vehicle marker are GeoJSON sources and
layers (`navigation_engine_*` ids) added when the style loads.

`MapboxNavigationView` turns the map's compass and scale bar off. If Flutter
widgets do not draw over the map on Android, try `MapWidget(textureView:
true)` via your own `MapboxNavigationMap` + `NavigationMapFrame` (wire
`onMapCreated` and `onStyleLoaded` to the `MapWidget` callbacks, and call
`onStyleChanging` when you switch the style). `MapboxNavigationMap` itself
leaves the ornaments alone; call `hideOrnaments()` after `onMapCreated` if
you want them off there too.

## Vehicle marker

While the camera follows the vehicle it is drawn by Flutter (`puck`); when
the user pans away it is a native symbol on the map. The native image is a
PNG rendered at the device pixel ratio (the view sets it from `MediaQuery`)
and added with that scale, so its logical size is right. When `puck` is a
`CarPuck`, that puck's size and colour are used. For any other widget pass
`vehicleImage` (a `VehicleImageBuilder`, for example
`(pixelRatio) => myRenderer(pixelRatio)`), otherwise the default `CarPuck`
is drawn on pan.

`routeColors` changes are applied to the route lines (colour and width,
through `updateLayer`). `vehicleImage` and `puck` are read once.

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
