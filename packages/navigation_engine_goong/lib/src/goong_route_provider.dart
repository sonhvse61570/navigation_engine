import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'goong_exception.dart';
import 'goong_http.dart';
import 'instructions.dart';
import 'maneuvers.dart';
import 'polyline.dart';

/// The vehicle direction v2 plans for (`vehicle=`).
///
/// Goong's direction v2 page lists `car` and `bike` (its table is cut
/// short); its v1 documentation also lists `taxi`, `truck` and `hd`.
enum GoongVehicle {
  /// A car: the default.
  car,

  /// A bike: a bicycle ("xe đạp") per the v2 page; confirm with the live
  /// check.
  bike,

  /// A taxi.
  taxi,

  /// A truck.
  truck,

  /// Ride-hailing (`hd`).
  hd,
}

/// Routes from [Goong](https://goong.io)'s direction v2 API
/// (`GET /v2/direction`).
///
/// ```dart
/// final router = GoongRouteProvider(
///   apiKey: null, // the key is added by your proxy
///   baseUrl: Uri.parse('https://maps-proxy.example.com/goong/'),
/// );
/// final routes = await router.routes(from, to);
/// // ...
/// router.close();
/// ```
///
/// The answer has Google Directions' shape. Each of its `routes` becomes a
/// [NavRoute]:
///
/// - the geometry is the steps' precision-5 polylines joined in order, the
///   point two steps share kept once;
/// - each step becomes a [RouteStep] where it starts. Its `maneuver` gives
///   the manoeuvre (Google's strings, and Goong's own such as
///   `slight right`); the first step is the departure. The road name comes
///   from a step `name` when there is one, else from `html_instructions`;
/// - an arrival is placed at the end (Goong's final zero-length step, when
///   it sends one, becomes it);
/// - each step's `duration` is spread over its segments by length.
///
/// Direction v2 takes no heading: [route] and [routes] ignore theirs, so a
/// reroute may start with a U-turn. It sends no lanes either.
///
/// REST keys (Goong's "API key") should stay on a server: point [baseUrl]
/// at a proxy that adds the key, and pass `apiKey: null`. A key passed
/// here is sent as the `api_key` query parameter, from the app.
///
/// Failures throw a [GoongException]: [GoongCodeException] for a Goong code
/// (`ZERO_RESULTS`, `REQUEST_DENIED`, …), [GoongHttpException] for an HTTP
/// error, [GoongTimeoutException] after [timeout], and
/// [GoongFormatException] for an answer that is not Goong's JSON. Transport
/// failures arrive as the `http` client throws them, the key in their URL
/// and message replaced by `REDACTED`.
class GoongRouteProvider extends RouteProvider {
  /// A provider that asks [baseUrl] (by default [defaultBaseUrl]) for
  /// [vehicle] routes.
  ///
  /// - [apiKey] is sent as the `api_key` query parameter; pass null to send
  ///   none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, such as
  ///   `https://example.com/goong/`, to which `v2/direction` is appended,
  ///   and query parameters, which are kept.
  /// - [vehicle] is the vehicle to plan for.
  /// - [headers] are added to every request (a proxy's token, say), after
  ///   `Accept` and `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none.
  ///   The default is [defaultUserAgent], except on the web, where it is
  ///   null: a browser that honours the header would send a CORS preflight
  ///   the server may not answer.
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the provider creates one and [close] closes it.
  GoongRouteProvider({
    required String? apiKey,
    Uri? baseUrl,
    this.vehicle = GoongVehicle.car,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = goongPlatformUserAgent,
    http.Client? client,
  }) : _http = GoongHttp(
         owner: 'GoongRouteProvider',
         apiKey: apiKey,
         baseUrl: baseUrl,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       );

  /// Goong's REST API root, `https://rsapi.goong.io/`.
  static final Uri defaultBaseUrl = goongApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = goongDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = goongUserAgent;

  /// The vehicle the routes are for.
  final GoongVehicle vehicle;

  final GoongHttp _http;

