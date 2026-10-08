import '../motion/motion_engine.dart';
import '../motion/motion_frame.dart';
import 'camera_target.dart';

/// A camera that follows the vehicle: centred on it, rotated to its heading,
/// zoomed in when slow (junctions) and out when fast (more road ahead), with
/// the zoom smoothed so speed changes do not make it pump.
class FollowCamera {
  FollowCamera({
    this.zoomSlow = 18.2,
    this.zoomFast = 16.6,
    this.slowSpeed = 4,
    this.fastSpeed = 22,
    this.tilt = 50,
    this.zoomTau = 1.5,
  });

  /// Zoom at or below [slowSpeed] (m/s).
  final double zoomSlow;

  /// Zoom at or above [fastSpeed] (m/s).
  final double zoomFast;
  final double slowSpeed;
  final double fastSpeed;
  final double tilt;

  /// Seconds; time constant of the zoom smoothing.
  final double zoomTau;

  /// Whether the map rotates to the vehicle's heading and tilts. When false
  /// the camera stays north-up and flat, and the zoom logic is unchanged.
  /// Changing it does not reset the zoom smoothing.
  bool headingUp = true;

  double? _zoom;

  /// The zoom the camera settles at for [speed] m/s.
  double zoomFor(double speed) {
    final t = ((speed - slowSpeed) / (fastSpeed - slowSpeed)).clamp(0.0, 1.0);
    return zoomSlow + (zoomFast - zoomSlow) * t;
  }

  /// The camera for [frame], [dt] seconds after the previous one. The first
  /// call (and the first after [reset]) jumps straight to the target zoom.
  CameraTarget update(MotionFrame frame, double dt) {
    final target = zoomFor(frame.speed);
    final z = _zoom;
    final zoom = z == null || dt <= 0
        ? (z ?? target)
        : z + (target - z) * smoothingAlpha(dt, zoomTau);
    _zoom = zoom;
    return CameraTarget(
      position: frame.position,
      bearing: headingUp ? frame.bearing : 0,
      zoom: zoom,
      tilt: headingUp ? tilt : 0,
    );
  }

  void reset() => _zoom = null;
}
