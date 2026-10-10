import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_geolocator/navigation_engine_geolocator.dart';

/// A [GeolocatorPlatform] driven by the test.
class FakeGeolocator extends GeolocatorPlatform {
  bool servicesOn = true;
  Object? servicesError;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;

  /// When true, [requestPermission] waits until the test completes the
  /// matching entry of [pendingRequests]. Like geolocator_android, a
  /// second request while one is open fails with
  /// [PermissionRequestInProgressException].
  bool holdRequests = false;
  final pendingRequests = <Completer<LocationPermission>>[];

  /// When true, [isLocationServiceEnabled] waits for [pendingServices].
  bool holdServices = false;
  final pendingServices = <Completer<bool>>[];

  /// When true, [checkPermission] waits for [pendingChecks].
  bool holdChecks = false;
  final pendingChecks = <Completer<LocationPermission>>[];

  int serviceChecks = 0;
  int permissionChecks = 0;
  int permissionRequests = 0;
  final settings = <LocationSettings?>[];
  StreamController<Position>? positions;
  int cancels = 0;

  @override
  Future<bool> isLocationServiceEnabled() async {
    serviceChecks++;
    if (servicesError case final error?) throw error;
    if (holdServices) {
      final completer = Completer<bool>();
      pendingServices.add(completer);
      return completer.future;
    }
    return servicesOn;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    permissionChecks++;
    if (holdChecks) {
      final completer = Completer<LocationPermission>();
      pendingChecks.add(completer);
      return completer.future;
    }
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() {
    permissionRequests++;
    if (!holdRequests) return Future.value(afterRequest);
    if (pendingRequests.any((c) => !c.isCompleted)) {
      return Future.error(
        const PermissionRequestInProgressException(
          'A request for location permissions is already running',
        ),
      );
    }
    final completer = Completer<LocationPermission>();
    pendingRequests.add(completer);
    return completer.future;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    final controller = StreamController<Position>(sync: true);
    controller.onCancel = () => cancels++;
    positions = controller;
    return controller.stream;
  }
}

Position position({
  double latitude = 10.77,
  double longitude = 106.70,
  double accuracy = 5,
  double speed = 10,
  double speedAccuracy = 0.5,
  double heading = 90,
  bool hasSpeed = true,
  bool hasHeading = true,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2020),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: speedAccuracy,
  hasSpeed: hasSpeed,
  hasHeading: hasHeading,
);

/// A started source with its listeners attached.
class Harness {
  Harness(
    this.geo, {
    DateTime Function() clock = DateTime.now,
    LocationSettings settings = GeolocatorFixSource.defaultLocationSettings,
    bool isWeb = false,
  }) : source = GeolocatorFixSource(
         geolocator: geo,
         clock: clock,
         locationSettings: settings,
         isWeb: isWeb,
       ) {
    source.fixes.listen(
      fixes.add,
      onError: (Object e, StackTrace _) => errors.add(e),
      onDone: () => done = true,
    );
  }

