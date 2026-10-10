## 0.1.0

- Initial release.
- `GeolocatorFixSource`, a `FixSource` on the device GPS through
  geolocator. `start` checks that location services are on and asks for
  the location permission; services off
  (`LocationServiceDisabledException`), a denial or a denial forever
  (`PermissionDeniedException`) become errors on `fixes`, and `start`
  never throws (listen to `fixes` first: it is a broadcast stream). `stop`
  during the permission prompt drops its outcome, and a `start` while the
  prompt is still open waits for the same request instead of asking
  again. If the platform closes the position stream, the source stops and
  reports a `StateError`.
- Depends on `geolocator_platform_interface` ^4.3.0 for
  `Position.hasSpeed` and `hasHeading`.
- `locationSettings` (default `defaultLocationSettings`:
  `bestForNavigation`, no distance filter) and `geolocator` (the
  `GeolocatorPlatform`, for tests) are injectable.
- Fixes are stamped on arrival with `clock` (`DateTime.now` by default),
  which must be the session's clock. A speed the platform does not have
  (`hasSpeed` false; or negative, or 0 with a `speedAccuracy` of 0, as
  mock-location apps send; or not finite) is null, and so is the heading
  without `hasHeading`, below 1 m/s, negative or not finite; a heading is
  wrapped into [0, 360). On the web
  (`isWeb`, `kIsWeb` by default), where geolocator sets no `has*` flags,
  only the value rules apply. A NaN or infinite accuracy becomes
  `double.infinity`, which `FixFilter` drops; a NaN or infinite latitude
  or longitude drops the fix.
