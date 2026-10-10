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
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`, …) and
the map interfaces' names (`SearchPinsMap`, `DestinationPinMap`,
`AlternateRoutesMap`, `AlongRoutePlace`, `AlternateRoute`, `paintSearchPin`,
`paintDestinationPin`), so
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

The attribution button keeps above the panel, the trip progress (and the
speed sign) and the arrival panel (`attributionButtonMargins`), as the map
data's licences require (the view shows no logo, maplibre_gl's default); with your own `MapLibreNavigationView`, set its
`bottomInset`.

### Day and night

`flow.isNight` switches the look. With a `nightStyleString`, night loads that
style; a switch reloads the style, and the route, the vehicle and the route
options are drawn again once it has loaded. Without it, the day style is kept.

### Route options

`MapLibreNavigationMap` implements `RoutePreviewMap`, so `flow.preview` and
`flow.select` draw the options on the map, and a tap on an option line or its
label selects that route. Taps elsewhere are ignored.

### Alternates, pins and map taps

`MapLibreNavigationMap` also implements `AlternateRoutesMap`,
`SearchPinsMap` and `DestinationPinMap` (navigation_engine_flutter):

- **Alternate routes** while navigating: grey lines under the route
  (`alternateColor`, 70 % as wide), each with a bubble (`alternateLabel`,
  `fasterLabelColors` / `slowerLabelColors`) at most 400 m past where it
  leaves the route, else at the middle of the rest. A tap on a line or a
  bubble switches to that alternate; a tap on one still drawn for an older
  list is ignored. `MapLibreStyleNavigation` words the bubbles with its
  `strings` ("2 min faster").
- **Search pins** (`showSearchPins`, `pinColor`), the focused one larger
  and on top; a tap calls `onTap` with the place.
- **The destination pin** (`showDestinationPin`): the shared red pin of
  `paintDestinationPin`. The scaffolds pin the end of the selected route in
  the overview, while navigating and arrived.

Bottom to top above the route: alternate bubbles, route option labels, the
destination pin, the search pins, then the vehicle. All of them, and the
alternate lines, are drawn again after a style reload.

`MapLibreNavigationView.onMapTap` and `onMapLongPress` (forwarded by
`MapLibreStyleNavigation`) get the app's taps on the map as `GeoPoint`s. A
tap on a route option, an alternate, a bubble or a pin is not a map tap: the
SDK reports none for it, and a map tap in the same frame after such a tap,
or that such a tap follows in the same turn of the event loop, is dropped
anyway. A map tap is delivered one turn of the event loop after the SDK
reports it; a long press at once.

### Side panels and Google-style screens

`horizontalFocus` moves the followed vehicle across the map (0.5 is the
centre), as `NavigationMapFrame.horizontalFocus`. It is physical (0 is the
left edge in both text directions). The camera insets that move the focus
also move the attribution button (bottom right) clear of a panel on the
right, above `bottomInset`. The view shows no logo (maplibre_gl's
`logoEnabled` defaults to false); its margin (bottom left) moves clear of a
panel on the left all the same.

An app can build the view from a `GoogleStyleFlowScaffold`'s `mapBuilder`:

```dart
GoogleStyleFlowScaffold(
  session: session,
  flow: flow,
  mapBuilder: (context, config, layers) => MapLibreNavigationView(
    key: mapKey, // keeps the platform map across rebuilds
    session: session,
    styleString: dayStyle,
    nightStyleString: nightStyle,
    night: config.isNight,
    initialCenter: start,
    horizontalFocus: layers.horizontalFocus,
    bottomInset: layers.bottomOverlay,
    routeColors: layers.routeColors,
    routeLabel: layers.routeLabel,
    alternateLabel: layers.alternateLabel,
    onRouteOptionTap: config.onRouteOptionTap,
    labelColors: layers.colors.routeLabelColors,
    alternativeRouteColor: layers.colors.alternative,
    alternateColor: layers.colors.alternative,
    fasterLabelColors: layers.colors.fasterLabelColors,
    slowerLabelColors: layers.colors.slowerLabelColors,
    searchPinColor: layers.colors.warning,
    recenterButton: (_) => const SizedBox.shrink(),
    onMapCreated: (_) => config.onMapReady(),
  ),
)
```

MapLibre has no traffic layer and no satellite map type of its own: both
come from the style. The view ignores `layers.traffic` and
`layers.satellite`; an app with a satellite style can pass it as
`styleString` while `layers.satellite` is on.

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
- alternates: the source and line layer `navigation_engine_alternates`, the
  bubbles' source and layer `navigation_engine_alternate_labels` and images
  `navigation_engine_alternate_label_<i>`
- search pins: the source and layer `navigation_engine_search` and the
  images `navigation_engine_search_pin` and
  `navigation_engine_search_pin_focused`
- the destination pin: the source and layer `navigation_engine_destination`
  and the image `navigation_engine_destination_pin`

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

## How the session is driven

The view's `NavigationMapFrame` ticks the session only while it is on
screen. A full-screen route pushed on top mutes it: no guidance and no
reroute until the user returns. Show a session in one view at a time; two
frames on one session tick it twice. To keep guidance running off-screen,
call `session.tick(dt)` yourself, for example from a `Timer` or your own
`Ticker`.
