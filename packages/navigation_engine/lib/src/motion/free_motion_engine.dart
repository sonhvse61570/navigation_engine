import 'dart:math' as math;

import '../fix/nav_fix.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import 'motion_engine.dart';
import 'motion_frame.dart';

/// Free driving (no route): the same predict-and-correct scheme in 2D. It
/// only smooths the GPS; it cannot remove the sideways noise a route removes.
class FreeMotionEngine implements MotionEngine {
  FreeMotionEngine({this.lead = 0.25});

  /// Extra seconds of prediction on top of the fix's own age.
  final double lead;

  GeoPoint? _pos;

  /// Velocity (m/s, east and north components) and its target.
  double _ve = 0, _vn = 0, _veT = 0, _vnT = 0;

  /// Position error still to absorb (m, east / north).
  double _ee = 0, _en = 0;
  double _bearing = 0;
  double _course = 0;
  DateTime? _lastFixAt;
  NavFix? _lastFix;

  /// Recent fixes for [_estimateSpeed].
  final _recent = <NavFix>[];

  /// How far back fixes without a speed are compared to estimate it.
  static const _speedWindow = Duration(seconds: 5);

  @override
  void onFix(NavFix fix, DateTime now) {
    final last = _lastFix;
    final measured = fix.speed;
    final estimate = _estimateSpeed(fix);
    var speed = measured != null ? math.max(0.0, measured) : estimate;
    // Heading straight from the GPS is noise below walking speed; fall back
    // to the direction of travel between fixes, then to the last course.
    final heading = fix.heading;
    if (heading != null && speed > 2) {
      _course = heading;
    } else if (last != null &&
        distanceBetween(last.position, fix.position) > 4) {
      _course = bearingBetween(last.position, fix.position);
    }
    _lastFix = fix;

    final age = (now.difference(fix.time).inMilliseconds / 1000).clamp(
      0.0,
      3.0,
    );
    var predicted = offsetPoint(fix.position, _course, speed * (age + lead));
    final pos = _pos;
    final jumped = pos == null || distanceBetween(pos, predicted) > 60;
    if (jumped && pos != null) {
      // An estimate across the jump is meaningless: measure again from here.
      _recent
        ..clear()
        ..add(fix);
      if (measured == null) {
        speed = math.sqrt(_ve * _ve + _vn * _vn);
        predicted = offsetPoint(fix.position, _course, speed * (age + lead));
      }
    }
    final rad = _course * math.pi / 180;
    _veT = speed * math.sin(rad);
    _vnT = speed * math.cos(rad);

    if (jumped) {
      _pos = predicted;
      _ee = _en = 0;
      _ve = _veT;
      _vn = _vnT;
      _bearing = _course;
    } else {
      final d = distanceBetween(pos, predicted);
      final b = bearingBetween(pos, predicted) * math.pi / 180;
      _ee = d * math.sin(b);
      _en = d * math.cos(b);
      if (speed < 0.8 && d < 8) _ee = _en = 0;
    }
    _lastFixAt = now;
  }

  /// Records [fix] and returns the speed it implies, for fixes without
  /// one: the straight-line distance from the fix about [_speedWindow]
  /// earlier, over the time between them (consecutive fixes are too noisy).
  /// Falls back to the current velocity when there is no earlier fix.
  double _estimateSpeed(NavFix fix) {
    final recent = _recent;
    // After a gap of more than two windows the old fixes describe another
    // drive (a stop, a tunnel): measure afresh.
    if (recent.isNotEmpty &&
        fix.time.difference(recent.last.time) > _speedWindow * 2) {
      recent.clear();
    }
    while (recent.length > 1 &&
        fix.time.difference(recent[1].time) >= _speedWindow) {
      recent.removeAt(0);
    }
    final base = recent.isEmpty ? null : recent.first;
    recent.add(fix);
    final dt = base == null
        ? 0.0
        : fix.time.difference(base.time).inMicroseconds / 1e6;
    if (base == null || dt <= 0) return math.sqrt(_ve * _ve + _vn * _vn);
    return distanceBetween(base.position, fix.position) / dt;
  }

  @override
  MotionFrame? tick(double dt, DateTime now) {
    final pos = _pos;
    if (pos == null || dt <= 0) return null;
    final stale = now.difference(_lastFixAt!).inMilliseconds / 1000;
    final veT = stale > staleAfterSeconds ? 0.0 : _veT;
    final vnT = stale > staleAfterSeconds ? 0.0 : _vnT;

    final a = smoothingAlpha(dt, 0.7);
    _ve += (veT - _ve) * a;
    _vn += (vnT - _vn) * a;
    final c = smoothingAlpha(dt, 0.5);
    final ce = _ee * c, cn = _en * c;
    _ee -= ce;
    _en -= cn;
    final de = _ve * dt + ce, dn = _vn * dt + cn;
    final step = math.sqrt(de * de + dn * dn);
    final next = step == 0 ? pos : offsetPoint(pos, bearingOf(de, dn), step);
    _pos = next;

    final speed = math.sqrt(_ve * _ve + _vn * _vn);
    if (speed > 1.5) {
      _bearing =
          (_bearing +
              angleDelta(_bearing, _course) * smoothingAlpha(dt, 0.35)) %
          360;
    }
    return MotionFrame(position: next, bearing: _bearing, speed: speed);
  }

  @override
  void reset() {
    _pos = null;
    _ve = _vn = _veT = _vnT = _ee = _en = 0;
    _lastFixAt = null;
    _lastFix = null;
    _recent.clear();
  }
}
