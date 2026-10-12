Demo of navigation_engine_vietmap: searches Vietmap for a destination, then asks Vietmap's route v4 for the routes to it from Ben Thanh market (Ho Chi Minh City), and prints each route's length, duration and manoeuvres.

It needs a Vietmap services key in the environment, and makes live requests (each one billed to that key):

```sh
VIETMAP_SERVICES_KEY=... dart run bin/main.dart "Landmark 81"
VIETMAP_SERVICES_KEY=... dart run bin/main.dart "Chợ Bến Thành" 10.7952,106.7216   # another start
```

Without the key it prints how to set it and exits. The test (`dart test`) uses a fake client: no key, no network.
