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

## Mapbox-style navigation UI

`MapLibreStyleNavigation` is a complete navigation screen: the map, route
options with duration labels, turn-by-turn guidance with lanes, the speed and
limit, trip progress, a step list and an arrival panel, bound to a
`NavigationFlowController`. It is named apart from the Mapbox package's
`MapboxStyleNavigation`, so an app can import both.

The library re-exports what the screen takes from navigation_engine and
navigation_engine_flutter (`NavigationSession`, `GeoPoint`,
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`, …), so
the adapter is the only navigation_engine package to depend on (an app that
writes its own `FixSource` or `RouteProvider` adds navigation_engine):

```yaml
dependencies:
  navigation_engine_maplibre: ^0.1.0
  maplibre_gl: ^0.27.1 # MapLibreMapController
```

```dart
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreMapController;
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';

final session = NavigationSession(fixes: myFixSource, routeProvider: provider);
final flow = NavigationFlowController(session: session, routeProvider: provider);

MapLibreStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
  styleString: 'https://tiles.openfreemap.org/styles/liberty',
  nightStyleString: 'https://tiles.openfreemap.org/styles/dark',
  onMapCreated: (MapLibreMapController controller) {},
);

session.start(); // the vehicle shows, and preview() starts from its position
await flow.preview(to: destination); // shows the route options; the user taps Start
```

The app owns, starts and disposes the `session` and the `flow` (flow first,
then the session, then the fix source). Pass `idleBuilder` for your own
overlay, such as a search bar, while the flow is idle. The screen is a
`MapboxStyleFlowScaffold` from `navigation_engine_flutter`, which also
documents the pieces and the theme (`dayColors` / `nightColors`,
`MapboxStyleColors`, `dayRouteColors` / `nightRouteColors`). Words come from
`NavigationStrings` (`NavigationStrings.vietnamese()` is included) and
numbers from `formatter`.

The attribution button and the logo keep above the panel, the trip progress
(and the speed sign) and the arrival panel (`attributionButtonMargins`, `logoViewMargins`), as the
map data's licences require; with your own `MapLibreNavigationView`, set its
`bottomInset`.

### Day and night

`flow.isNight` switches the look. With a `nightStyleString`, night loads that
style; a switch reloads the style, and the route, the vehicle and the route
options are drawn again once it has loaded. Without it, the day style is kept.

### Route options

`MapLibreNavigationMap` implements `RoutePreviewMap`, so `flow.preview` and
`flow.select` draw the options on the map, and a tap on an option line or its
label selects that route. Taps elsewhere are ignored.

### Trademark

This UI is inspired by Mapbox's navigation apps. It is not an official Mapbox
product and is not affiliated with or endorsed by Mapbox. It uses no Mapbox
logos, icons or palettes.

### Zoom scale

Camera zooms (`CameraTarget`, `initialZoom`) use the Google Maps scale on
every provider. MapLibre's world is made of 512 px tiles, so the adapter shows
each zoom one level lower; the same zoom frames the same area on all
providers.

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
- route options: every source, layer and image whose id starts with
  `navigation_engine_option_` (the lines and casings
  `navigation_engine_option_<i>` / `navigation_engine_option_casing_<i>`, the
  labels source and layer `navigation_engine_option_labels`, and the label
  images `navigation_engine_option_label_<i>_<sel|alt>`)

## How the session is driven

The view's `NavigationMapFrame` ticks the session only while it is on
screen. A full-screen route pushed on top mutes it: no guidance and no
reroute until the user returns. Show a session in one view at a time; two
frames on one session tick it twice. To keep guidance running off-screen,
call `session.tick(dt)` yourself, for example from a `Timer` or your own
`Ticker`.
