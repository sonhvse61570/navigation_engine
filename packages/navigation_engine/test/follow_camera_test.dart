import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  MotionFrame frame(double speed, {double bearing = 42}) => MotionFrame(
    position: const GeoPoint(10.77, 106.69),
    bearing: bearing,
    speed: speed,
  );

  test('zoomFor: close in when slow, wider when fast, clamped', () {
    final c = FollowCamera();
    expect(c.zoomFor(0), 18.7);
    expect(c.zoomFor(4), 18.7);
    expect(c.zoomFor(13), closeTo(17.9, 1e-9));
    expect(c.zoomFor(22), 17.1);
    expect(c.zoomFor(40), 17.1);
  });

  test('first update jumps to the target, then follows smoothly', () {
    final c = FollowCamera();
    final first = c.update(frame(0), 1 / 60);
    expect(first.zoom, 18.7);
    expect(first.bearing, 42);
    expect(first.tilt, 35);
    expect(first.position, const GeoPoint(10.77, 106.69));
    final next = c.update(frame(22), 1 / 60);
    expect(next.zoom, lessThan(18.7));
    expect(next.zoom, greaterThan(18.6));
    for (var i = 0; i < 60 * 10; i++) {
      c.update(frame(22), 1 / 60);
    }
    expect(c.update(frame(22), 1 / 60).zoom, closeTo(17.1, 0.01));
  });

  test('smoothing does not depend on the frame rate', () {
    final a = FollowCamera()..update(frame(0), 0);
    final b = FollowCamera()..update(frame(0), 0);
    late CameraTarget za, zb;
    for (var i = 0; i < 60; i++) {
      za = a.update(frame(22), 1 / 60);
    }
    for (var i = 0; i < 120; i++) {
      zb = b.update(frame(22), 1 / 120);
    }
    expect(za.zoom, closeTo(zb.zoom, 1e-9));
  });

  test('reset makes the next update jump again', () {
    final c = FollowCamera()..update(frame(0), 1 / 60);
    c.reset();
    expect(c.update(frame(22), 1 / 60).zoom, 17.1);
  });

  test('north-up returns bearing 0 and no tilt', () {
    final cam = FollowCamera()..headingUp = false;
    final t = cam.update(frame(10, bearing: 135), 0.1);
    expect(t.bearing, 0);
    expect(t.tilt, 0);
  });

  test('heading-up follows the frame bearing (default)', () {
    final t = FollowCamera().update(frame(10, bearing: 135), 0.1);
    expect(t.bearing, closeTo(135, 1e-9));
  });

  test('north-up keeps the position and the speed-based zoom', () {
    final cam = FollowCamera()..headingUp = false;
    final t = cam.update(frame(0, bearing: 135), 1 / 60);
    expect(t.position, const GeoPoint(10.77, 106.69));
    expect(t.zoom, 18.7);
    final up = FollowCamera().update(frame(0, bearing: 135), 1 / 60);
    expect(t.zoom, up.zoom);
    expect(t.position, up.position);
  });

  test('toggling headingUp keeps the zoom smoothing (no jump)', () {
    final toggled = FollowCamera()..update(frame(0), 1 / 60);
    final steady = FollowCamera()..update(frame(0), 1 / 60);
    for (var i = 0; i < 30; i++) {
      toggled.update(frame(22), 1 / 60);
      steady.update(frame(22), 1 / 60);
    }
    toggled.headingUp = false;
    final a = toggled.update(frame(22), 1 / 60);
    final b = steady.update(frame(22), 1 / 60);
    expect(a.zoom, closeTo(b.zoom, 1e-9));
    expect(a.zoom, greaterThan(17.2));
    toggled.headingUp = true;
    expect(
      toggled.update(frame(22), 1 / 60).zoom,
      closeTo(steady.update(frame(22), 1 / 60).zoom, 1e-9),
    );
  });

  test(
    'headingUpChanges emits each change of headingUp, not a repeat',
    () async {
      final cam = FollowCamera();
      final seen = <bool>[];
      final sub = cam.headingUpChanges.listen(seen.add);
      cam
        ..headingUp = false
        ..headingUp = false
        ..headingUp = true;
      await Future<void>.delayed(Duration.zero);
      expect(seen, [false, true]);
      await sub.cancel();
    },
  );

  test(
    'dispose ends headingUpChanges; a later change does not throw',
    () async {
      final cam = FollowCamera();
      var done = false;
      cam.headingUpChanges.listen(null, onDone: () => done = true);
      cam.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      cam.headingUp = false;
      expect(cam.headingUp, isFalse);
    },
  );
}
