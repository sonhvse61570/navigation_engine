import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// The device GPS, through [geolocator](https://pub.dev/packages/geolocator),
/// as a [FixSource].
///
/// [start] checks that location services are on and asks for the location
/// permission when it has not been granted yet. A failure becomes an error
/// on [fixes] (a `NavigationSession` reports it as a `FixSourceError`):
///
/// - location services off: [LocationServiceDisabledException];
/// - permission denied, or denied forever: [PermissionDeniedException];
/// - any other failure of the platform: that error.
///
/// [start] itself never throws. After such an error the source stays
/// running but delivers nothing: [stop] and [start] it to try again (when
/// the user has turned location on, say). Errors of the position stream
/// are forwarded as they come, and the fixes keep coming after them.
///
/// The app declares the platform's location permissions (see the
/// geolocator README); the source only asks for them at run time.
class GeolocatorFixSource implements FixSource {
  /// Creates a source that reads [geolocator] (the platform's own, by
  /// default) with [locationSettings] and stamps fixes with [clock].
  ///
  /// [clock] must be the clock of the `NavigationSession` that reads this
  /// source (`NavigationSession(clock: ...)`, `DateTime.now` by default):
  /// the motion engines compare a fix's time with the session's `now`.
  GeolocatorFixSource({
    GeolocatorPlatform? geolocator,
    this.locationSettings = defaultLocationSettings,
    DateTime Function() clock = DateTime.now,
    this.isWeb = kIsWeb,
  }) : _geolocator = geolocator ?? GeolocatorPlatform.instance,
       _clock = clock;

