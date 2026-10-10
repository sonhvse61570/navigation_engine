import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'osrm_exception.dart';
import 'polyline.dart';

/// How OSRM encodes the route geometry in its answer (`geometries=`).
enum OsrmGeometries {
  /// GeoJSON `LineString` coordinates: plain, but about three times larger
  /// on the wire.
  geojson,

  /// An encoded polyline with six decimals: compact, and as precise as
  /// OSRM's own coordinates.
  polyline6,
}

/// Routes from an [OSRM](https://project-osrm.org) server, through its
/// route service (`/route/v1`).
///
/// ```dart
/// final provider = OsrmRouteProvider(
///   baseUrl: Uri.parse('https://osrm.example.com'),
///   userAgent: 'my_app/1.0',
/// );
/// final routes = await provider.routes(from, to, heading: fix.heading);
/// // ...
/// provider.close();
/// ```
///
/// The default [baseUrl] is OSRM's public demo server, [demoServer]. It is
/// for testing only: it is rate limited, has no availability guarantee, and
/// sees the coordinates of every request. Ship your own server, or a hosted
/// one, in an app.
///
/// Each step becomes a [RouteStep]: its manoeuvre type and modifier, its
/// road name (falling back to the road's `ref`) and its lanes, placed on the
/// route at its manoeuvre location. The `duration` annotations give the time
/// of each segment.
///
/// Failures throw an [OsrmException]: [OsrmCodeException] for an OSRM error
/// code (`NoRoute`, `NoSegment`, …), [OsrmHttpException] for an HTTP error,
/// [OsrmTimeoutException] after [timeout], and [OsrmFormatException] for an
/// answer that is not OSRM's JSON. Transport failures arrive as the `http`
/// client throws them.
class OsrmRouteProvider extends RouteProvider {
  /// A provider that asks [baseUrl] (by default [demoServer], for testing
  /// only) for [profile] routes.
  ///
  /// - [baseUrl] may carry a path prefix, such as
  ///   `https://example.com/osrm/`, to which `route/v1/...` is appended,
  ///   and query parameters (an API key of a hosted server, say), which
  ///   are kept.
  /// - [profile] is the server's profile name, `driving` by default. The
  ///   demo server has only `driving`, whatever the name says.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [geometries] is how the route geometry is sent.
  /// - [speedLimits] (off by default) asks for every annotation
  ///   (`annotations=true`, the only way OSRM sends `maxspeed`) and turns
  ///   `maxspeed` into the routes' speed limits. Turn it on only for a
  ///   server that sends `maxspeed`: mainline OSRM, the demo server
  ///   included, does not, so it would only make the answers larger. Off,
  ///   the provider asks for `duration,distance` only.
  /// - [userAgent] is sent as the `User-Agent` header. OSRM's demo server
  ///   asks apps to identify themselves; set your app's name. Pass null to
  ///   send none. The default is [defaultUserAgent], except on the web,
  ///   where it is null: a browser that honours the header treats it as
  ///   not CORS-safelisted and sends a preflight the server may not answer.
  ///   Setting it on the web is allowed but has that cost.
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the provider creates one and [close] closes it.
  OsrmRouteProvider({
    Uri? baseUrl,
    this.profile = 'driving',
    this.timeout = defaultTimeout,
    this.geometries = OsrmGeometries.geojson,
    this.userAgent = _platformUserAgent,
    this.speedLimits = false,
    http.Client? client,
  }) : baseUrl = baseUrl ?? demoServer,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// OSRM's public demo server, `https://router.project-osrm.org`.
  ///
  /// For testing only: it is rate limited (about one request per second),
  /// has no availability guarantee, serves only the `driving` profile, and
  /// sees the coordinates of every request.
  static final Uri demoServer = Uri.parse('https://router.project-osrm.org');

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = Duration(seconds: 12);

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = 'navigation_engine_osrm/0.1.0';

  /// [defaultUserAgent], or null on the web (no CORS preflight).
  static const String? _platformUserAgent =
      bool.fromEnvironment('dart.library.js_interop') ? null : defaultUserAgent;

