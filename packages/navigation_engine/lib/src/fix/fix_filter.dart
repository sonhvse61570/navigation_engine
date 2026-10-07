import '../geo/geo_math.dart';
import 'nav_fix.dart';

/// Drops fixes that would visibly yank the vehicle: poor accuracy, and jumps
/// that imply an impossible speed (multipath in street canyons, cell / Wi-Fi
/// fallback positions).
class FixFilter {
  FixFilter({this.maxAccuracy = 30, this.maxSpeed = 55});

  /// Metres; fixes with a larger accuracy radius are dropped.
  final double maxAccuracy;

  /// Metres per second (~200 km/h).
  final double maxSpeed;

  NavFix? _last;

  /// Returns whether [fix] should be used (and remembers it if so).
  bool accept(NavFix fix) {
    if (fix.accuracy > maxAccuracy) return false;
    final last = _last;
    if (last != null) {
      final dt = fix.time.difference(last.time).inMilliseconds / 1000;
      if (dt <= 0) return false;
      // The slack term absorbs ordinary noise over short intervals.
      final allowed = maxSpeed * dt + fix.accuracy + last.accuracy;
      if (distanceBetween(last.position, fix.position) > allowed) return false;
    }
    _last = fix;
    return true;
  }

  void reset() => _last = null;
}
