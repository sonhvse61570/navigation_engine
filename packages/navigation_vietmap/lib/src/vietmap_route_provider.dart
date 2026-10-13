import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'polyline.dart';
import 'signs.dart';
import 'vietmap_exception.dart';
import 'vietmap_http.dart';

/// The vehicle route v4 plans for (`vehicle=`): its speeds and the roads
/// it may use.
enum VietmapVehicle {
  /// A car: Vietmap's default.
  car,

  /// A motorcycle, which Vietnamese roads (and Vietmap) treat apart.
  motorcycle,

  /// A truck: needs its gross weight, `VietmapRouteProvider.capacity`.
  truck,

  /// A container truck.
  container,
}

/// Routes from [Vietmap](https://maps.vietmap.vn)'s route v4 API
/// (`GET /api/route/v4`).
///
/// ```dart
/// final router = VietmapRouteProvider(
///   apiKey: null, // the key is added by your proxy
///   baseUrl: Uri.parse('https://maps-proxy.example.com/vietmap/'),
/// );
/// final routes = await router.routes(from, to, heading: fix.heading);
/// // ...
/// router.close();
/// ```
///
/// Each path of the answer becomes a [NavRoute]: its precision-5 polyline,
/// a [RouteStep] per instruction (the `sign` gives the manoeuvre, the
/// `interval` places it at its first vertex, `street_name` gives the road)
/// and per-segment durations from each instruction's `time`, spread over
/// its interval by length. Route v4 has no lanes.
///
/// REST keys (Vietmap's "services key") should stay on a server: point
/// [baseUrl] at a proxy that adds the key, and pass `apiKey: null`. A key
/// passed here is sent as the `apikey` query parameter, from the app.
///
/// Failures throw a [VietmapException]: [VietmapCodeException] for a
/// Vietmap code (`ZERO_RESULTS`, `OVER_DAILY_LIMIT`, …),
/// [VietmapHttpException] for an HTTP error, [VietmapTimeoutException]
/// after [timeout], and [VietmapFormatException] for an answer that is not
/// Vietmap's JSON. Transport failures arrive as the `http` client throws
/// them, the key in their URL and their message replaced by `REDACTED`.
class VietmapRouteProvider extends RouteProvider {
  /// A provider that asks [baseUrl] (by default [defaultBaseUrl]) for
  /// [vehicle] routes.
  ///
  /// - [apiKey] is sent as the `apikey` query parameter; pass null to send
  ///   none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, such as
  ///   `https://example.com/vietmap/`, to which `route/v4` is appended,
  ///   and query parameters, which are kept.
  /// - [vehicle] is the vehicle to plan for; a [VietmapVehicle.truck] needs
  ///   its [capacity].
  /// - [capacity] is the vehicle's gross weight in kilograms, sent when
  ///   given.
  /// - [headers] are added to every request (a proxy's token, say), after
  ///   `Accept` and `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none.
  ///   The default is [defaultUserAgent], except on the web, where it is
  ///   null: a browser that honours the header would send a CORS preflight
  ///   the server may not answer.
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the provider creates one and [close] closes it.
  ///
  /// Throws [ArgumentError] for a truck without a capacity, or a capacity
  /// that is not positive.
  VietmapRouteProvider({
    required String? apiKey,
    Uri? baseUrl,
    this.vehicle = VietmapVehicle.car,
    this.capacity,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = vietmapPlatformUserAgent,
    http.Client? client,
  }) : _http = VietmapHttp(
         owner: 'VietmapRouteProvider',
         apiKey: apiKey,
         baseUrl: baseUrl,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       ) {
    if (capacity case final c? when c <= 0) {
      throw ArgumentError.value(c, 'capacity', 'must be > 0');
    }
    if (vehicle == VietmapVehicle.truck && capacity == null) {
      throw ArgumentError.notNull('capacity');
    }
  }

  /// Vietmap's REST API root, `https://maps.vietmap.vn/api/`.
  static final Uri defaultBaseUrl = vietmapApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = vietmapDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = vietmapUserAgent;

  /// The vehicle the routes are for.
  final VietmapVehicle vehicle;

  /// The vehicle's gross weight in kilograms, or null to send none.
  final int? capacity;

  final VietmapHttp _http;

