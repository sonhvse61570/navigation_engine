import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  MotionFrame frame(double speed) => MotionFrame(
    position: const GeoPoint(10.77, 106.69),
    bearing: 42,
    speed: speed,
  );

  MotionFrame frameAt({required double bearing, required double speed}) =>
      MotionFrame(
        position: const GeoPoint(10.77, 106.69),
        bearing: bearing,
        speed: speed,
      );

  test('zoomFor: close in when slow, wider when fast, clamped', () {
    final c = FollowCamera();
    expect(c.zoomFor(0), 18.2);
    expect(c.zoomFor(4), 18.2);
    expect(c.zoomFor(13), closeTo(17.4, 1e-9));
    expect(c.zoomFor(22), 16.6);
    expect(c.zoomFor(40), 16.6);
  });

  test('first update jumps to the target, then follows smoothly', () {
    final c = FollowCamera();
    final first = c.update(frame(0), 1 / 60);
    expect(first.zoom, 18.2);
    expect(first.bearing, 42);
    expect(first.tilt, 50);
    expect(first.position, const GeoPoint(10.77, 106.69));
    final next = c.update(frame(22), 1 / 60);
    expect(next.zoom, lessThan(18.2));
    expect(next.zoom, greaterThan(18.1));
    for (var i = 0; i < 60 * 10; i++) {
      c.update(frame(22), 1 / 60);
    }
    expect(c.update(frame(22), 1 / 60).zoom, closeTo(16.6, 0.01));
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
    expect(c.update(frame(22), 1 / 60).zoom, 16.6);
  });

  test('north-up returns bearing 0 and no tilt', () {
    final cam = FollowCamera()..headingUp = false;
    final t = cam.update(frameAt(bearing: 135, speed: 10), 0.1);
    expect(t.bearing, 0);
    expect(t.tilt, 0);
  });

  test('heading-up follows the frame bearing (default)', () {
    final t = FollowCamera().update(frameAt(bearing: 135, speed: 10), 0.1);
    expect(t.bearing, closeTo(135, 1e-9));
  });
}
