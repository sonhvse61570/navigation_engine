import 'dart:math' as math;

import '../fix/nav_fix.dart';
import 'motion_frame.dart';

/// Turns ~1 Hz GPS fixes into continuous display-rate motion.
///
/// The engines never interpolate *between* the last two fixes (which shows
/// every position one fix late, and makes the vehicle stop and restart when
/// a fix arrives a little late). They dead-reckon instead: the vehicle keeps
/// moving at the measured speed, and each new fix only nudges it, the
/// difference between the prediction and the fix being absorbed over the
/// next fraction of a second.
abstract interface class MotionEngine {
  /// Feeds a fix that passed the `FixFilter`. [now] is the arrival time.
  void onFix(NavFix fix, DateTime now);

  /// Advances by [dt] seconds; null until the first fix.
  MotionFrame? tick(double dt, DateTime now);

  void reset();
}

/// Frame-rate independent exponential smoothing factor for time constant
/// [tau] seconds.
double smoothingAlpha(double dt, double tau) => 1 - math.exp(-dt / tau);

/// Seconds of GPS silence after which the engines stop dead-reckoning.
const staleAfterSeconds = 2.5;
