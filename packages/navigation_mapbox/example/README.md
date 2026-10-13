Demo of navigation_mapbox: drives a sample route with simulated GPS on Mapbox; run it with your public token: `flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk...`.

## Routing and search

`navigation_mapbox` also holds Mapbox routing and place search. This snippet
builds both from a token passed with `--dart-define`, and starts no UI:

```dart
import 'package:navigation_mapbox/navigation_mapbox.dart';

const mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

final router = MapboxDirectionsRouteProvider(
  accessToken: mapboxToken,
  language: 'vi',
);
final search = MapboxSearch(
  accessToken: mapboxToken,
  language: 'vi',
  country: 'vn',
);
```

Run the app with `flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk...`, and
pass `router` as the session's `routeProvider`. A public `pk.` token is
enough. Mapbox's terms govern whether Directions and Search results may be
shown on a non-Mapbox map; read them before you do (see the package README).
