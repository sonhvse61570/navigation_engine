Demo of navigation_engine_osrm: asks an OSRM server for a route and its alternatives and prints each route's length, duration and manoeuvres.

```sh
dart run bin/main.dart                                  # Ben Thanh -> Landmark 81, Ho Chi Minh City
dart run bin/main.dart 10.7719,106.6982 10.7952,106.7216 [https://your-osrm-server]
```

Without a server URL it uses OSRM's public demo server, which is for testing only: it is rate limited and sees the coordinates.
