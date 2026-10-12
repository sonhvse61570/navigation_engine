import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'google_http.dart';
import 'google_routes_exception.dart';
import 'instructions.dart';
import 'maneuvers.dart';

/// The Routes API's `travelMode`.
enum GoogleTravelMode {
  /// A passenger car: the default.
  drive('DRIVE'),

  /// A two-wheeled, motorised vehicle, such as a motorbike (not a
  /// bicycle). Google bills it as an Enterprise feature, and asks apps to
  /// warn their users that these routes are in beta.
  twoWheeler('TWO_WHEELER');

  const GoogleTravelMode(this.id);

  /// The value sent as `travelMode`, such as `DRIVE`.
  final String id;
}

/// The Routes API's `routingPreference`.
enum GoogleRoutingPreference {
  /// Routes and durations that take live traffic into account: the
  /// default. Billed as Compute Routes Pro.
  trafficAware('TRAFFIC_AWARE'),

  /// Routes and durations from the road network and average traffic, not
  /// live traffic: the lowest latency. Billed as Compute Routes Essentials
  /// (unless another feature is Pro or Enterprise, such as the origin's
  /// heading: pass `sendHeading: false` to [GoogleRoutesRouteProvider.new]
  /// too, because the navigation engine sends one on every reroute).
  trafficUnaware('TRAFFIC_UNAWARE');

  const GoogleRoutingPreference(this.id);

  /// The value sent as `routingPreference`, such as `TRAFFIC_AWARE`.
  final String id;
}

/// Routes from Google's [Routes API](https://developers.google.com/maps/documentation/routes)
/// v2 (`POST /directions/v2:computeRoutes`).
///
/// ```dart
/// final router = GoogleRoutesRouteProvider(apiKey: key, languageCode: 'vi');
/// final routes = await router.routes(from, to, heading: fix.heading);
/// // ...
/// router.close();
/// ```
///
/// Google Maps Platform's terms ask that these routes be shown on a Google
/// map (see the README).
///
/// Each answer is read as follows:
///
/// - `routes[0]` is the best route and the others its alternatives, in
///   Google's order;
/// - the geometry is the steps' polylines joined (a point two steps share
///   is kept once), else the route's polyline;
/// - each step becomes a [RouteStep] where it starts, its `maneuver`
///   mapped to a [ManeuverType] and [ManeuverModifier] (none on the first
///   step departs; a value this package does not know is a turn without a
///   direction), its road name read from its `instructions`, best effort;
///   the arrival is the last point;
/// - each step's `staticDuration` is spread over its segments by length,
///   then scaled so that the route takes its `duration` (with traffic,
///   when [routingPreference] asks for it).
///
/// Routes v2 sends no lanes and no speed limits: the routes have none.
///
/// Failures throw a [GoogleRoutesException]:
/// [GoogleRoutesNoRouteException] when there is no route,
/// [GoogleRoutesStatusException] for a Google error status
/// (`INVALID_ARGUMENT`, `RESOURCE_EXHAUSTED`, …),
/// [GoogleRoutesHttpException] for a 401 or 403, or an HTTP error that is
/// not Google's, [GoogleRoutesTimeoutException] after [timeout], and
/// [GoogleRoutesFormatException] for an answer that is not Google's JSON.
/// Transport failures arrive as the `http` client throws them, the key in
/// their message replaced by `REDACTED`.
class GoogleRoutesRouteProvider extends RouteProvider {
  /// A provider that asks [routesBaseUrl] (by default
  /// [defaultRoutesBaseUrl]) for routes.
  ///
  /// - [apiKey] is sent as the `X-Goog-Api-Key` header; pass null to send
  ///   none, for a proxy that adds it.
  /// - [routesBaseUrl] may carry a path prefix, such as
  ///   `https://example.com/google/`, to which `directions/v2:computeRoutes`
  ///   is appended, and query parameters, which are kept.
  /// - [travelMode] is [GoogleTravelMode.drive] by default.
  /// - [routingPreference] is [GoogleRoutingPreference.trafficAware] by
  ///   default.
  /// - [languageCode] is the language of the instructions (a BCP-47 code
  ///   such as `vi` or `en`), from which road names are read; null sends
  ///   none (Google picks one from the route's location).
  /// - [alternatives] (true by default) lets [routes] ask for
  ///   alternatives; false never asks for them.
  /// - [sendHeading] (true by default) sends the origin heading that
  ///   [route] and [routes] get; false never sends one, which keeps the
  ///   request off the Pro SKU that a heading triggers (see the README's
  ///   Billing section).
  /// - [headers] are added to every request (a proxy's token, say), after
  ///   the package's own (`Accept`, `Content-Type`, `User-Agent`,
  ///   `X-Goog-Api-Key`, `X-Goog-FieldMask`), which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none.
  ///   The default is [defaultUserAgent], except on the web, where it is
  ///   null: a browser that honours the header would send a CORS preflight
  ///   the server may not answer.
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the provider creates one and [close] closes it.
  GoogleRoutesRouteProvider({
    required String? apiKey,
    Uri? routesBaseUrl,
    this.travelMode = GoogleTravelMode.drive,
    this.routingPreference = GoogleRoutingPreference.trafficAware,
    this.languageCode,
    this.alternatives = true,
    this.sendHeading = true,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = googlePlatformUserAgent,
    http.Client? client,
  }) : routesBaseUrl = routesBaseUrl ?? googleRoutesApi,
       _http = GoogleHttp(
         owner: 'GoogleRoutesRouteProvider',
         apiKey: apiKey,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       );