  /// The best accuracy the platform has, with no distance filter: one fix
  /// per platform update, which the navigation engine needs to move the
  /// vehicle smoothly.
  static const LocationSettings defaultLocationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
  );

  /// How the position stream is requested. Pass a platform subclass
  /// (`AndroidSettings`, `AppleSettings`, `WebSettings`) for platform
  /// options such as a foreground notification or background updates.
  final LocationSettings locationSettings;

  /// Whether the positions come from geolocator's web implementation,
  /// which never sets `Position.hasSpeed` or `Position.hasHeading`: there
  /// the two flags are ignored and only the value rules apply. [kIsWeb] by
  /// default; tests pass it to exercise either path.
  final bool isWeb;

  final GeolocatorPlatform _geolocator;
  final DateTime Function() _clock;
  final _controller = StreamController<NavFix>.broadcast();
  StreamSubscription<Position>? _subscription;
  bool _running = false;

  /// Bumped by every [start] and [stop]: a permission flow that finishes
  /// under an older generation was stopped (or restarted) while it waited,
  /// and gives up silently.
  int _generation = 0;

  /// The permission request the platform is showing, shared by every flow
  /// until it completes: platforms refuse a second request while one is
  /// open (`PermissionRequestInProgressException`), which a stop and a
  /// start during the dialog would otherwise trigger.
  Future<LocationPermission>? _permissionRequest;

  @override
  Stream<NavFix> get fixes => _controller.stream;

  @override
  bool get isRunning => _running;

  /// Starts the permission flow, then the position stream. Calling it while
  /// running, or after [dispose], does nothing. Never throws: failures
  /// arrive as errors on [fixes], which is a broadcast stream, so listen
  /// before calling [start] or an early error (a denial, say) is lost.
  @override
  void start() {
    if (_running || _controller.isClosed) return;
    _running = true;
    unawaited(_subscribe(++_generation));
  }

  bool _isCurrent(int generation) =>
      generation == _generation && !_controller.isClosed;

  Future<void> _subscribe(int generation) async {
    try {
      final servicesOn = await _geolocator.isLocationServiceEnabled();
      if (!_isCurrent(generation)) return;
      if (!servicesOn) throw const LocationServiceDisabledException();

      var permission = await _geolocator.checkPermission();
      if (!_isCurrent(generation)) return;
      if (permission == LocationPermission.denied) {
        permission = await (_permissionRequest ??= _geolocator
            .requestPermission()
            .whenComplete(() => _permissionRequest = null));
        // stop() (or a stop and a newer start) happened while asking.
        if (!_isCurrent(generation)) return;
      }
      switch (permission) {
        case LocationPermission.denied:
          throw const PermissionDeniedException('Location permission denied');
        case LocationPermission.deniedForever:
          throw const PermissionDeniedException(
            'Location permission denied forever: the user must allow it in '
            'the system settings',
          );
        // unableToDetermine (web): the browser asks when the stream starts.
        case LocationPermission.whileInUse ||
            LocationPermission.always ||
            LocationPermission.unableToDetermine:
          break;
      }

      _subscription = _geolocator
          .getPositionStream(locationSettings: locationSettings)
          .listen(
            (position) {
              final fix = _toFix(position);
              if (fix != null) _controller.add(fix);
            },
            onError: _controller.addError,
            onDone: () => _ended(generation),
          );
    } catch (error, stackTrace) {
      if (_isCurrent(generation)) _controller.addError(error, stackTrace);
    }
  }

  /// The platform closed the position stream: the source stops (so [start]
  /// subscribes again) and says so on [fixes].
  void _ended(int generation) {
    if (!_isCurrent(generation)) return;
    _subscription = null;
    _running = false;
    _generation++;
    _controller.addError(
      StateError('The platform closed the position stream'),
      StackTrace.current,
    );
  }

  /// One [Position] as a [NavFix], stamped on arrival, or null to drop it.
  ///
  /// Position: a NaN or infinite latitude or longitude is dropped. No
  /// placeholder position is safe, and one such fix would poison every
  /// distance the engine measures from it (snapping, the jump filter,
  /// the motion), so the session simply waits for the next fix.
  ///
  /// Speed is null when the platform has none. First the flag:
  /// `Position.hasSpeed` is false when the platform measured no speed
  /// (Android, iOS and Windows set it). geolocator's web implementation
  /// never sets the flags, so with [isWeb] they are ignored. Then, as
  /// fallbacks for platforms and apps that report "no speed" in-band:
  /// iOS sends a negative value; Android without a speed, and
  /// mock-location apps whatever the vehicle does, send 0 with a
  /// `speedAccuracy` of 0. Taken as a measured standstill, such a 0 held
  /// the vehicle back and then made it jump tens of metres to the next
  /// fix; as null, the engine estimates the speed from the fixes instead.
  /// A 0 with a non-zero `speedAccuracy` is a measured standstill and is
  /// kept. A NaN or infinite speed is unknown too.
  ///
  /// Heading is null when `Position.hasHeading` is false (ignored with
  /// [isWeb]), when it is negative or not finite, and below 1 m/s or
  /// without a speed, where the course over ground is noise. It is wrapped
  /// into [0, 360). On the web, geolocator reports a missing heading as 0,
  /// so a browser that gives a speed but no heading yields north; browsers
  /// normally report the two together.
  ///
  /// Accuracy: [NavFix.accuracy] cannot be unknown, so a NaN or infinite
  /// accuracy becomes [double.infinity], which `FixFilter` (and so the
  /// session) drops as too inaccurate, counting it as rejected.
  /// `Position.hasAccuracy` is not used: Android reports a missing
  /// accuracy as 0, which reads as a perfect fix, but dropping such fixes
  /// could starve real devices of positions, and mock-location apps do set
  /// an accuracy.
  NavFix? _toFix(Position p) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) return null;
    final unknownSpeed =
        (!isWeb && !p.hasSpeed) ||
        !p.speed.isFinite ||
        p.speed < 0 ||
        (p.speed == 0 && p.speedAccuracy == 0);
    final speed = unknownSpeed ? null : p.speed;
    final knownHeading =
        (isWeb || p.hasHeading) && p.heading.isFinite && p.heading >= 0;
    return NavFix(
      position: GeoPoint(p.latitude, p.longitude),
      accuracy: p.accuracy.isFinite ? p.accuracy : double.infinity,
      time: _clock(),
      speed: speed,
      heading: speed != null && speed >= 1 && knownHeading
          ? p.heading % 360
          : null,
    );
  }

  /// Stops the position stream, or abandons a permission flow in progress
  /// (its outcome, granted or not, is dropped). [start] may be called
  /// again.
  @override
  void stop() {
    _running = false;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Stops the source and closes [fixes]; it cannot be started again.
  @override
  void dispose() {
    stop();
    unawaited(_controller.close());
  }
}
