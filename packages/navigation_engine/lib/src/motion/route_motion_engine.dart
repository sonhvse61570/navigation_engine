import 'dart:math' as math;

import '../fix/nav_fix.dart';
import '../geo/geo_math.dart';
import '../route/nav_route.dart';
import '../route/route_snap.dart';
import 'motion_engine.dart';
import 'motion_frame.dart';

/// Follows a [NavRoute]: positions are reduced to a distance along the route,
/// so the vehicle can only move along the road, never sideways, and corners
/// are driven along the polyline instead of being cut.
class RouteMotionEngine implements MotionEngine {
  RouteMotionEngine(
    this.route, {
    this.lead = 0.25,
    this.offRouteDistance = 30,
    this.offRouteAfter = const Duration(seconds: 3),
    this.maxCorrection = 5,
  });

  final NavRoute route;

  /// Metres per second the vehicle may speed up or slow down by to catch up
  /// with the fixes.
  final double maxCorrection;

  /// Extra seconds of prediction on top of the fix's own age, for the
  /// latency of the camera update itself (platform channel + render).
  final double lead;

  /// Metres away from the route that count as "off route"...
  final double offRouteDistance;

  /// ...when it lasts at least this long (hysteresis against noise).
  final Duration offRouteAfter;

  /// How far back fixes without a speed are compared to estimate it.
  static const _speedWindow = Duration(seconds: 5);

  double? _s;
  double _v = 0;
  double _vTarget = 0;
  double _err = 0;
  double _bearing = 0;
  double? _lastSnapS;
  DateTime? _lastSnapAt;
  DateTime? _lastFixAt;
  DateTime? _offSince;
  bool _offRoute = false;
  RouteSnap? _lastSnap;

  /// Recent fixes (time, distance along the route) for [_estimateSpeed].
  final _recent = <(DateTime, double)>[];

  /// The last fix projected onto the route (for debugging overlays).
  RouteSnap? get lastSnap => _lastSnap;

  @override
  void onFix(NavFix fix, DateTime now) {
    final measured = fix.speed;
    // Search only where the vehicle can be: from a bit behind the last snap
    // to as far as it could have driven since, plus margin. A fixed long
    // window reaches across a U-turn (or a loop) onto the way back, which is
    // often just one carriageway away.
    final last = _lastSnapS;
    final lastAt = _lastSnapAt;
    final windowSpeed = math.max(0.0, measured ?? _v);
    var snap = last == null || lastAt == null
        ? route.snap(fix.position)
        : route.snap(
            fix.position,
            near: last,
            behind: 30,
            ahead:
                40 +
                math.max(windowSpeed, 3) *
                    1.5 *
                    (fix.time.difference(lastAt).inMilliseconds / 1000).clamp(
                      1.0,
                      10.0,
                    ),
          );
    if (last != null && snap.offset > offRouteDistance) {
      // Rejoined the route somewhere outside the window?
      final global = route.snap(fix.position);
      if (global.offset < offRouteDistance / 2) snap = global;
    }
    _lastSnap = snap;
    _lastSnapS = snap.distance;
    _lastSnapAt = fix.time;

    final age = (now.difference(fix.time).inMilliseconds / 1000).clamp(
      0.0,
      3.0,
    );
    final estimate = _estimateSpeed(snap.distance, fix.time);
    var speed = measured != null ? math.max(0.0, measured) : estimate;
    final s = _s;
    if (measured != null && s != null) {
      speed = _checkMeasured(speed, estimate, snap.distance, age, s);
    }
    var predicted = math.min(
      route.length,
      snap.distance + speed * (age + lead),
    );
    final jumped = s == null || (predicted - s).abs() > 60;
    if (jumped && s != null) {
      // An estimate across the jump is meaningless: measure again from here.
      _recent
        ..clear()
        ..add((fix.time, snap.distance));
      if (measured == null) {
        speed = _v;
        predicted = math.min(
          route.length,
          snap.distance + speed * (age + lead),
        );
      }
    }

    // Driving across the route's direction is a stronger sign than distance
    // alone: it flags a wrong turn while the vehicle is still close to the
    // route. (GPS heading is noise when slow, hence the speed gate.)
    final heading = fix.heading;
    final crossing =
        speed > 3 &&
        heading != null &&
        snap.offset > offRouteDistance / 2 &&
        angleDelta(heading, route.bearingAt(snap.distance)).abs() > 50;
    if (snap.offset > offRouteDistance || crossing) {
      _offSince ??= fix.time;
      _offRoute = fix.time.difference(_offSince!) >= offRouteAfter;
    } else {
      _offSince = null;
      _offRoute = false;
    }

    if (jumped) {
      _s = predicted;
      _err = 0;
      _v = speed;
      _bearing = route.bearingAt(predicted);
    } else {
      _err = predicted - s;
      // Standing still: GPS noise slides the snap back and forth along the
      // road by a few metres; hold the vehicle instead of creeping.
      if (speed < 0.8 && _err.abs() < 8) _err = 0;
    }
    _vTarget = speed;
    _lastFixAt = now;
  }

