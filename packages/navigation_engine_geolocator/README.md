# navigation_engine_geolocator

The device GPS for [navigation_engine](https://pub.dev/packages/navigation_engine),
through [geolocator](https://pub.dev/packages/geolocator): a `FixSource`
that asks for the location permission and streams `NavFix`es.

```yaml
dependencies:
  navigation_engine: ^0.1.0
  navigation_engine_geolocator: ^0.1.0
```

```dart
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_geolocator/navigation_engine_geolocator.dart';

final source = GeolocatorFixSource();
final session = NavigationSession(fixes: source);

session.events.listen((event) {
  if (event is FixSourceError) showLocationProblem(event.error);
});
session.start(route: route); // starts the source too

// Later: the session first, then the source.
session.dispose();
source.dispose();
```

## Quick start with any map adapter

`GeolocatorFixSource` (navigation_engine_geolocator) and
`OsrmRouteProvider` (navigation_engine_osrm) plug into the session and the
flow controller, so the same code drives every map adapter: only the
drop-in screen changes. With MapLibre:

```dart
import 'package:navigation_engine_geolocator/navigation_engine_geolocator.dart';
import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';

final source = GeolocatorFixSource();
final router = OsrmRouteProvider(userAgent: 'my_app/1.0');
final session = NavigationSession(fixes: source, routeProvider: router);
final flow = NavigationFlowController(session: session, routeProvider: router);

MapLibreStyleNavigation(
  session: session,
  flow: flow,
  initialCenter: GeoPoint(10.7769, 106.7009),
  styleString: 'https://tiles.openfreemap.org/styles/liberty',
);

session.start(); // asks for the permission; the vehicle shows at the first fix
await flow.preview(to: destination); // OSRM's routes; the user taps Start

// When done: the flow, then the session, then the source and the router.
flow.dispose();
session.dispose();
source.dispose();
router.close();
```

The adapter's library re-exports `NavigationSession`, `GeoPoint` and
`NavigationFlowController`. For another map, swap the import and the
screen:

| Map | Package | Screen |
| --- | --- | --- |
| Google Maps | `navigation_engine_google_maps` | `GoogleStyleNavigation(session: …, flow: …, initialCenter: …)` (set up the Maps API key) |
| MapLibre | `navigation_engine_maplibre` | `MapLibreStyleNavigation(…, styleString: …)` |
| flutter_map | `navigation_engine_flutter_map` | `NeutralNavigation(…, userAgentPackageName: …)` |
| Mapbox | `navigation_engine_mapbox` | `MapboxStyleNavigation(…)` (set the access token first) |

## Permission and errors

`start` checks that location services are on, then asks for the location
permission if the app does not have it yet. It never throws: a problem
arrives as an error on `fixes`, which a `NavigationSession` reports as a
`FixSourceError`:

| Problem | Error |
| --- | --- |
| Location services are off | `LocationServiceDisabledException` |
| The user denied the permission | `PermissionDeniedException` |
| The user denied it forever (only the system settings can allow it) | `PermissionDeniedException` |

After such an error the source stays running but delivers nothing; stop
and start it (or the session) to try again. Stopping while the permission
dialog is open is safe: its answer is dropped, and a start while it is
still open waits for that same dialog instead of asking again (platforms
refuse a second request). Errors of the position stream itself are
forwarded, and fixes keep coming after them. If the platform closes the
stream, the source stops and reports a `StateError`; start it again.

`fixes` is a broadcast stream: listen before `start` (a session does), or
an early error such as a denial is lost.

Declare the permissions as geolocator's README describes:
`ACCESS_FINE_LOCATION` in the Android manifest and
`NSLocationWhenInUseUsageDescription` in the iOS `Info.plist`.

## Settings

The default, `GeolocatorFixSource.defaultLocationSettings`, asks for
`LocationAccuracy.bestForNavigation` with no distance filter: the engine
wants every update. Pass your own `locationSettings`, for example
geolocator's `AndroidSettings` for a foreground notification or
`AppleSettings` for background updates (add `geolocator` to your
dependencies for those classes).

## Fixes

- **Time.** A fix is stamped when it arrives, on `clock` (`DateTime.now`
  by default). Pass the same clock as the session's
  (`NavigationSession(clock: ...)`): the engine measures the GPS delay
  against it.
- **Position.** A fix with a NaN or infinite latitude or longitude is
  dropped: no placeholder position is safe, and the session simply waits
  for the next fix.
- **Speed.** Null when the platform has none: `Position.hasSpeed` is
  false, or, as fallbacks, a negative speed (iOS) or 0 with a
  `speedAccuracy` of 0 (Android without a speed, and mock-location apps
  whatever the vehicle does). Taken as a real standstill, that 0 made the
  vehicle lag and then jump to the next fix; with null the engine
  estimates the speed from the fixes instead. A NaN or infinite speed is
  null too. geolocator's web implementation never sets `hasSpeed` or
  `hasHeading`, so on the web (`isWeb`, `kIsWeb` by default) the flags are
  ignored and only the value rules apply.
- **Heading.** Null when `Position.hasHeading` is false (except on the
  web), when it is negative or not finite, and below 1 m/s (or without a
  speed), where the course over ground is noise. It is wrapped into
  [0, 360). On the web geolocator reports a missing heading as 0, so a
  browser that gives a speed but no heading yields north; browsers
  normally report both.
- **Accuracy.** A NaN or infinite accuracy becomes `double.infinity`, which
  the session's `FixFilter` drops as too inaccurate. `hasAccuracy` is not
  used: Android reports a missing accuracy as 0, which reads as a perfect
  fix, but dropping such fixes could starve real devices of positions.

## Testing

`GeolocatorFixSource(geolocator: fake)` takes any `GeolocatorPlatform`, so
tests can drive permissions and positions without a device.
