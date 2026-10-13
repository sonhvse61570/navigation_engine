Demo of navigation_goong: searches Goong for a destination (in one autocomplete session), then asks Goong's direction v2 for the routes to it from Hoan Kiem Lake (Hanoi), and prints each route's length, duration and manoeuvres.

It needs a Goong API key (the REST key, not the Maptiles key) in the environment, and makes live requests (each one billed to that key):

```sh
GOONG_API_KEY=... dart run bin/main.dart "Hồ Tây"
GOONG_API_KEY=... dart run bin/main.dart "Lăng Bác" 21.0465,105.7902   # another start
```

Without the key it prints how to set it and exits. The test (`dart test`) uses a fake client: no key, no network.
