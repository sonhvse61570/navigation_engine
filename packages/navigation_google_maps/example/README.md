Demo of navigation_google_maps: drives a sample route with simulated GPS on Google Maps; it needs `MAPS_API_KEY` set in `android/local.properties`. On iOS, add `GMSServices.provideAPIKey("…")` in `AppDelegate.swift` before running.


## Routing and search

`navigation_google_maps` also holds Google routing and place search. This
snippet builds both from a key passed with `--dart-define`, and starts no UI:

```dart
import 'package:navigation_google_maps/navigation_google_maps.dart';

const googleKey = String.fromEnvironment('GOOGLE_ROUTES_KEY');

final router = GoogleRoutesRouteProvider(apiKey: googleKey, languageCode: 'vi');
final search = GooglePlacesSearch(
  apiKey: googleKey,
  languageCode: 'vi',
  regionCodes: const ['vn'],
);
```

Run the app with `flutter run --dart-define=GOOGLE_ROUTES_KEY=...`, and pass
`router` as the session's `routeProvider`. The key must allow the Routes API
and the Places API (New). Show the results on a Google map, as the terms ask
(see the package README).
