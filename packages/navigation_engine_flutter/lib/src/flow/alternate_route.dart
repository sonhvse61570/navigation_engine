import 'package:flutter/foundation.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// A route the driver could switch to while navigating, beside the current
/// one.
@immutable
final class AlternateRoute {
  /// Creates an alternate [route] that leaves the current route [divergence]
  /// metres along itself and arrives [timeDelta] later (negative: sooner).
  const AlternateRoute({
    required this.route,
    required this.timeDelta,
    required this.divergence,
  });

  /// The alternate route.
  final NavRoute route;

  /// The alternate's remaining duration minus the current route's, from the
  /// routes' own durations: negative when the alternate is faster.
  final Duration timeDelta;

  /// Metres along [route] where it leaves the current route.
  final double divergence;

  /// [timeDelta] rounded to whole minutes, as a label shows it.
  int get minutesDelta => (timeDelta.inSeconds / 60).round();

  @override
  String toString() =>
      'AlternateRoute(${route.name}, $timeDelta, at '
      '${divergence.toStringAsFixed(0)} m)';
}

/// Where [alternate] first leaves [current] by more than [threshold] metres,
/// sampling [alternate] every [step] metres from [from] metres along it:
/// `alternate` is that sample's distance along [alternate], and `current`
/// is the distance along [current] of the last sample still within
/// [threshold]. `shift` maps the shared stretch from one route to the other:
/// a place `x` metres along [current] is `x + shift` metres along
/// [alternate], measured at the first sample (zero for two routes from the
/// same origin). Null when [alternate] never leaves [current] (a copy or a
/// prefix of it).
///
/// Each sample is snapped within a window that moves with the previous
/// match, so a long shared stretch costs time in proportion to its length,
/// not to its length times the route's points. Only the first sample, and a
/// sample farther than [threshold] from the window, are snapped over the
/// whole of [current]: an alternate may start anywhere along it, or rejoin
/// it further on (past a spur it skips, for example). So `current` follows
/// the windowed match while the alternate stays near it. A whole-route match
/// behind the window is never taken: on a route that passes the same place
/// twice (a U-turn, a loop) it is an earlier pass, which the alternate has
/// left. A match ahead of the window is taken, as a rejoin, even when it is
/// a later pass: an alternate that turns off across the route's own return
/// leg is measured as leaving from that leg.
({double current, double alternate, double shift})? routeDivergence(
  NavRoute current,
  NavRoute alternate, {
  double threshold = 30,
  double step = 10,
  double from = 0,
}) {
  double? lastOn;
  double? shift;
  for (var d = from; ; d += step) {
    final at = d < alternate.length ? d : alternate.length;
    final p = alternate.pointAt(at);
    final near = lastOn;
    var snap = near == null
        ? current.snap(p)
        : current.snap(
            p,
            near: near,
            behind: threshold,
            ahead: step + threshold + _windowSlack,
          );
    if (near != null && snap.offset > threshold) {
      final whole = current.snap(p);
      if (whole.distance > near) snap = whole;
    }
    if (snap.offset > threshold) {
      return (current: lastOn ?? 0.0, alternate: at, shift: shift ?? 0.0);
    }
    shift ??= at - snap.distance;
    lastOn = snap.distance;
    if (at >= alternate.length) return null;
  }
}

/// Extra metres ahead of the expected match that [routeDivergence]'s window
/// covers, for an alternate drawn with more or fewer bends than the route.
const double _windowSlack = 50;
