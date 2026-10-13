import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_osrm/navigation_osrm.dart';

import '../web_service/mapbox_directions_exception.dart';
import '../web_service/mapbox_http.dart';

/// The Directions API's routing profile (`mapbox/{profile}`).
enum MapboxDirectionsProfile {
  /// Driving, with live and historic traffic: the default. Its routes
  /// avoid congestion and its durations include it.
  drivingTraffic('driving-traffic'),

  /// Driving, without live traffic.
  driving('driving'),

  /// Walking, on footpaths and sidewalks.
  walking('walking'),

  /// Cycling, on cycle lanes and roads suited to bicycles.
  cycling('cycling');

  const MapboxDirectionsProfile(this.id);

  /// The profile's name in the request path, such as `driving-traffic`.
  final String id;
}

/// Routes from Mapbox's [Directions API](https://docs.mapbox.com/api/navigation/directions/)
/// v5 (`GET /directions/v5/mapbox/{profile}/{coordinates}`).
///
/// ```dart
/// final router = MapboxDirectionsRouteProvider(
///   accessToken: 'pk....', // a public token (see the README)
///   language: 'vi',
/// );
/// final routes = await router.routes(from, to, heading: fix.heading);
/// // ...
/// router.close();
/// ```
///
/// Mapbox answers in OSRM's format, so [OsrmResponseParser] reads each
/// answer, as it reads OSRM's: each step becomes a [RouteStep] with its
/// manoeuvre type and modifier, its road name (falling back to its `ref`)
/// and its lanes (each valid lane following its `valid_indication`); the
/// `duration` annotations give the time of each segment, and, on the
/// driving profiles, the `maxspeed` annotations its speed limit (`km/h` or
/// `mph`; `unknown` and `none` are no limit). Mapbox documents `maxspeed`
/// for `driving` and `driving-traffic` only, so walking and cycling ask for
/// `duration,distance` and their routes have no speed limits. Mapbox's `voiceInstructions` and
/// `bannerInstructions` are ignored.
///
/// Failures throw a [MapboxDirectionsException]:
/// [MapboxDirectionsCodeException] for a Mapbox code (`NoRoute`,
/// `NoSegment`, `InvalidInput`, `ProfileNotFound`, …),
/// [MapboxDirectionsHttpException] for a 401 or 403, or an HTTP error
/// without a code (429, …), [MapboxDirectionsTimeoutException] after [timeout], and
/// [MapboxDirectionsFormatException] for an answer that is not Mapbox's
/// JSON (its `cause` is the parser's `OsrmFormatException`). Transport
/// failures arrive as the `http` client throws them, the token in their
/// URL and message replaced by `REDACTED`.
class MapboxDirectionsRouteProvider extends RouteProvider {
  /// A provider that asks [baseUrl] (by default [defaultBaseUrl]) for
  /// [profile] routes.
  ///
  /// - [accessToken] is sent as the `access_token` query parameter; pass
  ///   null to send none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, such as
  ///   `https://example.com/mapbox/`, to which `directions/v5/...` is
  ///   appended, and query parameters, which are kept.
  /// - [profile] is the routing profile, [MapboxDirectionsProfile.drivingTraffic]
  ///   by default.
  /// - [geometries] is how the route geometry is sent: a precision-6
  ///   polyline by default, compact and exact; GeoJSON is about three
  ///   times larger.
  /// - [language] is the language of the turn-by-turn instruction text
  ///   Mapbox writes (an IETF tag such as `vi` or `en`); null sends none
  ///   (English). This package does not read that text (the engine words
  ///   its own guidance), so the option leaves the returned routes as
  ///   they are; it is kept for parity with Mapbox's API.
  /// - [alternatives] (true by default) lets [routes] ask for
  ///   alternatives; false never asks for them.
  /// - [headers] are added to every request (a proxy's token, say), after
  ///   `Accept` and `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none.
  ///   The default is [defaultUserAgent], except on the web, where it is
  ///   null: a browser that honours the header would send a CORS preflight
  ///   the server may not answer.
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the provider creates one and [close] closes it.
  MapboxDirectionsRouteProvider({
    required String? accessToken,
    Uri? baseUrl,
    this.profile = MapboxDirectionsProfile.drivingTraffic,
    this.geometries = OsrmGeometries.polyline6,
    this.language,
    this.alternatives = true,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = mapboxPlatformUserAgent,
    http.Client? client,
  }) : _http = MapboxHttp(
         owner: 'MapboxDirectionsRouteProvider',
         accessToken: accessToken,
         baseUrl: baseUrl,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       );

