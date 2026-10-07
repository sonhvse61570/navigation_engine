import 'dart:math' as math;

import '../fix/nav_fix.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../route/maneuver.dart';
import '../route/nav_route.dart';

/// A car driving a [NavRoute] and the GPS fixes a phone in it would report:
/// about 1 Hz with jitter, delivered late, with noise, a slowly wandering
/// bias (multipath), noisy heading, and the occasional wild outlier.
///
/// Pure and deterministic for a given seed: [advance] moves the car,
/// [sample] reads a fix. `SimulatedFixSource` runs it in real time.
class GpsSimulator {
  GpsSimulator(
    NavRoute route, {
    int seed = 7,
    this.cruise = 11,
    this.noise = 3.5,
    this.outlierRate = 0.02,
    this.stops = const [],
    this.stopSeconds = 6,
  }) : _route = route,
       _rng = math.Random(seed);

  NavRoute _route;
  final math.Random _rng;

  /// Cruise speed in m/s (11 ≈ 40 km/h).
  double cruise;

  /// Standard deviation of the per-fix noise (m, per axis).
  final double noise;

  /// Probability that a fix is a wild outlier (~45 m off).
  final double outlierRate;

  /// Distances along the route (m) of red lights, where the car stops for
  /// [stopSeconds]. None by default; `sampleRouteRedLights` has two for
  /// `sampleRoute`.
  final List<double> stops;
  final double stopSeconds;

  /// Seconds of simulated time.
  double time = 0;

  /// Distance along the route (while on it).
  double distance = 0;
  double speed = 0;

  /// Set while the car has left the route (see [driveOffRoute]).
  GeoPoint? _offPos;
  double _offBearing = 0;
  double _offDriven = 0;

  final _doneStops = <double>{};
  double _stoppedFor = 0;
  double _biasE = 0, _biasN = 0;

  /// Recent true positions, to report fixes that were measured earlier.
  final _history = <(double, GeoPoint, double)>[];

  NavRoute get route => _route;
  bool get isOffRoute => _offPos != null;
  bool get finished => !isOffRoute && distance >= _route.length;

  GeoPoint get position => _offPos ?? _route.pointAt(distance);
  double get heading => _offPos != null
      ? _offBearing
      : _route.bearingAt(distance, behind: 2, ahead: 3);

  /// Leaves the route: turns [turn] degrees into a side street (a wrong
  /// turn) and keeps going until a new route is set with [setRoute].
  ///
  /// The turn has to be clear: drifting off at a shallow angle keeps the car
  /// within a few metres of the route for a long time, which is (correctly)
  /// not treated as off route.
  void driveOffRoute({double turn = 70}) {
    if (isOffRoute) return;
    _offPos = position;
    _offBearing = (heading + turn) % 360;
    _offDriven = 0;
  }

  /// Continues on [route] from the point of it nearest to the car (a reroute
  /// starts where the car is, give or take the GPS error).
  void setRoute(NavRoute route) {
    final here = position;
    _route = route;
    distance = route.snap(here, near: 0, behind: 0, ahead: 150).distance;
    _offPos = null;
    _doneStops.clear();
  }

  /// Puts the car [at] metres along the route, stopped (to test a given
  /// manoeuvre without driving there).
  void teleport(double at) {
    distance = at.clamp(0.0, _route.length);
    speed = 0;
    _offPos = null;
    _stoppedFor = 0;
    _history.clear();
    _doneStops
      ..clear()
      ..addAll(stops.where((s) => s <= distance + 5));
  }

  /// Moves the car forward by [dt] seconds.
  void advance(double dt) {
    time += dt;
    final target = _targetSpeed();
    final a = target > speed ? 2.0 : 3.5; // m/s², accelerate / brake
    speed += (target - speed).clamp(-a * dt, a * dt);
    if (_stoppedFor > 0) {
      _stoppedFor -= dt;
      speed = 0;
    }
    final off = _offPos;
    if (off != null) {
      // Give up after 400 m without a new route.
      if (_offDriven < 400) {
        _offPos = offsetPoint(off, _offBearing, speed * dt);
        _offDriven += speed * dt;
      } else {
        speed = 0;
      }
    } else {
      distance = math.min(_route.length, distance + speed * dt);
      for (final s in stops) {
        if (!_doneStops.contains(s) && distance >= s && distance - s < 5) {
          _doneStops.add(s);
          _stoppedFor = stopSeconds;
        }
      }
    }
    // Multipath bias: a bounded random walk of a few metres.
    _biasE = (_biasE + _gauss() * 0.6 * math.sqrt(dt)).clamp(-6.0, 6.0);
    _biasN = (_biasN + _gauss() * 0.6 * math.sqrt(dt)).clamp(-6.0, 6.0);
    _history.add((time, position, speed));
    while (_history.length > 200) {
      _history.removeAt(0);
    }
  }

  /// The fix a receiver would report for the car [age] seconds ago, stamped
  /// with [now] minus that age.
  NavFix sample(DateTime now, {double age = 0.6}) {
    final at = time - age;
    final (_, truePos, trueSpeed) = _history.lastWhere(
      (h) => h.$1 <= at,
      orElse: () => _history.isEmpty ? (time, position, speed) : _history.first,
    );
    final outlier = _rng.nextDouble() < outlierRate;
    final errE = _biasE + _gauss() * noise + (outlier ? 45 : 0);
    final errN = _biasN + _gauss() * noise;
    final err = math.sqrt(errE * errE + errN * errN);
    final p = err == 0
        ? truePos
        : offsetPoint(truePos, math.atan2(errE, errN) * 180 / math.pi, err);
    return NavFix(
      position: p,
      accuracy: outlier ? 48 : 5 + _rng.nextDouble() * 6,
      speed: math.max(0, trueSpeed + _gauss() * 0.4),
      // Below ~2 m/s phones report a heading that is close to random.
      heading: trueSpeed > 2
          ? (heading + _gauss() * 8 + 360) % 360
          : _rng.nextDouble() * 360,
      time: now.subtract(Duration(milliseconds: (age * 1000).round())),
    );
  }

  double _targetSpeed() {
    if (isOffRoute) return cruise * 0.8;
    var v = cruise;
    // Slow down for turns and stop at the red lights, braking early enough.
    const brake = 2.5;
    void limit(double at, double vMax) {
      final d = at - distance;
      if (d < -5) return;
      final allowed = math.sqrt(vMax * vMax + 2 * brake * math.max(0, d));
      v = math.min(v, allowed);
    }

    for (final step in _route.steps) {
      final vTurn = switch (step.modifier) {
        ManeuverModifier.uturn => 2.5,
        ManeuverModifier.left ||
        ManeuverModifier.right ||
        ManeuverModifier.sharpLeft ||
        ManeuverModifier.sharpRight => 4.5,
        ManeuverModifier.slightLeft || ManeuverModifier.slightRight => 7.0,
        _ => null,
      };
      if (vTurn != null &&
          step.type != ManeuverType.depart &&
          step.type != ManeuverType.newName) {
        limit(step.distance, vTurn);
      }
    }
    for (final s in stops) {
      if (!_doneStops.contains(s)) limit(s, 0);
    }
    limit(_route.length, 0);
    return math.max(v, distance < _route.length - 1 ? 1.0 : 0.0);
  }

  double _gauss() {
    // Box-Muller.
    final u = 1 - _rng.nextDouble();
    final w = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * w);
  }
}