  /// Whether the fixes' own speed has been found not to match how far they
  /// move (see [_checkMeasured]).
  bool _measuredUnreliable = false;

  /// Returns the speed to use for a fix that reports [measured].
  ///
  /// A receiver's speed is normally better than one estimated from
  /// positions, but mock-location apps often report 0 (Android fills in 0
  /// when a location has none) or a speed that does not match how far the
  /// fixes move. Trusting it leaves the vehicle ever further from the fixes,
  /// [maxCorrection] cannot close the gap, and it ends in a jump. So when
  /// the vehicle has drifted more than [_driftLimit] metres from the fixes,
  /// in the direction the [estimate] disagrees with [measured], the engine
  /// uses the estimate instead, until the two agree again while moving. A
  /// real receiver
  /// stays within the limit (braking for a red light included), so it is
  /// never second-guessed.
  double _checkMeasured(
    double measured,
    double estimate,
    double snapDistance,
    double age,
    double s,
  ) {
    final agree = (estimate - measured).abs() <= math.max(1.5, 0.25 * estimate);
    if (agree) {
      // Agreeing at a standstill says nothing (a source stuck at 0 agrees
      // at every red light): only agreement while moving restores trust.
      if (estimate > 3) _measuredUnreliable = false;
    } else {
      final drift = snapDistance + measured * (age + lead) - s;
      if (drift.abs() > _driftLimit && (drift > 0) == (estimate > measured)) {
        _measuredUnreliable = true;
      }
    }
    return _measuredUnreliable ? estimate : measured;
  }

  /// Metres between the vehicle and the fixes beyond which a disagreeing
  /// measured speed is no longer trusted.
  static const _driftLimit = 15.0;

  /// Records the fix and returns the speed it implies, for fixes without
  /// one: the distance driven along the route since the fix about
  /// [_speedWindow] earlier, over the time between them. Two consecutive
  /// fixes are too close together: their noise alone makes the estimate
  /// swing by several metres per second. Falls back to the current velocity
  /// when there is no earlier fix.
  double _estimateSpeed(double distance, DateTime time) {
    final recent = _recent;
    // After a gap of more than two windows the old fixes describe another
    // drive (a stop, a tunnel): measure afresh.
    if (recent.isNotEmpty &&
        time.difference(recent.last.$1) > _speedWindow * 2) {
      recent.clear();
    }
    // Keep the newest fix that is at least [_speedWindow] old as the base.
    while (recent.length > 1 && time.difference(recent[1].$1) >= _speedWindow) {
      recent.removeAt(0);
    }
    final base = recent.isEmpty ? null : recent.first;
    recent.add((time, distance));
    if (base == null) return _v;
    final dt = time.difference(base.$1).inMicroseconds / 1e6;
    if (dt <= 0) return _v;
    return math.max(0.0, (distance - base.$2) / dt);
  }

  @override
  MotionFrame? tick(double dt, DateTime now) {
    final s = _s;
    if (s == null || dt <= 0) return null;
    final stale = now.difference(_lastFixAt!).inMilliseconds / 1000;
    final vTarget = stale > staleAfterSeconds ? 0.0 : _vTarget;

    _v += (vTarget - _v) * smoothingAlpha(dt, 0.7);
    // Absorb the prediction error quickly but never faster than
    // [maxCorrection], or a late fix makes the vehicle visibly surge.
    final corr = (_err * smoothingAlpha(dt, 0.5)).clamp(
      -maxCorrection * dt,
      maxCorrection * dt,
    );
    _err -= corr;
    // Never drive backwards: a fix behind the vehicle only slows it down.
    final next = math.min(route.length, s + math.max(0.0, _v * dt + corr));
    _s = next;

    final target = route.bearingAt(next);
    _bearing =
        (_bearing + angleDelta(_bearing, target) * smoothingAlpha(dt, 0.25)) %
        360;

    return MotionFrame(
      position: route.pointAt(next),
      bearing: _bearing,
      speed: _v,
      routeDistance: next,
      offRoute: _offRoute,
    );
  }

  @override
  void reset() {
    _s = null;
    _v = _vTarget = _err = 0;
    _lastSnapS = null;
    _lastSnapAt = null;
    _lastFixAt = null;
    _offSince = null;
    _offRoute = false;
    _lastSnap = null;
    _measuredUnreliable = false;
    _recent.clear();
  }
}