  /// The Routes API's root, `https://routes.googleapis.com`.
  static final Uri defaultRoutesBaseUrl = googleRoutesApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = googleDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = googleUserAgent;

  /// The response field mask sent as `X-Goog-FieldMask`: only what the
  /// provider reads.
  static const String fieldMask =
      'routes.distanceMeters,routes.duration,routes.staticDuration,'
      'routes.polyline.encodedPolyline,routes.routeLabels,'
      'routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,'
      'routes.legs.steps.polyline.encodedPolyline,'
      'routes.legs.steps.navigationInstruction';

  /// The API root, with any path prefix and query parameters.
  final Uri routesBaseUrl;

  /// The travel mode (`travelMode`).
  final GoogleTravelMode travelMode;

  /// Whether routes take live traffic into account (`routingPreference`).
  final GoogleRoutingPreference routingPreference;

  /// The language of the instructions (`languageCode`), or null for
  /// Google's choice.
  final String? languageCode;

  /// Whether [routes] may ask for alternatives.
  final bool alternatives;

  /// Whether the origin heading passed to [route] and [routes] is sent.
  final bool sendHeading;

  final GoogleHttp _http;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included, before it is aborted
  /// with a [GoogleRoutesTimeoutException].
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The best route from [from] to [to], asked for without alternatives.
  ///
  /// [heading] (degrees clockwise from north) is sent as the origin's
  /// `heading`, an integer from 0 to 359, so the route leaves the way the
  /// vehicle faces; the destination has none. A heading that is null or
  /// not finite sends none, and so does a provider with [sendHeading]
  /// false. (Google bills a request with a heading as Compute Routes Pro.)
  ///
  /// A `NavigationSession` calls this on every reroute, with the vehicle's
  /// bearing, and may do so every `rerouteInterval` (10 s by default) while
  /// the vehicle stays off the route; a `NavigationFlowController` adds a
  /// [routes] call after each one unless built with
  /// `fetchAlternatesOnReroute: false`. Each is a billed request. To cut
  /// the cost, set that option to false and, to stay on Essentials, use
  /// [GoogleRoutingPreference.trafficUnaware] with `sendHeading: false`.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [GoogleRoutesException] when the request fails.
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await _request(from, to, heading: heading, maxAlternatives: 0)).first;

  /// The best route, then up to [maxAlternatives] alternatives, as [route]
  /// asks for one.
  ///
  /// It sends `computeAlternativeRoutes: true` when [maxAlternatives] is
  /// positive and [alternatives] allows it; Google then sends up to two
  /// alternatives. Throws [ArgumentError] when [maxAlternatives] is
  /// negative.
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
      maxAlternatives: alternatives ? maxAlternatives : 0,
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
    final json = await _http.send(
      'POST',
      routesBaseUrl,
      const ['directions', 'v2:computeRoutes'],
      fieldMask: fieldMask,
      body: {
        'origin': _waypoint(
          from,
          heading: sendHeading && heading != null && heading.isFinite
              ? (heading % 360).round() % 360
              : null,
        ),
        'destination': _waypoint(to),
        'travelMode': travelMode.id,
        // The docs allow it with DRIVE and TWO_WHEELER, the only modes here.
        'routingPreference': routingPreference.id,
        'computeAlternativeRoutes': maxAlternatives > 0,
        'languageCode': ?languageCode,
        'polylineQuality': 'HIGH_QUALITY',
        'polylineEncoding': 'ENCODED_POLYLINE',
      },
    );
    try {
      final raw = json['routes'];
      final routes = raw == null ? const <Object?>[] : readList(raw, 'routes');
      // Google answers `{}` when there is no route.
      if (routes.isEmpty) throw const GoogleRoutesNoRouteException();
      return [
        for (var i = 0; i < routes.length && i <= maxAlternatives; i++)
          _parseRoute(routes[i], 'routes[$i]'),
      ];
    } on GoogleRoutesFormatException catch (e) {
      // The message may quote a server string.
      throw GoogleRoutesFormatException(
        _http.scrubbed(e.message)!,
        cause: e.cause,
      );
    }
  }

  static Map<String, Object?> _waypoint(GeoPoint p, {int? heading}) => {
    'location': {
      'latLng': {'latitude': p.lat, 'longitude': p.lng},
      'heading': ?heading,
    },
  };

  static NavRoute _parseRoute(Object? json, String path) {
    final r = readMap(json, path);
    final distance = _meters(r['distanceMeters'], '$path.distanceMeters');
    // Google omits a value of zero.
    final duration = _duration(r['duration'], '$path.duration') ?? 0;
    final staticDuration =
        _duration(r['staticDuration'], '$path.staticDuration') ?? 0;
    final target = duration > 0 ? duration : staticDuration;
    if (r['routeLabels'] case final Object labels) {
      final list = readList(labels, '$path.routeLabels');
      for (var i = 0; i < list.length; i++) {
        readString(list[i], '$path.routeLabels[$i]');
      }
    }

    final steps = <_Step>[];
    final rawLegs = r['legs'];
    final legs = rawLegs == null
        ? const <Object?>[]
        : readList(rawLegs, '$path.legs');
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = readMap(legs[l], legPath);
      final raw = leg['steps'];
      final list = raw == null
          ? const <Object?>[]
          : readList(raw, '$legPath.steps');
      for (var k = 0; k < list.length; k++) {
        steps.add(
          _Step.read(list[k], '$legPath.steps[$k]', first: steps.isEmpty),
        );
      }
    }

    final points = <GeoPoint>[];
    final seeds = <RouteStepSeed>[];
    List<double>? durations;
    if (steps.any((s) => s.points.isNotEmpty)) {
      // Each step's vertex range.
      final ranges = <(int, int)>[];
      for (final step in steps) {
        final int start;
        if (step.points.isEmpty) {
          start = points.isEmpty ? 0 : points.length - 1;
        } else {
          // The point two steps share is kept once.
          final shared = points.isNotEmpty && points.last == step.points.first;
          start = shared ? points.length - 1 : points.length;
          points.addAll(shared ? step.points.skip(1) : step.points);
        }
        ranges.add((start, points.isEmpty ? 0 : points.length - 1));
        if (step.type != ManeuverType.arrive) {
          seeds.add(step.seed(start));
        }
      }
      _checkLength(points, path);
      durations = _durations(points, ranges, [for (final s in steps) s.time]);
    } else {
      // No step geometry: the route's polyline, with a departure only.
      final polyline = readOptionalMap(r['polyline'], '$path.polyline');
      final encoded = polyline?['encodedPolyline'];
      if (encoded == null) {
        throw GoogleRoutesFormatException(
          '$path.polyline: no step polyline and no route polyline',
        );
      }
      points.addAll(_decode(encoded, '$path.polyline.encodedPolyline'));
      _checkLength(points, path);
      seeds.add(
        steps.isEmpty || steps.first.type == ManeuverType.arrive
            ? const RouteStepSeed.atVertex(0, type: ManeuverType.depart)
            : steps.first.seed(0),
      );
    }
    final last = points.length - 1;
    // A last step of no length: its manoeuvre is the arrival.
    if (seeds.length > 1 && seeds.last.vertex == last) seeds.removeLast();
    seeds.add(RouteStepSeed.atVertex(last, type: ManeuverType.arrive));

    final stepTime = durations?.fold(0.0, (a, b) => a + b) ?? 0;
    if (target > 0 && stepTime > 0) {
      // The steps' static times, scaled to the route's (traffic) duration.
      durations = [for (final d in durations!) d * target / stepTime];
    } else if (target > 0) {
      durations = _spread(points, target);
    } else if (stepTime == 0) {
      durations = null;
    }

    NavRoute build(String name) {
      try {
        return NavRoute.fromPoints(
          points,
          steps: seeds,
          name: name,
          segmentDurations: durations,
        );
      } on ArgumentError catch (e) {
        throw GoogleRoutesFormatException('$path: ${e.message} (${e.name})');
      }
    }

    if (distance != null) return build('Google ${distance.round()} m');
    final unnamed = build('');
    return build('Google ${unnamed.length.round()} m');
  }

  static void _checkLength(List<GeoPoint> points, String path) {
    if (points.length < 2) {
      throw GoogleRoutesFormatException(
        '$path: ${points.length} point(s), a route needs at least 2',
      );
    }
  }

  /// Each step's [seconds] spread over the segments of its range by length
  /// (evenly when they have none). The time of a step without segments
  /// goes to the segment before it (after it, at the start).
  static List<double> _durations(
    List<GeoPoint> points,
    List<(int, int)> ranges,
    List<double> seconds,
  ) {
    final out = List<double>.filled(points.length - 1, 0);
    for (var k = 0; k < ranges.length; k++) {
      final (from, to) = ranges[k];
      final time = seconds[k];
      if (time == 0) continue;
      if (from == to) {
        out[from > 0 ? from - 1 : 0] += time;
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

  /// [time] spread over the segments of [points] by length (evenly when
  /// they have none).
  static List<double> _spread(List<GeoPoint> points, double time) {
    final lengths = [
      for (var i = 0; i + 1 < points.length; i++)
        distanceBetween(points[i], points[i + 1]),
    ];
    final total = lengths.fold(0.0, (a, b) => a + b);
    return [
      for (final l in lengths)
        total == 0 ? time / lengths.length : time * l / total,
    ];
  }

  /// A `distanceMeters` value; null when absent. A negative one throws.
  static double? _meters(Object? json, String path) {
    if (json == null) return null;
    final value = readNumber(json, path);
    if (value < 0) {
      throw GoogleRoutesFormatException('$path: negative ($value)');
    }
    return value;
  }

  static List<GeoPoint> _decode(Object? json, String path) {
    final encoded = readString(json, path);
    try {
      return decodePolyline(encoded);
    } on FormatException catch (e) {
      throw GoogleRoutesFormatException('$path: ${e.message}', cause: e);
    }
  }
}

/// A Google duration: seconds with up to nine decimals, then `s`.
final _durationPattern = RegExp(r'^\d+(?:\.\d{1,9})?s$');

/// A duration such as `"12.5s"` in seconds; null when absent. Any other
/// form throws.
double? _duration(Object? json, String path) {
  if (json == null) return null;
  if (json is String && _durationPattern.hasMatch(json)) {
    return double.parse(json.substring(0, json.length - 1));
  }
  throw GoogleRoutesFormatException(
    '$path: expected a duration such as "12.5s", got '
    '${json is String ? '"$json"' : kindOf(json)}',
  );
}

/// One step of a route, as read.
final class _Step {
  _Step(this.points, this.type, this.modifier, this.roadName, this.time);

  /// The step at [path]; [first] when it is the route's first.
  factory _Step.read(Object? json, String path, {required bool first}) {
    final step = readMap(json, path);
    GoogleRoutesRouteProvider._meters(
      step['distanceMeters'],
      '$path.distanceMeters',
    );
    // Google omits a value of zero.
    final time = _duration(step['staticDuration'], '$path.staticDuration') ?? 0;
    final polyline = readOptionalMap(step['polyline'], '$path.polyline');
    final encoded = polyline?['encodedPolyline'];
    final points = encoded == null
        ? const <GeoPoint>[]
        : GoogleRoutesRouteProvider._decode(
            encoded,
            '$path.polyline.encodedPolyline',
          );
    final at = '$path.navigationInstruction';
    final nav = readOptionalMap(step['navigationInstruction'], at);
    final maneuver = readOptionalString(nav?['maneuver'], '$at.maneuver');
    final instructions =
        readOptionalString(nav?['instructions'], '$at.instructions') ?? '';
    final (
      type,
      modifier,
    ) = first && (maneuver == null || maneuver == 'MANEUVER_UNSPECIFIED')
        ? (ManeuverType.depart, ManeuverModifier.none)
        // A value Google adds later: a turn, direction unknown.
        : googleManeuver(maneuver) ??
              (ManeuverType.turn, ManeuverModifier.none);
    return _Step(points, type, modifier, roadNameOf(instructions) ?? '', time);
  }

  final List<GeoPoint> points;
  final ManeuverType type;
  final ManeuverModifier modifier;
  final String roadName;

  /// The step's `staticDuration` in seconds.
  final double time;

  RouteStepSeed seed(int vertex) => RouteStepSeed.atVertex(
    vertex,
    type: type,
    modifier: modifier,
    roadName: roadName,
  );
}