  final FakeGeolocator geo;
  final GeolocatorFixSource source;
  final fixes = <NavFix>[];
  final errors = <Object>[];
  bool done = false;
}

void main() {
  group('permission', () {
    for (final granted in [
      LocationPermission.whileInUse,
      LocationPermission.always,
    ]) {
      test('$granted: no request, the position stream starts', () async {
        final h = Harness(FakeGeolocator()..permission = granted);
        h.source.start();
        await pumpEventQueue();
        expect(h.geo.permissionRequests, 0);
        expect(h.geo.settings, hasLength(1));
        h.geo.positions!.add(position());
        await pumpEventQueue();
        expect(h.fixes, hasLength(1));
        expect(h.errors, isEmpty);
        h.source.dispose();
      });
    }

    test(
      'denied, then granted on request: the position stream starts',
      () async {
        final h = Harness(
          FakeGeolocator()
            ..permission = LocationPermission.denied
            ..afterRequest = LocationPermission.whileInUse,
        );
        h.source.start();
        await pumpEventQueue();
        expect(h.geo.permissionRequests, 1);
        expect(h.geo.settings, hasLength(1));
        expect(h.errors, isEmpty);
        h.source.dispose();
      },
    );

    test(
      'denied on request: an error on fixes, start does not throw',
      () async {
        final h = Harness(
          FakeGeolocator()
            ..permission = LocationPermission.denied
            ..afterRequest = LocationPermission.denied,
        );
        h.source.start();
        expect(h.source.isRunning, isTrue);
        await pumpEventQueue();
        expect(h.geo.permissionRequests, 1);
        expect(h.errors.single, isA<PermissionDeniedException>());
        expect(h.errors.single.toString(), contains('denied'));
        expect(h.geo.settings, isEmpty);
        // Stays running until stopped; stop and start retries.
        expect(h.source.isRunning, isTrue);
        h.source.stop();
        expect(h.source.isRunning, isFalse);
        h.geo.afterRequest = LocationPermission.whileInUse;
        h.source.start();
        await pumpEventQueue();
        expect(h.geo.settings, hasLength(1));
        h.source.dispose();
      },
    );

    test('denied forever: an error on fixes without asking', () async {
      final h = Harness(
        FakeGeolocator()..permission = LocationPermission.deniedForever,
      );
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.permissionRequests, 0);
      expect(h.errors.single, isA<PermissionDeniedException>());
      expect(h.errors.single.toString(), contains('forever'));
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });

    test('denied forever on request: an error on fixes', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..afterRequest = LocationPermission.deniedForever,
      );
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.permissionRequests, 1);
      expect(h.errors.single, isA<PermissionDeniedException>());
      expect(h.errors.single.toString(), contains('forever'));
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });
  });

  group('location services', () {
    test('off: an error on fixes, no permission asked', () async {
      final h = Harness(FakeGeolocator()..servicesOn = false);
      h.source.start();
      await pumpEventQueue();
      expect(h.errors.single, isA<LocationServiceDisabledException>());
      expect(h.geo.permissionChecks, 0);
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });

    test('a failing check becomes an error on fixes', () async {
      final h = Harness(FakeGeolocator()..servicesError = StateError('boom'));
      h.source.start();
      await pumpEventQueue();
      expect(h.errors.single, isA<StateError>());
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });
  });

  group('stop during the permission request', () {
    test('granted afterwards: no position stream, no error', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.pendingRequests, hasLength(1));
      h.source.stop();
      h.geo.pendingRequests.single.complete(LocationPermission.whileInUse);
      await pumpEventQueue();
      expect(h.geo.settings, isEmpty);
      expect(h.errors, isEmpty);
      expect(h.source.isRunning, isFalse);
      h.source.dispose();
    });

    test('denied afterwards: no error', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingRequests.single.complete(LocationPermission.denied);
      await pumpEventQueue();
      expect(h.errors, isEmpty);
      h.source.dispose();
    });

    test('a request failing after stop: no error', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingRequests.single.completeError(StateError('late'));
      await pumpEventQueue();
      expect(h.errors, isEmpty);
      h.source.dispose();
    });

    test('a request failing after dispose: nothing after close', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.source.dispose();
      h.geo.pendingRequests.single.completeError(StateError('late'));
      await pumpEventQueue();
      expect(h.errors, isEmpty);
      expect(h.done, isTrue);
    });

    test(
      'restarted while asking, then granted: the stream starts, no error',
      () async {
        final h = Harness(
          FakeGeolocator()
            ..permission = LocationPermission.denied
            ..holdRequests = true,
        );
        h.source.start();
        await pumpEventQueue();
        h.source.stop();
        h.source.start();
        await pumpEventQueue();
        expect(
          h.errors,
          isEmpty,
          reason: 'no second request while one is open',
        );
        expect(h.geo.pendingRequests, hasLength(1));
        h.geo.pendingRequests.single.complete(LocationPermission.whileInUse);
        await pumpEventQueue();
        expect(h.geo.settings, hasLength(1));
        expect(h.errors, isEmpty);
        expect(h.source.isRunning, isTrue);
        h.geo.positions!.add(position());
        await pumpEventQueue();
        expect(h.fixes, hasLength(1));
        h.source.dispose();
      },
    );

    test('restarted while asking, then denied: one error', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.source.start();
      await pumpEventQueue();
      h.geo.pendingRequests.single.complete(LocationPermission.denied);
      await pumpEventQueue();
      expect(h.errors.single, isA<PermissionDeniedException>());
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });

    test(
      'a finished request is not reused: a later start asks again',
      () async {
        final h = Harness(
          FakeGeolocator()
            ..permission = LocationPermission.denied
            ..holdRequests = true,
        );
        h.source.start();
        await pumpEventQueue();
        h.geo.pendingRequests.single.complete(LocationPermission.denied);
        await pumpEventQueue();
        h.source.stop();
        h.source.start();
        await pumpEventQueue();
        expect(h.geo.permissionRequests, 2);
        h.geo.pendingRequests.last.complete(LocationPermission.whileInUse);
        await pumpEventQueue();
        expect(h.geo.settings, hasLength(1));
        expect(h.errors, hasLength(1), reason: 'only the first denial');
        h.source.dispose();
      },
    );

    test('a failed request is not reused either', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.geo.pendingRequests.single.completeError(StateError('platform'));
      await pumpEventQueue();
      expect(h.errors.single, isA<StateError>());
      h.source.stop();
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.permissionRequests, 2);
      h.source.dispose();
    });

    test('stop during the services check: no permission check', () async {
      final h = Harness(FakeGeolocator()..holdServices = true);
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingServices.single.complete(true);
      await pumpEventQueue();
      expect(h.geo.permissionChecks, 0);
      expect(h.geo.settings, isEmpty);
      expect(h.errors, isEmpty);
      h.source.dispose();
    });

    test('stop during the services check, services off: no error', () async {
      final h = Harness(FakeGeolocator()..holdServices = true);
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingServices.single.complete(false);
      await pumpEventQueue();
      expect(h.errors, isEmpty);
      h.source.dispose();
    });

    test('stop during the permission check: no request, no stream', () async {
      final h = Harness(FakeGeolocator()..holdChecks = true);
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingChecks.single.complete(LocationPermission.denied);
      await pumpEventQueue();
      expect(h.geo.permissionRequests, 0);
      expect(h.geo.settings, isEmpty);
      expect(h.errors, isEmpty);
      h.source.dispose();
    });

    test('stop during the permission check, granted: no stream', () async {
      final h = Harness(FakeGeolocator()..holdChecks = true);
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      h.geo.pendingChecks.single.complete(LocationPermission.whileInUse);
      await pumpEventQueue();
      expect(h.geo.settings, isEmpty);
      h.source.dispose();
    });

    test('disposed while asking: nothing after close', () async {
      final h = Harness(
        FakeGeolocator()
          ..permission = LocationPermission.denied
          ..holdRequests = true,
      );
      h.source.start();
      await pumpEventQueue();
      h.source.dispose();
      h.geo.pendingRequests.single.complete(LocationPermission.denied);
      await pumpEventQueue();
      expect(h.errors, isEmpty);
      expect(h.geo.settings, isEmpty);
      expect(h.done, isTrue);
    });
  });

  group('settings', () {
    test('default: bestForNavigation, every metre', () async {
      final h = Harness(FakeGeolocator());
      expect(
        h.source.locationSettings,
        same(GeolocatorFixSource.defaultLocationSettings),
      );
      expect(
        GeolocatorFixSource.defaultLocationSettings.accuracy,
        LocationAccuracy.bestForNavigation,
      );
      expect(GeolocatorFixSource.defaultLocationSettings.distanceFilter, 0);
      h.source.start();
      await pumpEventQueue();
      expect(
        h.geo.settings.single,
        same(GeolocatorFixSource.defaultLocationSettings),
      );
      h.source.dispose();
    });

    test('custom settings reach the position stream', () async {
      const custom = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
      final h = Harness(FakeGeolocator(), settings: custom);
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.settings.single, same(custom));
      h.source.dispose();
    });
  });

  group('positions become fixes', () {
    Future<NavFix> fixOf(Position p) async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      await pumpEventQueue();
      h.geo.positions!.add(p);
      await pumpEventQueue();
      h.source.dispose();
      return h.fixes.single;
    }

    test('position and accuracy', () async {
      final fix = await fixOf(
        position(latitude: 21.03, longitude: 105.85, accuracy: 7.5),
      );
      expect(fix.position, const GeoPoint(21.03, 105.85));
      expect(fix.accuracy, 7.5);
    });

    test('a measured speed is kept', () async {
      expect((await fixOf(position(speed: 12.5))).speed, 12.5);
      expect(
        (await fixOf(position(speed: 0, speedAccuracy: 0.3))).speed,
        0,
        reason: 'a measured standstill',
      );
      expect(
        (await fixOf(position(speed: 4, speedAccuracy: 0))).speed,
        4,
        reason: 'no accuracy, but a speed',
      );
    });

    test('speed < 0 is unknown', () async {
      expect((await fixOf(position(speed: -1))).speed, isNull);
    });

    test('speed 0 with speedAccuracy 0 is unknown', () async {
      expect((await fixOf(position(speed: 0, speedAccuracy: 0))).speed, isNull);
    });

    test('heading is kept from 1 m/s', () async {
      expect((await fixOf(position(speed: 1, heading: 45))).heading, 45);
      expect((await fixOf(position(speed: 20, heading: 0))).heading, 0);
    });

    test('heading is null below 1 m/s', () async {
      expect((await fixOf(position(speed: 0.99, heading: 45))).heading, isNull);
      expect(
        (await fixOf(
          position(speed: 0, speedAccuracy: 0.3, heading: 45),
        )).heading,
        isNull,
      );
    });

    test('heading is null when below 0', () async {
      expect((await fixOf(position(speed: 10, heading: -1))).heading, isNull);
    });

    test('heading is null when the speed is unknown', () async {
      expect((await fixOf(position(speed: -1, heading: 45))).heading, isNull);
      expect(
        (await fixOf(
          position(speed: 0, speedAccuracy: 0, heading: 45),
        )).heading,
        isNull,
      );
    });
  });

  group('platform flags', () {
    Future<NavFix> fixOf(Position p) async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      await pumpEventQueue();
      h.geo.positions!.add(p);
      await pumpEventQueue();
      h.source.dispose();
      return h.fixes.single;
    }

    test('no hasSpeed: speed and heading are unknown', () async {
      final fix = await fixOf(
        position(speed: 10, speedAccuracy: 0.5, heading: 90, hasSpeed: false),
      );
      expect(fix.speed, isNull);
      expect(fix.heading, isNull);
    });

    test('hasSpeed does not override the in-band rules', () async {
      expect((await fixOf(position(speed: -1))).speed, isNull);
      expect((await fixOf(position(speed: 0, speedAccuracy: 0))).speed, isNull);
    });

    test('no hasHeading: heading is unknown, speed is kept', () async {
      final fix = await fixOf(position(speed: 10, hasHeading: false));
      expect(fix.speed, 10);
      expect(fix.heading, isNull);
    });
  });

  group('web', () {
    Future<NavFix> webFixOf(Position p) async {
      final h = Harness(FakeGeolocator(), isWeb: true);
      h.source.start();
      await pumpEventQueue();
      h.geo.positions!.add(p);
      await pumpEventQueue();
      h.source.dispose();
      return h.fixes.single;
    }

    test('the missing flags are ignored: speed and heading are kept', () async {
      final fix = await webFixOf(
        position(speed: 10, heading: 90, hasSpeed: false, hasHeading: false),
      );
      expect(fix.speed, 10);
      expect(fix.heading, 90);
    });

    test('the value rules still apply', () async {
      expect(
        (await webFixOf(
          position(speed: 0, speedAccuracy: 0, hasSpeed: false),
        )).speed,
        isNull,
      );
      expect(
        (await webFixOf(position(speed: -1, hasSpeed: false))).speed,
        isNull,
      );
      expect(
        (await webFixOf(
          position(speed: 10, heading: -1, hasHeading: false),
        )).heading,
        isNull,
      );
      expect(
        (await webFixOf(
          position(speed: 0.5, heading: 90, hasHeading: false),
        )).heading,
        isNull,
      );
    });

    test('isWeb defaults to false off the web', () async {
      final geo = FakeGeolocator();
      final source = GeolocatorFixSource(geolocator: geo);
      final fixes = <NavFix>[];
      source.fixes.listen(fixes.add);
      source.start();
      await pumpEventQueue();
      geo.positions!.add(position(hasSpeed: false));
      await pumpEventQueue();
      expect(fixes.single.speed, isNull);
      source.dispose();
    });
  });

  group('invalid position', () {
    for (final (lat, lng) in [
      (double.nan, 106.70),
      (10.77, double.nan),
      (double.infinity, 106.70),
      (10.77, double.negativeInfinity),
    ]) {
      test('($lat, $lng) is dropped; the next fix comes through', () async {
        final h = Harness(FakeGeolocator());
        h.source.start();
        await pumpEventQueue();
        h.geo.positions!.add(position(latitude: lat, longitude: lng));
        h.geo.positions!.add(position());
        await pumpEventQueue();
        expect(h.fixes.single.position, const GeoPoint(10.77, 106.70));
        expect(h.errors, isEmpty);
        h.source.dispose();
      });
    }
  });

  group('non-finite values', () {
    Future<NavFix> fixOf(Position p) async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      await pumpEventQueue();
      h.geo.positions!.add(p);
      await pumpEventQueue();
      h.source.dispose();
      return h.fixes.single;
    }

    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('speed $value is unknown, and so is the heading', () async {
        final fix = await fixOf(position(speed: value, heading: 90));
        expect(fix.speed, isNull);
        expect(fix.heading, isNull);
      });

      test('heading $value is unknown', () async {
        final fix = await fixOf(position(speed: 10, heading: value));
        expect(fix.speed, 10);
        expect(fix.heading, isNull);
      });

      test('accuracy $value becomes infinite: FixFilter drops it', () async {
        final fix = await fixOf(position(accuracy: value));
        expect(fix.accuracy, double.infinity);
        expect(FixFilter().accept(fix), isFalse);
      });
    }

    test('a finite accuracy is kept as reported', () async {
      final fix = await fixOf(position(accuracy: 12));
      expect(fix.accuracy, 12);
      expect(FixFilter().accept(fix), isTrue);
    });
  });

  group('position stream end', () {
    test(
      'the platform closing the stream: an error, stopped, restartable',
      () async {
        final h = Harness(FakeGeolocator());
        h.source.start();
        await pumpEventQueue();
        await h.geo.positions!.close();
        await pumpEventQueue();
        expect(h.errors.single, isA<StateError>());
        expect(h.source.isRunning, isFalse);
        h.source.start();
        await pumpEventQueue();
        expect(h.geo.settings, hasLength(2));
        h.geo.positions!.add(position());
        await pumpEventQueue();
        expect(h.fixes, hasLength(1));
        h.source.dispose();
      },
    );
  });

  test('heading is wrapped into [0, 360)', () async {
    final h = Harness(FakeGeolocator());
    h.source.start();
    await pumpEventQueue();
    h.geo.positions!.add(position(heading: 360));
    h.geo.positions!.add(position(heading: 450.5));
    h.geo.positions!.add(position(heading: 359.5));
    await pumpEventQueue();
    expect(h.fixes.map((f) => f.heading), [0, 90.5, 359.5]);
    h.source.dispose();
  });

  group('clock', () {
    test('fix time is the arrival time on the injected clock', () async {
      var now = DateTime.utc(2026, 10, 10, 8);
      final h = Harness(FakeGeolocator(), clock: () => now);
      h.source.start();
      await pumpEventQueue();
      h.geo.positions!.add(position());
      now = now.add(const Duration(milliseconds: 1100));
      h.geo.positions!.add(position());
      await pumpEventQueue();
      expect(h.fixes.map((f) => f.time), [
        DateTime.utc(2026, 10, 10, 8),
        DateTime.utc(2026, 10, 10, 8, 0, 1, 100),
      ]);
      h.source.dispose();
    });

    test('defaults to DateTime.now, not the position timestamp', () async {
      final geo = FakeGeolocator();
      final source = GeolocatorFixSource(geolocator: geo);
      final fixes = <NavFix>[];
      source.fixes.listen(fixes.add);
      source.start();
      await pumpEventQueue();
      final before = DateTime.now();
      geo.positions!.add(position());
      await pumpEventQueue();
      final after = DateTime.now();
      expect(fixes.single.time.isBefore(before), isFalse);
      expect(fixes.single.time.isAfter(after), isFalse);
      source.dispose();
    });
  });

  test('position stream errors are forwarded; fixes keep coming', () async {
    final h = Harness(FakeGeolocator());
    h.source.start();
    await pumpEventQueue();
    h.geo.positions!.addError(const LocationServiceDisabledException());
    h.geo.positions!.add(position());
    await pumpEventQueue();
    expect(h.errors.single, isA<LocationServiceDisabledException>());
    expect(h.fixes, hasLength(1));
    h.source.dispose();
  });

  group('lifecycle', () {
    test('start while running does nothing', () async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.serviceChecks, 1);
      expect(h.geo.settings, hasLength(1));
      h.source.dispose();
    });

    test('stop cancels the position stream; start subscribes again', () async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      await pumpEventQueue();
      h.source.stop();
      expect(h.source.isRunning, isFalse);
      expect(h.geo.cancels, 1);
      h.source.start();
      await pumpEventQueue();
      expect(h.geo.settings, hasLength(2));
      h.geo.positions!.add(position());
      await pumpEventQueue();
      expect(h.fixes, hasLength(1));
      h.source.dispose();
    });

    test('dispose stops the source and closes fixes', () async {
      final h = Harness(FakeGeolocator());
      h.source.start();
      await pumpEventQueue();
      h.source.dispose();
      await pumpEventQueue();
      expect(h.source.isRunning, isFalse);
      expect(h.geo.cancels, 1);
      expect(h.done, isTrue);
    });

    test('start after dispose does nothing', () async {
      final h = Harness(FakeGeolocator());
      h.source.dispose();
      h.source.start();
      await pumpEventQueue();
      expect(h.source.isRunning, isFalse);
      expect(h.geo.serviceChecks, 0);
      expect(h.errors, isEmpty);
    });
  });
}
