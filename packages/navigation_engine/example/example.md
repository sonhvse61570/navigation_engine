# navigation_engine example

A `NavigationSession` wires a `FixSource`, the motion engine, the camera,
guidance and an optional `NavigationMap` / `RouteProvider` into one run:

```dart
import 'package:navigation_engine/navigation_engine.dart';

final session = NavigationSession(
  fixes: myFixSource,        // implements FixSource (GPS, simulator, …)
  map: myNavigationMap,      // implements NavigationMap (optional)
  routeProvider: myRouter,   // extends RouteProvider (optional: rerouting)
);
session.start(route: NavRoute.fromPoints(points, steps: steps));

// Once per display frame, e.g. from a Flutter Ticker:
session.tick(dt);

const formatter = EnglishGuidanceFormatter();
session.announcements.listen((a) => speak(formatter.announcement(a)));
session.guidance.listen((g) => g == null ? hideBanner() : showBanner(g));
session.events.listen((e) {
  if (e is Arrived) session.stop();
});

// App in the background, or the user taps pause:
session.pause(); // stops the FixSource, keeps the route and the progress
session.resume();

// When done (e.g. in State.dispose). Your FixSource is not disposed.
session.dispose();
```

To try it without a GPS, use the simulator from
`package:navigation_engine/testing.dart`:

```dart
import 'package:navigation_engine/testing.dart';

final sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights);
final session = NavigationSession(fixes: SimulatedFixSource(sim));
session.start(route: sampleRoute);
```

## Flutter app

The app in `example/lib/` drives the 5.5 km sample route in Ho Chi Minh City with simulated GPS on
flutter_map (no API key needed), using `FlutterMapNavigationView` from
`navigation_engine_flutter_map`.

    cd example
    flutter run --profile        # judge smoothness in profile mode

## Console demo

Drives the sample route on a virtual clock (no map, no waiting) and prints
every voice prompt:

    cd example
    dart run bin/console.dart
