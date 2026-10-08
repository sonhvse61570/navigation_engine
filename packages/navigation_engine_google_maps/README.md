# navigation_engine_google_maps

A smooth turn-by-turn navigation view for Google Maps
([google_maps_flutter](https://pub.dev/packages/google_maps_flutter)), built
on [navigation_engine](https://pub.dev/packages/navigation_engine).

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

## Google-style navigation UI

A complete navigation screen in the style of a phone navigation app: route
options on the map with duration labels, turn-by-turn guidance with lane
arrows, a speedometer, a trip footer, day and night themes, and an arrival
panel.

The library re-exports what the screen takes from navigation_engine and
navigation_engine_flutter (`NavigationSession`, `GeoPoint`,
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`, …), so
the adapter is the only navigation_engine package to depend on (an app that
writes its own `FixSource` or `RouteProvider` adds navigation_engine):

```yaml
dependencies:
  navigation_engine_google_maps: ^0.1.0
```

```dart
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

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
overview resumes the trip. Retry runs only from the error state. The step
list follows the guidance and closes itself on arrival, stop or reroute.

`puck`, `vehicleImage`, `focus` and `initialZoom` are passed to the map
view (see Vehicle marker below).

### Controls

While navigating, each control can be turned off. The toggles mirror the
Google Navigation SDK's UI settings that this package has data for; all are
true by default and take effect on rebuild:

| Parameter | Mirrors the SDK's | Controls |
| --- | --- | --- |
| `headerEnabled` | `setNavigationHeaderEnabled` | the turn card |
| `footerEnabled` | `setNavigationFooterEnabled` | the trip footer |
| `tripProgressBarEnabled` | `setNavigationTripProgressBarEnabled` | the progress bar on the start edge |
| `speedometerEnabled` | `setSpeedometerEnabled` | the current speed |
| `speedLimitIconEnabled` | `setSpeedLimitIconEnabled` | the speed limit sign |
| `recenterButtonEnabled` | `setRecenterButtonEnabled` | the Re-center button |
| `compassEnabled` | the map's compass setting | the compass button, shown only while the camera follows the vehicle |
| `routeOverviewButtonEnabled` | `showRouteOverview` | the footer's overview button |

`onMuteToggle` (with `muted`) adds a sound button and `onReportIncident` a
report button, both below the header; the app owns the sound and the report.
The compass needle follows the camera bearing, and a tap switches between
heading up and north up (`session.camera.headingUp`); a switch the app makes
shows at once. The bearing is the one the follow camera sends, not one read
back from the map, so it is right while following, the only time the compass
shows (a gesture that rotates the map stops following and hides it). Its
accessibility label is its tooltip, the mode a tap switches to.

The Re-center button sits at the bottom start, above the speedometer, as in
Google's navigation UI. It shows once the user has moved the map.

### Built on navigation_engine_flutter

`GoogleStyleNavigation` is a `NavigationFlowScaffold` (from
`navigation_engine_flutter`) dressed with the Google-style pieces. The
shared vocabulary lives in that package and is re-exported here, with what
the drop-in takes: `NavigationSession` and `GeoPoint` (navigation_engine),
`NavigationFlowController`, `NavigationStrings`, `SpeedLimitSign`,
`RouteColors`, `CarPuck`, `VehicleImageBuilder`, `RouteLabelColors`,
`fitCameraToBounds`, `paintRouteLabel` and `laneDirectionIcon`. To build a
screen in another look, use the scaffold directly.

The UI is built from public pieces you can use on their own:

- `GoogleStyleNavigation`: the drop-in screen that binds the pieces to a flow.
- `GoogleStyleManeuverHeader`: the next manoeuvre, its distance and street.
- `GoogleStyleLaneGuidance`: the lane arrows before a manoeuvre.
- `GoogleStyleTripFooter`: arrival time, remaining time and distance, and the end, steps and overview buttons.
- `GoogleStyleSpeedometer`: the current speed and the speed limit sign (`SpeedLimitSign`).
- `GoogleStyleRecenterButton`: brings the camera back to the vehicle.
- `GoogleStyleTripProgressBar`: the share of the trip driven, a bar on the start edge.
- `GoogleStyleCompassButton`: a needle that points to north, and a tap to switch heading up and north up.
- `GoogleStyleRoundButton`: the round map button of the compass, sound and report.
- `GoogleStyleOverviewPanel`: the route options, loading and error states.
- `GoogleStyleStepList`: the list of steps of a route.
- `GoogleStyleArrivalPanel`: the arrival summary.
- `googleStyleNightMapStyle`: a dark map style, used at night.
- `fitCameraToBounds` and `paintRouteLabel` (from `navigation_engine_flutter`, re-exported here): the camera fit and the route label bubble the overview uses.

### Theme and language

Colours come from `GoogleStyleColors`; pass your own to `dayColors` and
`nightColors` (`GoogleStyleColors.day` and `GoogleStyleColors.night` are the
defaults, switched by `flow.isNight`). They reach:

- the panels: the overview, the trip footer, the speedometer, the step list
  and the arrival (`surface`, `onSurface`, `accent`, …);
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
turn card's distance and the footer's time left stop growing at 1.6×.

### Route option ids

Besides the ids listed under Reserved ids below, the route options use polylines and markers whose ids
all start with `navigation_engine_option_`. Do not reuse that prefix in your
own `markers` or `polylines`.

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
- marker: `navigation_engine_vehicle`

## How the session is driven

The view's `NavigationMapFrame` ticks the session only while it is on
screen. A full-screen route pushed on top mutes it: no guidance and no
reroute until the user returns. Show a session in one view at a time; two
frames on one session tick it twice. To keep guidance running off-screen,
call `session.tick(dt)` yourself, for example from a `Timer` or your own
`Ticker`.