  /// The API root, with any path prefix and query parameters.
  Uri get baseUrl => _http.baseUrl;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included, before it is aborted
  /// with a [GoongTimeoutException].
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The best route from [from] to [to], asked for without alternatives.
  ///
  /// [heading] is ignored: direction v2 takes none, so a reroute may start
  /// with a U-turn.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [GoongException] when the request fails.
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await _request(from, to, maxAlternatives: 0)).first;

  /// The best route, then up to [maxAlternatives] alternatives
  /// (`alternatives=true`; Goong decides how many), as [route] asks for
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
    return _request(from, to, maxAlternatives: maxAlternatives);
  }

  /// Releases the HTTP client when the provider created it; an injected
  /// client is left open. The provider throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  Future<List<NavRoute>> _request(
    GeoPoint from,
    GeoPoint to, {
    required int maxAlternatives,
  }) async {
    _http.checkOpen();
    checkFinite(from, 'from');
    checkFinite(to, 'to');
    final json = await _http.get(
      ['v2', 'direction'],
      [
        ('origin', latLng(from)),
        ('destination', latLng(to)),
        ('vehicle', vehicle.name),
        ('alternatives', '${maxAlternatives > 0}'),
      ],
    );
    if (json is! Map<String, Object?>) {
      throw GoongFormatException(
        'the answer is not a JSON object: got ${kindOf(json)}',
      );
    }
    final routes = readList(json['routes'], 'routes');
    if (routes.isEmpty) {
      throw const GoongFormatException('routes: an OK answer with no routes');
    }
    return [
      for (var i = 0; i < routes.length && i <= maxAlternatives; i++)
        _parseRoute(routes[i], 'routes[$i]'),
    ];
  }

  static NavRoute _parseRoute(Object? json, String path) {
    final r = readMap(json, path);
    final legs = readList(r['legs'], '$path.legs');
    final summary = readOptionalString(r['summary'], '$path.summary') ?? '';

    final points = <GeoPoint>[];
    final seeds = <RouteStepSeed>[];
    // Each step's vertex range and seconds (null when it sent none).
    final ranges = <(int, int)>[];
    final seconds = <double?>[];
    // The legs' distance; null when one has none.
    double? distance = 0;
    double? legsTime = 0;
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = readMap(legs[l], legPath);
      final legDistance = _value(leg['distance'], '$legPath.distance');
      distance = legDistance == null || distance == null
          ? null
          : distance + legDistance;
      final legTime = _value(leg['duration'], '$legPath.duration');
      legsTime = legTime == null || legsTime == null
          ? null
          : legsTime + legTime;
      final raw = leg['steps'];
      final steps = raw == null
          ? const <Object?>[]
          : readList(raw, '$legPath.steps');
      for (var k = 0; k < steps.length; k++) {
        final at = '$legPath.steps[$k]';
        final step = readMap(steps[k], at);
        final polyline = readMap(step['polyline'], '$at.polyline');
        final stepPoints = _decode(polyline['points'], '$at.polyline.points');
        final start = points.isEmpty ? 0 : points.length - 1;
        for (final (j, p) in stepPoints.indexed) {
          // The point two steps share is kept once.
          if (j == 0 && points.isNotEmpty && points.last == p) continue;
          points.add(p);
        }
        final maneuver = readOptionalString(step['maneuver'], '$at.maneuver');
        final html =
            readOptionalString(
              step['html_instructions'],
              '$at.html_instructions',
            ) ??
            '';
        final name = readOptionalString(step['name'], '$at.name') ?? '';
        final (type, modifier) = seeds.isEmpty
            ? (ManeuverType.depart, ManeuverModifier.none)
            // A value Goong adds later: a turn, direction unknown.
            : goongManeuver(maneuver) ??
                  (ManeuverType.turn, ManeuverModifier.none);
        seeds.add(
          RouteStepSeed.atVertex(
            start,
            type: type,
            modifier: modifier,
            roadName: name.isNotEmpty ? name : roadNameOf(html),
          ),
        );
        ranges.add((start, points.length - 1));
        seconds.add(_value(step['duration'], '$at.duration'));
      }
    }
    if (seeds.isEmpty) {
      // No steps: the overview polyline, with no manoeuvre but the arrival.
      final overview = readMap(
        r['overview_polyline'],
        '$path.overview_polyline',
      );
      points.addAll(
        _decode(overview['points'], '$path.overview_polyline.points'),
      );
    }
    if (points.length < 2) {
      throw GoongFormatException(
        '$path: ${points.length} point(s), a route needs at least 2',
      );
    }
    if (ranges.length > 1) {
      // A final step of no length sent as several points (`[p, p]`): keep
      // one, so that it becomes the arrival below.
      final (from, to) = ranges.last;
      if (to > from &&
          [
            for (var i = from + 1; i <= to; i++) points[i],
          ].every((p) => p == points[from])) {
        points.removeRange(from + 1, to + 1);
        ranges.last = (from, from);
      }
    }
    final last = points.length - 1;
    if (seeds.length > 1 && ranges.last == (last, last)) {
      // Goong's final step ("Bạn đã đến điểm đích"), of no length.
      seeds.removeLast();
    }
    seeds.add(RouteStepSeed.atVertex(last, type: ManeuverType.arrive));
    try {
      return NavRoute.fromPoints(
        points,
        steps: seeds,
        name: 'Goong ${(distance ?? _length(points)).round()} m',
        summary: summary.isEmpty ? null : summary,
        segmentDurations:
            _durations(points, ranges, seconds) ?? _spread(points, legsTime),
      );
    } on ArgumentError catch (e) {
      throw GoongFormatException('$path: ${e.message} (${e.name})');
    }
  }

  /// The `value` of a `{text, value}` object such as `distance` or
  /// `duration`; null when [json] is absent. A negative value throws.
  static double? _value(Object? json, String path) {
    if (json == null) return null;
    final value = readNumber(readMap(json, path)['value'], '$path.value');
    if (value < 0) {
      throw GoongFormatException('$path.value: negative ($value)');
    }
    return value;
  }

  static List<GeoPoint> _decode(Object? json, String path) {
    final encoded = readString(json, path);
    final List<GeoPoint> points;
    try {
      points = decodePolyline5(encoded);
    } on FormatException catch (e) {
      throw GoongFormatException('$path: ${e.message}');
    }
    if (points.isEmpty) throw GoongFormatException('$path: no points');
    return points;
  }

  /// The length of [points] in metres, for a route whose legs give none.
  static double _length(List<GeoPoint> points) => [
    for (var i = 0; i + 1 < points.length; i++)
      distanceBetween(points[i], points[i + 1]),
  ].fold(0.0, (a, b) => a + b);

  /// The legs' [time] in seconds spread over the route's segments by
  /// length: Goong's ETA, when the steps cannot place it. Null without a
  /// positive time, or for a route of no length.
  static List<double>? _spread(List<GeoPoint> points, double? time) {
    if (time == null || time <= 0) return null;
    final lengths = [
      for (var i = 0; i + 1 < points.length; i++)
        distanceBetween(points[i], points[i + 1]),
    ];
    final total = lengths.fold(0.0, (a, b) => a + b);
    if (total == 0) return null;
    return [for (final l in lengths) time * l / total];
  }

  /// Each step's [seconds] spread over the segments of its range by length
  /// (evenly when they have none). The time of a step without segments
  /// goes to the segment before it (after it, at the start). Null when a
  /// step with segments has no duration, or there are no steps: the legs'
  /// time is then spread instead.
  static List<double>? _durations(
    List<GeoPoint> points,
    List<(int, int)> ranges,
    List<double?> seconds,
  ) {
    if (ranges.isEmpty) return null;
    final out = List<double>.filled(points.length - 1, 0);
    for (var k = 0; k < ranges.length; k++) {
      final (from, to) = ranges[k];
      final time = seconds[k];
      if (from == to) {
        if (time != null && time > 0) out[from > 0 ? from - 1 : 0] += time;
        continue;
      }
      if (time == null) return null;
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
