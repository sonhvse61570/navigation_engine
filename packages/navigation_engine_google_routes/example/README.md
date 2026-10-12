Demo of navigation_engine_google_routes: searches the Places API (New) for a destination (in one autocomplete session), then asks the Routes API for the driving routes to it from Ben Thanh Market (Ho Chi Minh City), and prints each route's length, duration and manoeuvres.

It needs a Google Maps Platform API key that may call the Routes API and the Places API (New), in the environment, and makes live requests (one autocomplete session and one Compute Routes request, billed to the key's project):

```sh
GOOGLE_ROUTES_KEY=... dart run bin/main.dart "Nhà thờ Đức Bà"
GOOGLE_ROUTES_KEY=... dart run bin/main.dart "Chợ Lớn" 10.7884,106.6905   # another start
```

Without the key it prints how to set it and exits. The test (`dart test`) uses a fake client: no key, no network.

It prints text only. In an app, show Google's routes and places on a Google map, as Google Maps Platform's terms ask (see the package README).
