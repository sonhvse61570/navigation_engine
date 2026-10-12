Demo of navigation_engine_mapbox_directions: searches the Mapbox Search Box API for a destination (in one search session), then asks the Mapbox Directions API for the driving-traffic routes to it from Hoan Kiem Lake (Hanoi), and prints each route's length, duration and manoeuvres, with the speed limit where each one starts.

It needs a Mapbox access token (a public `pk.` token is enough) in the environment, and makes live requests (one Search Box session and one Directions request, billed to the token's account):

```sh
MAPBOX_TOKEN=pk.... dart run bin/main.dart "Hồ Tây"
MAPBOX_TOKEN=pk.... dart run bin/main.dart "Lăng Bác" 21.0465,105.7902   # another start
```

Without the token it prints how to set it and exits. The test (`dart test`) uses a fake client: no token, no network.