  /// The angle either side of the vehicle's heading within which OSRM may
  /// start the route, in degrees (the range of `bearings`).
  static const int bearingRange = 45;

  /// The server, with any path prefix.
  final Uri baseUrl;

  /// The server's profile, such as `driving`.
  final String profile;

  /// How long a request may take, its body included, before it is aborted
  /// with an [OsrmTimeoutException].
  final Duration timeout;

  /// How the route geometry is requested.
  final OsrmGeometries geometries;

  /// The `User-Agent` header, or null to send none.
  final String? userAgent;

  /// Whether to ask for the speed limits (`maxspeed`, which needs
  /// `annotations=true`) and give them to each route, for its speed-limit
  /// sign and its estimates. False by default: mainline OSRM, the demo
  /// server included, sends no `maxspeed`; turn it on for a server that
  /// does.
  final bool speedLimits;

  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  /// The best route from [from] to [to], asked for without alternatives.
  ///
  /// [heading] (degrees clockwise from north) is sent as the start's
  /// `bearings`, so the route leaves the way the vehicle faces, within
  /// [bearingRange] degrees; a heading that is null or not finite sends
  /// none.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and an [OsrmException] when the request fails.
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await _request(from, to, heading: heading, alternatives: 0)).first;

  /// The best route, then up to [maxAlternatives] alternatives
  /// (`alternatives=N`), as [route] asks for one.
  ///
  /// The server may send fewer alternatives, and refuses more than its own
  /// limit (`TooBig`; 3 by default in OSRM). Throws [ArgumentError] when
  /// [maxAlternatives] is negative.
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
    return _request(from, to, heading: heading, alternatives: maxAlternatives);
  }

  /// Releases the HTTP client when the provider created it; an injected
  /// client is left open. The provider throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Future<List<NavRoute>> _request(
    GeoPoint from,
    GeoPoint to, {
    required double? heading,
    required int alternatives,
  }) async {
    if (_closed) throw StateError('OsrmRouteProvider is closed');
    final uri = _uri(from, to, heading: heading, alternatives: alternatives);
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..headers['Accept'] = 'application/json';
    if (userAgent case final agent?) request.headers['User-Agent'] = agent;

    // onTimeout rather than catching TimeoutException: a TimeoutException
    // the client itself throws passes through as it is.
    final response = await _send(request).timeout(
      timeout,
      onTimeout: () {
        abort.complete();
        throw OsrmTimeoutException(timeout);
      },
    );

    // Decoded once: UTF-8, then JSON.
    final text = _text(response);
    Object? json;
    String? jsonError;
    if (text != null) {
      try {
        json = jsonDecode(text);
      } on FormatException catch (e) {
        jsonError = e.message;
      }
    }
    final body = json is Map<String, Object?> ? json : null;
    if (response.statusCode != 200) {
      if (body case {'code': final String code} when code != 'Ok') {
        throw OsrmCodeException(
          code,
          serverMessage: _message(body),
          statusCode: response.statusCode,
        );
      }
      throw OsrmHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
        body: text ?? '',
      );
    }
    if (body == null) {
      final why = text == null
          ? 'the body is not UTF-8'
          : jsonError != null
          ? 'invalid JSON ($jsonError)'
          : 'got ${_kind(json)}';
      throw OsrmFormatException('the answer is not a JSON object: $why');
    }
    final code = body['code'];
    if (code is! String) {
      throw OsrmFormatException('code: expected a string, got ${_kind(code)}');
    }
    if (code != 'Ok') {
      throw OsrmCodeException(
        code,
        serverMessage: _message(body),
        statusCode: response.statusCode,
      );
    }
    final routes = _list(body['routes'], 'routes');
    if (routes.isEmpty) {
      throw const OsrmFormatException('routes: an Ok answer with no routes');
    }
    return [
      for (var i = 0; i < routes.length && i <= alternatives; i++)
        _parseRoute(routes[i], 'routes[$i]'),
    ];
  }

  Future<http.Response> _send(http.BaseRequest request) async =>
      http.Response.fromStream(await _client.send(request));

  Uri _uri(
    GeoPoint from,
    GeoPoint to, {
    required double? heading,
    required int alternatives,
  }) {
    final coordinates = '${_coordinate(from, 'from')};${_coordinate(to, 'to')}';
    // Built by hand: OSRM's documentation writes `,` and `;` as they are.
    final query = [
      if (baseUrl.query.isNotEmpty) baseUrl.query,
      'alternatives=${alternatives == 0 ? 'false' : alternatives}',
      'steps=true',
      'geometries=${geometries.name}',
      'overview=full',
      // OSRM's grammar has no `maxspeed` value (the demo server answers
      // InvalidQuery): only `true`, every annotation, returns it.
      'annotations=${speedLimits ? 'true' : 'duration,distance'}',
      if (heading != null && heading.isFinite)
        'bearings=${(heading % 360).round() % 360},$bearingRange;',
    ].join('&');
    return baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
        'route',
        'v1',
        profile,
        coordinates,
      ],
      query: query,
    );
  }

  /// The server's `message`, when it is a string.
  static String? _message(Map<String, Object?> body) =>
      switch (body['message']) {
        final String m => m,
        _ => null,
      };

  /// `lng,lat` with six decimals, OSRM's own precision.
  static String _coordinate(GeoPoint p, String name) {
    if (!p.lat.isFinite || !p.lng.isFinite) {
      throw ArgumentError.value(p, name, 'is not finite');
    }
    return '${_fixed(p.lng)},${_fixed(p.lat)}';
  }

  /// Six decimals, without `-0.000000` for a tiny negative value.
  static String _fixed(double v) {
    final s = v.toStringAsFixed(6);
    return s == '-0.000000' ? '0.000000' : s;
  }

  /// The body as UTF-8, or null when it is not.
  static String? _text(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return null;
    }
  }

  static String _kind(Object? json) => switch (json) {
    Map<Object?, Object?>() => 'an object',
    List<Object?>() => 'an array',
    String() => 'a string',
    num() => 'a number',
    bool() => 'a boolean',
    null => 'null',
    _ => 'a ${json.runtimeType}',
  };

  NavRoute _parseRoute(Object? json, String path) {
    final route = _map(json, path);
    final points = _points(route['geometry'], '$path.geometry');
    final legs = _list(route['legs'], '$path.legs');
    final seeds = <RouteStepSeed>[];
    final summaries = <String>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = _map(legs[l], legPath);
      final steps = _list(leg['steps'], '$legPath.steps');
      for (var s = 0; s < steps.length; s++) {
        seeds.add(_seed(steps[s], '$legPath.steps[$s]'));
      }
      final summary = _optionalString(leg['summary'], '$legPath.summary');
      if (summary != null && summary.isNotEmpty) summaries.add(summary);
    }
    final durations = _durations(legs, path);
    final limits = speedLimits ? _speedLimits(legs, path) : null;
    final distance = _number(route['distance'], '$path.distance');
    try {
      return NavRoute.fromPoints(
        points,
        steps: seeds,
        name: 'OSRM ${distance.round()} m',
        summary: summaries.isEmpty ? null : summaries.join(', '),
        segmentDurations: durations?.length == points.length - 1
            ? durations
            : null,
        segmentSpeedLimits: limits?.length == points.length - 1 ? limits : null,
      );
    } on ArgumentError catch (e) {
      throw OsrmFormatException('$path: ${e.message} (${e.name})');
    }
  }

  List<GeoPoint> _points(Object? json, String path) {
    final List<GeoPoint> points;
    switch (geometries) {
      case OsrmGeometries.geojson:
        final coordinates = _list(
          _map(json, path)['coordinates'],
          '$path.coordinates',
        );
        points = [
          for (var i = 0; i < coordinates.length; i++)
            _lngLat(coordinates[i], '$path.coordinates[$i]'),
        ];
      case OsrmGeometries.polyline6:
        if (json is! String) {
          throw OsrmFormatException('$path: expected a polyline6 string');
        }
        try {
          points = decodePolyline(json, precision: 6);
        } on FormatException catch (e) {
          throw OsrmFormatException('$path: ${e.message}');
        }
    }
    if (points.length < 2) {
      throw OsrmFormatException(
        '$path: ${points.length} point(s), a route needs at least 2',
      );
    }
    return points;
  }

  static RouteStepSeed _seed(Object? json, String path) {
    final step = _map(json, path);
    final maneuver = _map(step['maneuver'], '$path.maneuver');
    final type = _string(maneuver['type'], '$path.maneuver.type');
    final modifier = _optionalString(
      maneuver['modifier'],
      '$path.maneuver.modifier',
    );
    final name = _optionalString(step['name'], '$path.name') ?? '';
    final ref = _optionalString(step['ref'], '$path.ref') ?? '';
    return RouteStepSeed.atLocation(
      _lngLat(maneuver['location'], '$path.maneuver.location'),
      type: _type(type),
      modifier: _modifier(modifier),
      roadName: name.isNotEmpty ? name : ref,
      lanes: _lanes(step['intersections'], '$path.intersections', modifier),
    );
  }

  /// Each leg's `annotation.duration`, scaled so that the leg sums to its
  /// `duration`: the annotations leave out the time of the turns. Null
  /// when a leg has none, or when they sum to 0 for a leg that takes time.
  static List<double>? _durations(List<Object?> legs, String path) {
    final out = <double>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = _map(legs[l], legPath);
      final annotation = leg['annotation'];
      if (annotation == null) return null;
      final raw = _map(annotation, '$legPath.annotation')['duration'];
      if (raw == null) return null;
      final list = _list(raw, '$legPath.annotation.duration');
      final values = <double>[];
      for (var i = 0; i < list.length; i++) {
        final d = _number(list[i], '$legPath.annotation.duration[$i]');
        if (d < 0) {
          throw OsrmFormatException(
            '$legPath.annotation.duration[$i]: negative ($d)',
          );
        }
        values.add(d);
      }
      final total = _number(leg['duration'], '$legPath.duration');
      final sum = values.fold(0.0, (a, b) => a + b);
      if (sum == 0) {
        if (total > 0) return null;
        out.addAll(values);
        continue;
      }
      out.addAll(values.map((d) => d * total / sum));
    }
    return out;
  }

  /// Each leg's `annotation.maxspeed` in m/s: `{speed, unit}` in km/h or
  /// mph; `{unknown: true}`, `{none: true}` and speeds that are not
  /// positive are no limit (null). Null when a leg has none.
  static List<double?>? _speedLimits(List<Object?> legs, String path) {
    final out = <double?>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final annotation = _map(legs[l], legPath)['annotation'];
      if (annotation == null) return null;
      final raw = _map(annotation, '$legPath.annotation')['maxspeed'];
      if (raw == null) return null;
      final list = _list(raw, '$legPath.annotation.maxspeed');
      for (var i = 0; i < list.length; i++) {
        final entryPath = '$legPath.annotation.maxspeed[$i]';
        final entry = _map(list[i], entryPath);
        if (entry['speed'] == null) {
          out.add(null);
          continue;
        }
        final speed = _number(entry['speed'], '$entryPath.speed');
        final unit = _optionalString(entry['unit'], '$entryPath.unit');
        out.add(switch (unit) {
          _ when !(speed > 0) => null,
          'mph' => speed * 0.44704,
          _ => speed / 3.6,
        });
      }
    }
    return out;
  }

  /// The lanes of the step's first intersection, where its manoeuvre is.
  static List<Lane> _lanes(Object? json, String path, String? modifier) {
    if (json == null) return const [];
    final intersections = _list(json, path);
    if (intersections.isEmpty) return const [];
    final raw = _map(intersections.first, '$path[0]')['lanes'];
    if (raw == null) return const [];
    final lanes = _list(raw, '$path[0].lanes');
    final follow = _laneDirection(modifier);
    return [
      for (var i = 0; i < lanes.length; i++)
        _lane(lanes[i], '$path[0].lanes[$i]', follow),
    ];
  }

  static Lane _lane(Object? json, String path, LaneDirection? follow) {
    final lane = _map(json, path);
    final indications = lane['indications'] == null
        ? const <Object?>[]
        : _list(lane['indications'], '$path.indications');
    final directions = <LaneDirection>{
      for (var i = 0; i < indications.length; i++)
        ?_laneDirection(_string(indications[i], '$path.indications[$i]')),
    };
    // `none` (or nothing): no arrow painted, which drivers read as straight.
    if (directions.isEmpty) directions.add(LaneDirection.straight);
    final valid = lane['valid'] == true;
    final given = _laneDirection(
      _optionalString(lane['valid_indication'], '$path.valid_indication'),
    );
    final active = !valid
        ? null
        : given ??
              (follow != null && directions.contains(follow)
                  ? follow
                  : directions.first);
    return Lane(directions: directions, valid: valid, active: active);
  }

  static LaneDirection? _laneDirection(String? s) => switch (s) {
    'uturn' => LaneDirection.uturn,
    'sharp right' => LaneDirection.sharpRight,
    'right' => LaneDirection.right,
    'slight right' => LaneDirection.slightRight,
    'straight' => LaneDirection.straight,
    'slight left' => LaneDirection.slightLeft,
    'left' => LaneDirection.left,
    'sharp left' => LaneDirection.sharpLeft,
    _ => null,
  };

  /// OSRM's `maneuver.type`. OSRM asks clients to handle a type they do not
  /// know like `turn`.
  static ManeuverType _type(String t) => switch (t) {
    'depart' => ManeuverType.depart,
    'arrive' => ManeuverType.arrive,
    'new name' => ManeuverType.newName,
    'continue' || 'notification' || 'use lane' => ManeuverType.continueOn,
    'merge' => ManeuverType.merge,
    'on ramp' => ManeuverType.onRamp,
    'off ramp' => ManeuverType.offRamp,
    'fork' => ManeuverType.fork,
    'end of road' => ManeuverType.endOfRoad,
    'roundabout' || 'rotary' => ManeuverType.roundabout,
    'exit roundabout' || 'exit rotary' => ManeuverType.exitRoundabout,
    // `roundabout turn`: a small roundabout driven like an intersection.
    _ => ManeuverType.turn,
  };

  static ManeuverModifier _modifier(String? m) => switch (m) {
    'uturn' => ManeuverModifier.uturn,
    'sharp right' => ManeuverModifier.sharpRight,
    'right' => ManeuverModifier.right,
    'slight right' => ManeuverModifier.slightRight,
    'straight' => ManeuverModifier.straight,
    'slight left' => ManeuverModifier.slightLeft,
    'left' => ManeuverModifier.left,
    'sharp left' => ManeuverModifier.sharpLeft,
    _ => ManeuverModifier.none,
  };

  // Typed reads that name the field when the JSON is not what OSRM sends.

  static Map<String, Object?> _map(Object? json, String path) =>
      json is Map<String, Object?>
      ? json
      : throw OsrmFormatException(
          '$path: expected an object, got ${_kind(json)}',
        );

  static List<Object?> _list(Object? json, String path) => json is List<Object?>
      ? json
      : throw OsrmFormatException(
          '$path: expected an array, got ${_kind(json)}',
        );

  static double _number(Object? json, String path) => json is num
      ? json.toDouble()
      : throw OsrmFormatException(
          '$path: expected a number, got ${_kind(json)}',
        );

  static String _string(Object? json, String path) => json is String
      ? json
      : throw OsrmFormatException(
          '$path: expected a string, got ${_kind(json)}',
        );

  static String? _optionalString(Object? json, String path) =>
      json == null ? null : _string(json, path);

  static GeoPoint _lngLat(Object? json, String path) {
    final pair = _list(json, path);
    if (pair.length < 2) {
      throw OsrmFormatException('$path: expected [longitude, latitude]');
    }
    return GeoPoint(_number(pair[1], '$path[1]'), _number(pair[0], '$path[0]'));
  }
}
