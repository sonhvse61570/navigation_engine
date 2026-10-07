# navigation_engine example

A Flutter app that drives a 5.5 km sample route in Ho Chi Minh City with
simulated GPS (1 Hz, noisy, late) on [flutter_map](https://pub.dev/packages/flutter_map).
No API key needed.

    flutter run --profile        # judge smoothness in profile mode

The map comes from `navigation_engine_flutter_map`
(`FlutterMapNavigationView`) and the banner from
`navigation_engine_flutter` (`NavigationBanner`).

There is also a console demo that prints every voice prompt:

    dart run bin/console.dart

Map tiles come from the OpenStreetMap tile servers, which are for light,
demo use only — see the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/).
Map and route data © OpenStreetMap contributors.