  /// Mapbox's API root, `https://api.mapbox.com`.
  static final Uri defaultBaseUrl = mapboxApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = mapboxDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = mapboxUserAgent;

  /// The angle either side of the vehicle's heading within which Mapbox
  /// may start the route, in degrees (the range of `bearings`).
  static const int bearingRange = 45;

  /// The routing profile.
  final MapboxDirectionsProfile profile;

  /// How the route geometry is requested.
  final OsrmGeometries geometries;

  /// The language of Mapbox's instruction text (`language=`), which this
  /// package does not read, or null for Mapbox's default, English.
  final String? language;

  /// Whether [routes] may ask for alternatives.
  final bool alternatives;

  final MapboxHttp _http;

  /// The API root, with any path prefix and query parameters.
  Uri get baseUrl => _http.baseUrl;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included, before it is aborted
  /// with a [MapboxDirectionsTimeoutException].
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The best route from [from] to [to], asked for without alternatives.
  ///
  /// [heading] (degrees clockwise from north) is sent as the origin's
  /// `bearings`, so the route leaves the way the vehicle faces, within
  /// [bearingRange] degrees; the destination has none. A heading that is
  /// null or not finite sends no `bearings`.
  ///
  /// A `NavigationSession` calls this on every reroute, and may do so every
  /// `rerouteInterval` (10 s by default) while the vehicle stays off the
  /// route; a `NavigationFlowController` adds a [routes] call after each
  /// one unless built with `fetchAlternatesOnReroute: false`. Each is a
  /// billed request.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [MapboxDirectionsException] when the request
  /// fails.
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async =>
      (await _request(from, to, heading: heading, maxAlternatives: 0)).first;

  /// The best route, then up to [maxAlternatives] alternatives, as [route]
  /// asks for one.
  ///
  /// It sends `alternatives=true` when [maxAlternatives] is positive and
  /// [alternatives] allows it; Mapbox then sends up to two alternatives.
  /// Throws [ArgumentError] when [maxAlternatives] is negative.
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

  /// Whether [profile] has speed limits: Mapbox sends `maxspeed` on the
  /// driving profiles only.
  bool get _speedLimits => switch (profile) {
    MapboxDirectionsProfile.drivingTraffic ||
    MapboxDirectionsProfile.driving => true,
    MapboxDirectionsProfile.walking || MapboxDirectionsProfile.cycling => false,
  };

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
      [
        'directions',
        'v5',
        'mapbox',
        profile.id,
        '${lonLat(from)};${lonLat(to)}',
      ],
      [
        ('alternatives', '${maxAlternatives > 0}'),
        ('steps', 'true'),
        ('geometries', geometries.name),
        ('overview', 'full'),
        (
          'annotations',
          _speedLimits ? 'duration,distance,maxspeed' : 'duration,distance',
        ),
        if (heading != null && heading.isFinite)
          ('bearings', '${(heading % 360).round() % 360},$bearingRange;'),
        if (language case final language?) ('language', language),
      ],
    );
    final code = json['code'];
    if (code is! String) {
      throw MapboxDirectionsFormatException(
        'code: expected a string, got ${kindOf(code)}',
      );
    }
    if (code != 'Ok') throw _http.codeException(json, code, 200);
    try {
      return OsrmResponseParser.parse(
        json,
        geometries: geometries,
        speedLimits: _speedLimits,
        maxAlternatives: maxAlternatives,
        providerName: 'Mapbox',
      );
    } on OsrmFormatException catch (e) {
      throw MapboxDirectionsFormatException(
        _http.scrubbed(e.message)!,
        cause: e,
      );
    }
  }
}
