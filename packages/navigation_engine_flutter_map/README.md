# navigation_engine_flutter_map

A smooth turn-by-turn navigation view for
[flutter_map](https://pub.dev/packages/flutter_map), built on
[navigation_engine](https://pub.dev/packages/navigation_engine).
No API key needed with OpenStreetMap tiles.

```dart
final session = NavigationSession(fixes: myFixSource)..start(route: route);

Stack(children: [
  FlutterMapNavigationView(
    session: session,
    initialCenter: route.points.first,
    userAgentPackageName: 'com.example.app',
  ),
  NavigationBanner(session: session), // from navigation_engine_flutter
]);
```

The view follows the vehicle heading-up at display rate, draws the route
(driven / ahead), keeps the vehicle at 70 % of the height, stops following
when the user touches the map and offers a recenter button. It attaches
itself as `session.map` while mounted. flutter_map has no tilt.
`onMapReady` hands you the `MapController`; the vehicle marker follows
`CarPuck.size` (or `markerSize` for a custom `puck`).

## How the session is driven

The view ticks the session only while it is on screen. A full-screen route pushed
on top mutes it: no guidance and no reroute until the user returns. Show a
session in one view at a time; two frames on one session tick it twice. To
keep guidance running off-screen, call `session.tick(dt)` yourself, for
example from a `Timer` or your own `Ticker`.

OpenStreetMap's tile servers are for light use only — see the
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/);
set `tileUrlTemplate` to your own provider for production.
