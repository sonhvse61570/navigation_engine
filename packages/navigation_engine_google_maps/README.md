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
