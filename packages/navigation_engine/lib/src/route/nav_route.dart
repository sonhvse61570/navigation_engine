import 'dart:math' as math;

import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import 'route_snap.dart';
import 'route_step.dart';

/// A route polyline measured in metres, with its manoeuvres.
///
/// Positions are converted once to a local planar frame (equirectangular
/// around the first point). That is accurate to well under a metre over a
/// city-sized route and makes projections plain 2D vector maths; accuracy
/// degrades on routes longer than a few tens of kilometres.
final class NavRoute {
  NavRoute._(
    this.name,
    this.points,
    this.steps,
    this._xs,
    this._ys,
    this._cum,
    this._kLng,
    this._origin,
    this.summary,
    this._cumTime,
    this._speedLimits,
    this.hasProviderDurations,
  );

  /// Builds a route from its polyline and manoeuvres.
  ///
  /// Travel times: [segmentDurations] gives the seconds for each segment
  /// (`points[i]` → `points[i + 1]`), as routing back ends report them.
  /// Without it each segment is estimated from its entry in
  /// [segmentSpeedLimits] (metres per second, null when unknown), else from
  /// [fallbackSpeed]. [summary] is the "via …" label; when null it is the
  /// named road covering the longest distance.
  ///
  /// Throws [ArgumentError] when [points] has fewer than 2 points, a
  /// [RouteStepSeed.atVertex] index is out of range, a per-segment list does
  /// not have `points.length - 1` entries, a duration is negative or not
  /// finite, or a speed is not positive.
  factory NavRoute.fromPoints(
    List<GeoPoint> points, {
    List<RouteStepSeed> steps = const [],
    String name = '',
    String? summary,
    List<double>? segmentDurations,
    List<double?>? segmentSpeedLimits,
    double fallbackSpeed = 30 / 3.6,
  }) {
    if (points.length < 2) {
      throw ArgumentError.value(points, 'points', 'needs at least 2 points');
    }
    final segments = points.length - 1;
    if (segmentDurations != null && segmentDurations.length != segments) {
      throw ArgumentError.value(
        segmentDurations.length,
        'segmentDurations',
        'needs $segments entries, one per segment',
      );
    }
    if (segmentSpeedLimits != null && segmentSpeedLimits.length != segments) {
      throw ArgumentError.value(
        segmentSpeedLimits.length,
        'segmentSpeedLimits',
        'needs $segments entries, one per segment',
      );
    }
    if (!(fallbackSpeed > 0) || !fallbackSpeed.isFinite) {
      throw ArgumentError.value(fallbackSpeed, 'fallbackSpeed', 'must be > 0');
    }
    for (final d in segmentDurations ?? const <double>[]) {
      if (!d.isFinite || d < 0) {
        throw ArgumentError.value(d, 'segmentDurations', 'must be >= 0');
      }
    }
    for (final v in segmentSpeedLimits ?? const <double?>[]) {
      if (v != null && (!(v > 0) || !v.isFinite)) {
        throw ArgumentError.value(v, 'segmentSpeedLimits', 'must be > 0');
      }
    }
    final origin = points.first;
    final kLng = metresPerDegLng(origin.lat);
    final xs = <double>[];
    final ys = <double>[];
    for (final p in points) {
      xs.add((p.lng - origin.lng) * kLng);
      ys.add((p.lat - origin.lat) * mPerDegLat);
    }
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cum.add(cum.last + hypot(xs[i] - xs[i - 1], ys[i] - ys[i - 1]));
    }
    final resolved = <RouteStep>[];
    var from = 0;
    for (final s in steps) {
      final vertex = s.vertex ?? _nearestVertex(points, s.location!, from);
      if (vertex < 0 || vertex >= points.length) {
        throw ArgumentError.value(
          vertex,
          'steps',
          'vertex out of range (0..${points.length - 1})',
        );
      }
      from = vertex;
      resolved.add(
        RouteStep(
          distance: cum[vertex],
          type: s.type,
          modifier: s.modifier,
          roadName: s.roadName,
          lanes: List.unmodifiable(s.lanes),
        ),
      );
    }
    final cumTime = <double>[0];
    for (var i = 0; i < segments; i++) {
      final length = cum[i + 1] - cum[i];
      final seconds =
          segmentDurations?[i] ??
          (length == 0
              ? 0.0
              : length / (segmentSpeedLimits?[i] ?? fallbackSpeed));
      cumTime.add(cumTime.last + seconds);
    }
    return NavRoute._(
      name,
      List.unmodifiable(points),
      List.unmodifiable(resolved),
      xs,
      ys,
      cum,
      kLng,
      origin,
      summary ?? _longestRoad(resolved, cum.last),
      cumTime,
      segmentSpeedLimits == null ? null : List.unmodifiable(segmentSpeedLimits),
      segmentDurations != null,
    );
  }

  /// The named road the steps cover for the longest distance; a step's road
  /// runs from its manoeuvre to the next step.
  static String _longestRoad(List<RouteStep> steps, double length) {
    final byRoad = <String, double>{};
    for (var i = 0; i < steps.length; i++) {
      final road = steps[i].roadName;
      if (road.isEmpty) continue;
      final end = i + 1 < steps.length ? steps[i + 1].distance : length;
      byRoad[road] = (byRoad[road] ?? 0) + (end - steps[i].distance);
    }
    var best = '';
    var bestLength = 0.0;
    byRoad.forEach((road, d) {
      if (d > bestLength) {
        best = road;
        bestLength = d;
      }
    });
    return best;
  }

  /// The vertex nearest to [p], searching forward from [from] (the previous
  /// step's vertex): a U-turn back over the same road must not resolve to the
  /// outbound vertex. The first vertex within 0.5 m wins.
  static int _nearestVertex(List<GeoPoint> points, GeoPoint p, int from) {
    var best = from;
    var bestD = double.infinity;
    for (var i = from; i < points.length; i++) {
      final d = distanceBetween(points[i], p);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
      if (d < 0.5) break;
    }
    return best;
  }

  final String name;
  final List<GeoPoint> points;
  final List<RouteStep> steps;

  /// The "via …" label of the route (may be empty).
  final String summary;

  /// Whether the travel times came from the routing back end; false when
  /// every segment was estimated from speed limits or the fallback speed.
  final bool hasProviderDurations;

  /// Cumulative seconds at each vertex.
  final List<double> _cumTime;
  final List<double?>? _speedLimits;

  final List<double> _xs;
  final List<double> _ys;

  /// Cumulative distance (m) at each vertex.
  final List<double> _cum;
  final double _kLng;
  final GeoPoint _origin;

  /// Total length in metres.
  double get length => _cum.last;

  /// Total travel time in seconds.
  double get duration => _cumTime.last;

  /// Seconds from the start to [distance] metres along the route
  /// (interpolated within a segment, clamped to the route).
  double durationAt(double distance) {
    final d = distance.clamp(0.0, length);
    final i = _segmentAt(d);
    final seg = _cum[i + 1] - _cum[i];
    final t = seg == 0 ? 0.0 : (d - _cum[i]) / seg;
    return _cumTime[i] + (_cumTime[i + 1] - _cumTime[i]) * t;
  }

  /// Seconds still to drive from [distance] metres along the route.
  double remainingDuration(double distance) => duration - durationAt(distance);

  /// The speed limit (metres per second) at [distance], or null when
  /// unknown.
  double? speedLimitAt(double distance) {
    final limits = _speedLimits;
    if (limits == null) return null;
    return limits[_segmentAt(distance.clamp(0.0, length))];
  }

  (double, double) _toXy(GeoPoint p) =>
      ((p.lng - _origin.lng) * _kLng, (p.lat - _origin.lat) * mPerDegLat);

  GeoPoint _fromXy(double x, double y) =>
      GeoPoint(_origin.lat + y / mPerDegLat, _origin.lng + x / _kLng);

  /// Projects [p] onto the route.
  ///
  /// With [near] (metres along the route, usually the last known position)
  /// only the window `[near - behind, near + ahead]` is searched: this is what
  /// keeps the snap from jumping to a parallel road or to the other side of a
  /// U-turn, which are both a few metres away in a global search.
  RouteSnap snap(
    GeoPoint p, {
    double? near,
    double behind = 30,
    double ahead = 250,
  }) {
    final (px, py) = _toXy(p);
    var from = 0;
    var to = points.length - 2;
    if (near != null) {
      from = _segmentAt(near - behind);
      to = _segmentAt(near + ahead);
    }
    RouteSnap? best;
    for (var i = from; i <= to; i++) {
      final ax = _xs[i], ay = _ys[i];
      final abx = _xs[i + 1] - ax, aby = _ys[i + 1] - ay;
      final len2 = abx * abx + aby * aby;
      final t = len2 == 0
          ? 0.0
          : (((px - ax) * abx + (py - ay) * aby) / len2).clamp(0.0, 1.0);
      final qx = ax + abx * t, qy = ay + aby * t;
      final d = hypot(px - qx, py - qy);
      if (best == null || d < best.offset) {
        best = RouteSnap(
          distance: _cum[i] + (_cum[i + 1] - _cum[i]) * t,
          segment: i,
          point: _fromXy(qx, qy),
          offset: d,
        );
      }
    }
    return best!;
  }

  /// The point [distance] metres along the route (clamped to its ends).
  GeoPoint pointAt(double distance) {
    final (x, y) = _xyAt(distance);
    return _fromXy(x, y);
  }

  /// The heading (degrees clockwise from north) at [distance].
  ///
  /// Measured as the chord from `distance - behind` to `distance + ahead`
  /// rather than the heading of the current segment: corners are then turned
  /// gradually (starting [ahead] metres before the vertex) instead of in one
  /// snap when the next segment starts, and the many tiny segments of a curve
  /// do not make the heading jitter.
  double bearingAt(double distance, {double behind = 5, double ahead = 15}) {
    var a = distance - behind;
    var b = distance + ahead;
    if (a < 0) {
      b -= a;
      a = 0;
    }
    if (b > length) {
      a = math.max(0, a - (b - length));
      b = length;
    }
    final (ax, ay) = _xyAt(a);
    final (bx, by) = _xyAt(b);
    return bearingOf(bx - ax, by - ay);
  }

  /// The first step strictly ahead of [distance], or null past the last one.
  RouteStep? nextStep(double distance) {
    for (final s in steps) {
      if (s.distance > distance + 1) return s;
    }
    return null;
  }

  /// The route split at [distance]: the part already driven and the part
  /// still ahead (both include the split point).
  (List<GeoPoint>, List<GeoPoint>) splitAt(double distance) {
    final d = distance.clamp(0.0, length);
    final i = _segmentAt(d);
    final at = pointAt(d);
    return ([...points.sublist(0, i + 1), at], [at, ...points.sublist(i + 1)]);
  }

  /// The distance in metres along the route at `points[index]`, in the
  /// route's own planar frame (the one [pointAt] and [snap] use). Throws a
  /// [RangeError] when [index] is not a vertex.
  double distanceAtVertex(int index) {
    RangeError.checkValidIndex(index, points, 'index');
    return _cum[index];
  }

  /// The part of the route from [from] to [to] metres along it: the point at
  /// [from], the vertices strictly between, and the point at [to]. An end
  /// within a millimetre of a vertex is that vertex, once. Both ends are
  /// clamped to the route, and [to] to at least [from]: an empty range is
  /// its one point twice, so the result always has 2 points or more.
  List<GeoPoint> pointsBetween(double from, double to) {
    final a = from.clamp(0.0, length);
    final b = math.max(a, to.clamp(0.0, length));
    // Vertex k lies in (a, b) only for k in (segment of a, segment of b].
    final last = _segmentAt(b);
    return [
      _pointAtOrVertex(a),
      for (var k = _segmentAt(a) + 1; k <= last; k++)
        if (_cum[k] > a + _vertexSnap && _cum[k] < b - _vertexSnap) points[k],
      _pointAtOrVertex(b),
    ];
  }

  /// How close (m) to a vertex an end of [pointsBetween] is that vertex.
  static const double _vertexSnap = 1e-3;

  /// The vertex within [_vertexSnap] of [distance] when there is one, else
  /// [pointAt].
  GeoPoint _pointAtOrVertex(double distance) {
    final i = _segmentAt(distance);
    if ((_cum[i] - distance).abs() <= _vertexSnap) return points[i];
    if ((_cum[i + 1] - distance).abs() <= _vertexSnap) return points[i + 1];
    return pointAt(distance);
  }

  /// Index of the segment that contains [distance].
  int _segmentAt(double distance) {
    if (distance <= 0) return 0;
    if (distance >= length) return points.length - 2;
    var lo = 0, hi = _cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  (double, double) _xyAt(double distance) {
    final d = distance.clamp(0.0, length);
    final i = _segmentAt(d);
    final seg = _cum[i + 1] - _cum[i];
    final t = seg == 0 ? 0.0 : (d - _cum[i]) / seg;
    return (
      _xs[i] + (_xs[i + 1] - _xs[i]) * t,
      _ys[i] + (_ys[i + 1] - _ys[i]) * t,
    );
  }
}