  /// The API root, with any path prefix and query parameters.
  Uri get baseUrl => _http.baseUrl;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included, before it is aborted
  /// with a [VietmapTimeoutException].
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The best route from [from] to [to], asked for without alternatives.
  ///
  /// [heading] (degrees clockwise from north) is sent as `heading`, in
  /// whole degrees, so the route leaves the way the vehicle faces; a
  /// heading that is null or not finite sends none.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [VietmapException] when the request fails.
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await _request(from, to, heading: heading, maxAlternatives: 0)).first;

  /// The best route, then up to [maxAlternatives] alternatives
  /// (`alternative=true`; Vietmap decides how many), as [route] asks for
  /// one. Throws [ArgumentError] when [maxAlternatives] is negative.
  @override
  Future<List<NavRoute>> routes(
    GeoPoint from,
    GeoPoint to, {
    double? heading,
    int maxAlternatives = 2,
  }) async {
    if (maxAlternatives < 0) {
      throw ArgumentError.value(maxAlternatives, 'maxAlternatives', 'is < 0');
    }
    return _request(
      from,
      to,
      heading: heading,
      maxAlternatives: maxAlternatives,
    );
  }

  /// Releases the HTTP client when the provider created it; an injected
  /// client is left open. The provider throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  Future<List<NavRoute>> _request(
    GeoPoint from,
    GeoPoint to, {
    required double? heading,
    required int maxAlternatives,
  }) async {
    _http.checkOpen();
    checkFinite(from, 'from');
    checkFinite(to, 'to');
    final json = await _http.get(
      ['route', 'v4'],
      [
        ('point', '${fixed6(from.lat)},${fixed6(from.lng)}'),
        ('point', '${fixed6(to.lat)},${fixed6(to.lng)}'),
        ('vehicle', vehicle.name),
        if (capacity case final c?) ('capacity', '$c'),
        ('alternative', '${maxAlternatives > 0}'),
        if (heading != null && heading.isFinite)
          ('heading', '${(heading % 360).round() % 360}'),
        ('points_encoded', 'true'),
      ],
    );
    if (json is! Map<String, Object?>) {
      throw VietmapFormatException(
        'the answer is not a JSON object: got ${kindOf(json)}',
      );
    }
    final paths = readList(json['paths'], 'paths');
    if (paths.isEmpty) {
      throw const VietmapFormatException('paths: an OK answer with no paths');
    }
    return [
      for (var i = 0; i < paths.length && i <= maxAlternatives; i++)
        _parsePath(paths[i], 'paths[$i]'),
    ];
  }

  static NavRoute _parsePath(Object? json, String path) {
    final p = readMap(json, path);
    final points = _points(p['points'], '$path.points');
    final distance = readNumber(p['distance'], '$path.distance');
    final pathTime = p['time'] == null
        ? null
        : readNumber(p['time'], '$path.time');
    if (pathTime != null && pathTime < 0) {
      throw VietmapFormatException('$path.time: negative ($pathTime)');
    }
    final raw = p['instructions'];
    final instructions = raw == null
        ? const <Object?>[]
        : readList(raw, '$path.instructions');
    final seeds = <RouteStepSeed>[];
    final intervals = <(int, int)>[];
    final seconds = <double>[];
    for (var i = 0; i < instructions.length; i++) {
      final at = '$path.instructions[$i]';
      final instruction = readMap(instructions[i], at);
      final sign = _sign(instruction['sign'], '$at.sign');
      final interval = _interval(
        instruction['interval'],
        '$at.interval',
        vertices: points.length,
        notBefore: intervals.isEmpty ? 0 : intervals.last.$1,
      );
      final time = readNumber(instruction['time'], '$at.time');
      if (time < 0) {
        throw VietmapFormatException('$at.time: negative ($time)');
      }
      final name =
          readOptionalString(instruction['street_name'], '$at.street_name') ??
          '';
      final ref =
          readOptionalString(instruction['street_ref'], '$at.street_ref') ?? '';
      final (type, modifier) = i == 0 && sign == 0
          ? (ManeuverType.depart, ManeuverModifier.none)
          // A code Vietmap adds later: a turn, direction unknown.
          : vietmapSign(sign) ?? (ManeuverType.turn, ManeuverModifier.none);
      seeds.add(
        RouteStepSeed.atVertex(
          interval.$1,
          type: type,
          modifier: modifier,
          roadName: name.isNotEmpty ? name : ref,
        ),
      );
      intervals.add(interval);
      seconds.add(time / 1000);
    }
    try {
      return NavRoute.fromPoints(
        points,
        steps: seeds,
        name: 'Vietmap ${distance.round()} m',
        segmentDurations:
            _durations(points, intervals, seconds) ?? _spread(points, pathTime),
      );
    } on ArgumentError catch (e) {
      throw VietmapFormatException('$path: ${e.message} (${e.name})');
    }
  }

  static List<GeoPoint> _points(Object? json, String path) {
    if (json is! String) {
      throw VietmapFormatException(
        '$path: expected an encoded polyline (points_encoded=true), '
        'got ${kindOf(json)}',
      );
    }
    final List<GeoPoint> points;
    try {
      points = decodePolyline5(json);
    } on FormatException catch (e) {
      throw VietmapFormatException('$path: ${e.message}');
    }
    if (points.length < 2) {
      throw VietmapFormatException(
        '$path: ${points.length} point(s), a route needs at least 2',
      );
    }
    return points;
  }

  /// The integer `sign`, which may come as a whole double.
  static int _sign(Object? json, String path) {
    final n = readNumber(json, path);
    if (n != n.roundToDouble()) {
      throw VietmapFormatException('$path: expected an integer, got $n');
    }
    return n.toInt();
  }

  /// The `[from, to]` vertex range, within the path and starting no
  /// earlier than the previous instruction's.
  static (int, int) _interval(
    Object? json,
    String path, {
    required int vertices,
    required int notBefore,
  }) {
    final pair = readList(json, path);
    if (pair.length != 2) {
      throw VietmapFormatException('$path: expected [from, to]');
    }
    final [first, second] = pair;
    if (first is! num ||
        second is! num ||
        first != first.roundToDouble() ||
        second != second.roundToDouble()) {
      // Described, not quoted: a string from the server may hold anything.
      final got = [for (final v in pair) v is num ? '$v' : kindOf(v)];
      throw VietmapFormatException(
        '$path: expected two vertex indices, got [${got.join(', ')}]',
      );
    }
    final (from, to) = (first.toInt(), second.toInt());
    if (from < notBefore || from > to || to >= vertices) {
      throw VietmapFormatException(
        '$path: [$from, $to] is out of order or out of range '
        '($notBefore..${vertices - 1})',
      );
    }
    return (from, to);
  }

  /// The path's [time] in milliseconds spread over its segments by length:
  /// Vietmap's ETA, when the instructions cannot place it. Null without a
  /// positive time, or for a path of no length.
  static List<double>? _spread(List<GeoPoint> points, double? time) {
    if (time == null || time <= 0) return null;
    final lengths = [
      for (var i = 0; i + 1 < points.length; i++)
        distanceBetween(points[i], points[i + 1]),
    ];
    final total = lengths.fold(0.0, (a, b) => a + b);
    if (total == 0) return null;
    return [for (final l in lengths) time / 1000 * l / total];
  }

  /// Each instruction's [seconds] spread over the segments of its interval
  /// by length (evenly when they have none). The time of an instruction
  /// without segments goes to the segment before it (after it, at the
  /// start). Null unless the intervals cover every segment once, in order:
  /// the path's time is then spread instead.
  static List<double>? _durations(
    List<GeoPoint> points,
    List<(int, int)> intervals,
    List<double> seconds,
  ) {
    final segments = points.length - 1;
    if (intervals.isEmpty) return null;
    var next = 0;
    for (final (from, to) in intervals) {
      if (from != next) return null;
      next = to;
    }
    if (next != segments) return null;

    final out = List<double>.filled(segments, 0);
    for (var k = 0; k < intervals.length; k++) {
      final (from, to) = intervals[k];
      final time = seconds[k];
      if (from == to) {
        if (time > 0) out[from > 0 ? from - 1 : 0] += time;
        continue;
      }
      final lengths = [
        for (var i = from; i < to; i++)
          distanceBetween(points[i], points[i + 1]),
      ];
      final total = lengths.fold(0.0, (a, b) => a + b);
      for (var i = from; i < to; i++) {
        out[i] += total == 0
            ? time / (to - from)
            : time * lengths[i - from] / total;
      }
    }
    return out;
  }
}
