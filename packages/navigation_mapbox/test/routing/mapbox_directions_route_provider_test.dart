import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_mapbox/navigation_mapbox.dart';
import 'package:navigation_osrm/navigation_osrm.dart' show OsrmFormatException;

// Fixtures (test/routing/fixtures), all hand-written in the shape of the
// Directions API v5 documentation
// (https://docs.mapbox.com/api/navigation/directions/); none was recorded,
// and none holds a token (the uuids are redacted):
// - directions_alternatives.json: two routes in Hanoi with polyline6
//   geometry, as the provider asks for them. The first has a turn with
//   Mapbox lanes (`active`, `valid_indication`), a step named only by its
//   `ref`, `voiceInstructions` and `bannerInstructions`, and `maxspeed`
//   annotations in km/h, mph, `unknown` and `none`. The second has no
//   `maxspeed`.
// - directions_no_route.json, directions_invalid_input.json,
//   directions_profile_not_found.json: error bodies with a `code` and a
//   `message`.
// - error_unauthorized.json: the `{"message"}` body of an HTTP 401.

String fixture(String name) =>
    File('test/routing/fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

/// The routes of [json], to edit in place.
List<Map<String, Object?>> routesOf(Map<String, Object?> json) =>
    (json['routes']! as List<Object?>).cast<Map<String, Object?>>();

const a = GeoPoint(21.028772, 105.852379);
const b = GeoPoint(21.04, 105.844);

/// A fake token: requests must carry it, messages must not.
const token = 'test-token';

/// A provider whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({MapboxDirectionsRouteProvider provider, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? accessToken = token,
  Uri? baseUrl,
  MapboxDirectionsProfile profile = MapboxDirectionsProfile.drivingTraffic,
  OsrmGeometries geometries = OsrmGeometries.polyline6,
  String? language,
  bool alternatives = true,
  Map<String, String> headers = const {},
  String? userAgent = MapboxDirectionsRouteProvider.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final provider = MapboxDirectionsRouteProvider(
    accessToken: accessToken,
    baseUrl: baseUrl,
    profile: profile,
    geometries: geometries,
    language: language,
    alternatives: alternatives,
    headers: headers,
    userAgent: userAgent,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (provider: provider, requests: requests);
}

/// A client that forwards to [inner] and records [close].
class RecordingClient extends http.BaseClient {
  RecordingClient(this.inner);

  final http.Client inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() => closed = true;
}

typedef StepView = (ManeuverType, ManeuverModifier, String);

List<StepView> view(NavRoute r) => [
  for (final s in r.steps) (s.type, s.modifier, s.roadName),
];

/// The speed limit in the middle of each segment of [r], in m/s.
List<double?> segmentLimits(NavRoute r) => [
  for (var i = 0; i + 1 < r.points.length; i++)
    r.speedLimitAt((r.distanceAtVertex(i) + r.distanceAtVertex(i + 1)) / 2),
];

void main() {
  group('request', () {
    test('route() asks Directions v5 for one driving-traffic route, lon,lat, '
        'with steps, polyline6, the full overview, the annotations and the '
        'token last', () async {
      final s = serve(fixture('directions_alternatives.json'));
      await s.provider.route(a, b);
      expect(s.requests, hasLength(1));
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.scheme, 'https');
      expect(req.url.host, 'api.mapbox.com');
      expect(
        req.url.path,
        '/directions/v5/mapbox/driving-traffic/'
        '105.852379,21.028772;105.844,21.04',
      );
      expect(
        req.url.query,
        'alternatives=false&steps=true&geometries=polyline6&overview=full'
        '&annotations=duration,distance,maxspeed&access_token=test-token',
      );
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], 'navigation_mapbox/0.1.0');
    });

    test('routes() asks for alternatives; the heading is the origin\'s '
        'bearing, with none for the destination', () async {
      final s = serve(fixture('directions_alternatives.json'));
      await s.provider.routes(a, b, heading: 90.4);
      expect(s.requests.single.url.query, contains('alternatives=true&'));
      expect(s.requests.single.url.query, contains('&bearings=90,45;&'));
      expect(s.requests.single.url.queryParameters['bearings'], '90,45;');
    });

    test('the heading is normalised to 0..359, and one that is not finite '
        'sends no bearings', () async {
      final s = serve(fixture('directions_alternatives.json'));
      for (final heading in [
        359.6,
        -90.0,
        720.0,
        double.nan,
        double.infinity,
      ]) {
        await s.provider.route(a, b, heading: heading);
      }
      expect(
        [for (final r in s.requests) r.url.queryParameters['bearings']],
        ['0,45;', '270,45;', '0,45;', null, null],
      );
    });

    test('each profile is sent by its id', () async {
      final ids = <String>[];
      for (final profile in MapboxDirectionsProfile.values) {
        final s = serve(
          fixture('directions_alternatives.json'),
          profile: profile,
        );
        await s.provider.route(a, b);
        ids.add(s.requests.single.url.pathSegments[3]);
        expect(profile.id, ids.last);
      }
      expect(ids, ['driving-traffic', 'driving', 'walking', 'cycling']);
      expect(MapboxDirectionsProfile.values, hasLength(4));
      expect(
        MapboxDirectionsRouteProvider(accessToken: token).profile,
        MapboxDirectionsProfile.drivingTraffic,
      );
    });

    test('maxspeed is asked for on the driving profiles only', () async {
      final annotations = <MapboxDirectionsProfile, String?>{};
      for (final profile in MapboxDirectionsProfile.values) {
        final s = serve(
          fixture('directions_alternatives.json'),
          profile: profile,
        );
        await s.provider.route(a, b);
        annotations[profile] =
            s.requests.single.url.queryParameters['annotations'];
        expect(
          s.requests.single.url.query,
          contains('&annotations=${annotations[profile]}&'),
        );
      }
      expect(annotations, {
        MapboxDirectionsProfile.drivingTraffic: 'duration,distance,maxspeed',
        MapboxDirectionsProfile.driving: 'duration,distance,maxspeed',
        MapboxDirectionsProfile.walking: 'duration,distance',
        MapboxDirectionsProfile.cycling: 'duration,distance',
      });
    });

    test('walking and cycling routes have no speed limits', () async {
      final r = await serve(
        fixture('directions_alternatives.json'),
        profile: MapboxDirectionsProfile.walking,
      ).provider.route(a, b);
      expect(segmentLimits(r), everyElement(isNull));
    });

    test('geometries and language are sent', () async {
      final json = fixtureJson('directions_alternatives.json');
      for (final r in routesOf(json)) {
        r['geometry'] = {
          'type': 'LineString',
          'coordinates': [
            for (final p in decodePolyline(
              r['geometry']! as String,
              precision: 6,
            ))
              [p.lng, p.lat],
          ],
        };
      }
      final s = serve(
        jsonEncode(json),
        geometries: OsrmGeometries.geojson,
        language: 'vi',
      );
      await s.provider.route(a, b);
      final params = s.requests.single.url.queryParameters;
      expect(params['geometries'], 'geojson');
      expect(params['language'], 'vi');
      expect(
        s.requests.single.url.query,
        endsWith('&language=vi&access_token=test-token'),
      );
    });

    test('coordinates keep their full precision, with no exponent and no '
        '-0', () async {
      final s = serve(fixture('directions_alternatives.json'));
      await s.provider.route(
        const GeoPoint(21.0287721234567, 105.852379123456),
        const GeoPoint(-0.0, 1e-7),
      );
      await s.provider.route(const GeoPoint(10, -106), const GeoPoint(0, 0));
      expect(
        [for (final r in s.requests) r.url.pathSegments.last],
        ['105.852379123456,21.0287721234567;0.0000001,0', '-106,10;0,0'],
      );
    });

    test('a coordinate that is not finite throws before any request', () async {
      final s = serve(fixture('directions_alternatives.json'));
      await expectLater(
        s.provider.route(const GeoPoint(double.nan, 105), b),
        throwsArgumentError,
      );
      await expectLater(
        s.provider.routes(a, const GeoPoint(21, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('a null accessToken sends none, for a proxy that adds it', () async {
      final s = serve(
        fixture('directions_alternatives.json'),
        accessToken: null,
      );
      await s.provider.route(a, b);
      expect(s.requests.single.url.query, isNot(contains('access_token')));
      expect(s.requests.single.url.query, endsWith('maxspeed'));
    });

    test('the token is encoded', () async {
      final s = serve(
        fixture('directions_alternatives.json'),
        accessToken: 'pk.a/b+c=',
      );
      await s.provider.route(a, b);
      expect(
        s.requests.single.url.query,
        endsWith('&access_token=pk.a%2Fb%2Bc%3D'),
      );
      expect(
        s.requests.single.url.queryParameters['access_token'],
        'pk.a/b+c=',
      );
    });

    test('baseUrl keeps its path and query parameters', () async {
      final s = serve(
        fixture('directions_alternatives.json'),
        accessToken: null,
        baseUrl: Uri.parse('https://proxy.example.com/mapbox/?tenant=a'),
      );
      await s.provider.route(a, b);
      final url = s.requests.single.url;
      expect(url.host, 'proxy.example.com');
      expect(
        url.path,
        '/mapbox/directions/v5/mapbox/driving-traffic/'
        '105.852379,21.028772;105.844,21.04',
      );
      expect(url.query, startsWith('tenant=a&alternatives=false&'));
    });

    test('extra headers are sent, and may replace the defaults', () async {
      final s = serve(
        fixture('directions_alternatives.json'),
        headers: {'X-Proxy-Token': 'p', 'Accept': 'application/geo+json'},
      );
      await s.provider.route(a, b);
      final headers = s.requests.single.headers;
      expect(headers['X-Proxy-Token'], 'p');
      expect(headers['Accept'], 'application/geo+json');
      expect(s.provider.headers, {
        'X-Proxy-Token': 'p',
        'Accept': 'application/geo+json',
      });
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('directions_alternatives.json'), userAgent: null);
      await s.provider.route(a, b);
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final p = MapboxDirectionsRouteProvider(accessToken: token);
      expect(p.baseUrl, Uri.parse('https://api.mapbox.com'));
      expect(MapboxDirectionsRouteProvider.defaultBaseUrl, p.baseUrl);
      expect(p.profile, MapboxDirectionsProfile.drivingTraffic);
      expect(p.geometries, OsrmGeometries.polyline6);
      expect(p.language, isNull);
      expect(p.alternatives, isTrue);
      expect(p.headers, isEmpty);
      expect(p.timeout, const Duration(seconds: 12));
      expect(p.userAgent, 'navigation_mapbox/0.1.0');
      expect(MapboxDirectionsRouteProvider.bearingRange, 45);
      p.close();
    });
  });

  group('alternatives', () {
    test('routes() returns every route, best first', () async {
      final s = serve(fixture('directions_alternatives.json'));
      final routes = await s.provider.routes(a, b);
      expect(
        [for (final r in routes) r.name],
        ['Mapbox 1571 m', 'Mapbox 2105 m'],
      );
      expect(routes[1].summary, 'Trần Quang Khải');
    });

    test('route() and routes() keep at most maxAlternatives + 1', () async {
      final s = serve(fixture('directions_alternatives.json'));
      expect((await s.provider.route(a, b)).name, 'Mapbox 1571 m');
      expect(await s.provider.routes(a, b, maxAlternatives: 0), hasLength(1));
      expect(await s.provider.routes(a, b, maxAlternatives: 1), hasLength(2));
      expect(
        [for (final r in s.requests) r.url.queryParameters['alternatives']],
        ['false', 'false', 'true'],
      );
    });

    test('alternatives: false never asks for them', () async {
      final s = serve(
        fixture('directions_alternatives.json'),
        alternatives: false,
      );
      expect(await s.provider.routes(a, b), hasLength(1));
      expect(s.requests.single.url.queryParameters['alternatives'], 'false');
    });

    test('a negative maxAlternatives throws before any request', () async {
      final s = serve(fixture('directions_alternatives.json'));
      await expectLater(
        s.provider.routes(a, b, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('routes', () {
    test('steps, manoeuvres, road names (the ref when there is no name), '
        'summary and name, through the OSRM parser', () async {
      final r = await serve(
        fixture('directions_alternatives.json'),
      ).provider.route(a, b);
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Đinh Tiên Hoàng'),
        (ManeuverType.turn, ManeuverModifier.left, 'Lê Thái Tổ'),
        (ManeuverType.endOfRoad, ManeuverModifier.right, 'QL1A'),
        (ManeuverType.arrive, ManeuverModifier.none, 'QL1A'),
      ]);
      expect(r.points, hasLength(6));
      expect(r.points.first, const GeoPoint(21.028772, 105.852379));
      expect(r.points.last, const GeoPoint(21.04, 105.844));
      expect(r.summary, 'Đinh Tiên Hoàng, Lê Thái Tổ');
      expect(r.name, 'Mapbox 1571 m');
    });

    test('lanes: valid lanes follow their valid_indication', () async {
      final r = await serve(
        fixture('directions_alternatives.json'),
      ).provider.route(a, b);
      expect(r.steps[0].lanes, isEmpty);
      expect(r.steps[1].lanes, const [
        Lane(
          directions: {LaneDirection.left},
          valid: true,
          active: LaneDirection.left,
        ),
        Lane(
          directions: {LaneDirection.straight, LaneDirection.left},
          valid: true,
          active: LaneDirection.left,
        ),
        Lane(directions: {LaneDirection.straight}),
      ]);
    });

    test('durations: the duration annotations, scaled to the leg', () async {
      final r = await serve(
        fixture('directions_alternatives.json'),
      ).provider.route(a, b);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(84, 1e-9));
      // 10 of the annotations' 78 s, scaled to the leg's 84 s.
      expect(r.durationAt(r.distanceAtVertex(1)), closeTo(10 * 84 / 78, 1e-9));
    });

    test('speed limits from maxspeed: km/h and mph in m/s, unknown and none '
        'as no limit', () async {
      final routes = await serve(
        fixture('directions_alternatives.json'),
      ).provider.routes(a, b);
      final limits = segmentLimits(routes[0]);
      expect(limits, hasLength(5));
      expect(limits[0], closeTo(50 / 3.6, 1e-9));
      expect(limits[1], closeTo(50 / 3.6, 1e-9));
      expect(limits[2], isNull); // {unknown: true}
      expect(limits[3], isNull); // {none: true}
      expect(limits[4], closeTo(30 * 0.44704, 1e-9)); // 30 mph
      // The alternative has no maxspeed annotation.
      expect(segmentLimits(routes[1]), [null, null]);
    });

    test('geojson geometry reads the same route', () async {
      final json = fixtureJson('directions_alternatives.json');
      for (final r in routesOf(json)) {
        r['geometry'] = {
          'type': 'LineString',
          'coordinates': [
            for (final p in decodePolyline(
              r['geometry']! as String,
              precision: 6,
            ))
              [p.lng, p.lat],
          ],
        };
      }
      final polyline = await serve(
        fixture('directions_alternatives.json'),
      ).provider.route(a, b);
      final geojson = await serve(
        jsonEncode(json),
        geometries: OsrmGeometries.geojson,
      ).provider.route(a, b);
      expect(geojson.points, polyline.points);
      expect(view(geojson), view(polyline));
    });
  });

  group('errors', () {
    test(
      'NoRoute with HTTP 200 throws MapboxDirectionsCodeException',
      () async {
        final s = serve(fixture('directions_no_route.json'));
        final e = await _thrown<MapboxDirectionsCodeException>(
          s.provider.route(a, b),
        );
        expect(e, isA<MapboxDirectionsException>());
        expect(e.code, 'NoRoute');
        expect(e.serverMessage, 'No route found for the given coordinates.');
        expect(e.statusCode, 200);
        expect(
          e.toString(),
          'MapboxDirectionsCodeException: Mapbox NoRoute: no route between the '
          'points (No route found for the given coordinates.) [HTTP 200]',
        );
      },
    );

    test('the codes and their HTTP statuses', () async {
      final cases = [
        (
          fixture('directions_invalid_input.json'),
          422,
          'Mapbox InvalidInput: the server rejected the request (bearings '
              'must have the same number of values as coordinates) [HTTP 422]',
        ),
        (
          fixture('directions_profile_not_found.json'),
          404,
          'Mapbox ProfileNotFound: the profile does not exist (Profile not '
              'found) [HTTP 404]',
        ),
        (
          jsonEncode({'code': 'NoSegment', 'message': ''}),
          200,
          'Mapbox NoSegment: a point is not near a road the profile can use '
              '[HTTP 200]',
        ),
        (
          jsonEncode({'code': 'Unexpected', 'message': 'something'}),
          400,
          'Mapbox Unexpected: the server reported an error (something) '
              '[HTTP 400]',
        ),
      ];
      for (final (body, status, message) in cases) {
        final e = await _thrown<MapboxDirectionsCodeException>(
          serve(body, status: status).provider.route(a, b),
        );
        expect(e.statusCode, status);
        expect(e.message, message);
      }
    });

    test('an HTTP error without a code throws MapboxDirectionsHttpException, '
        'with a hint', () async {
      final e = await _thrown<MapboxDirectionsHttpException>(
        serve(
          fixture('error_unauthorized.json'),
          status: 401,
        ).provider.route(a, b),
      );
      expect(e, isA<MapboxDirectionsException>());
      expect(e.statusCode, 401);
      expect(
        e.message,
        'Mapbox request failed with HTTP 401 (the access token is missing or '
        'not valid): {"message":"Not Authorized - Invalid Token"}',
      );
      const hints = {
        403:
            '(the token is not allowed: check its URL restrictions and the '
            'account)',
        422: '(the request is not valid)',
        429: '(rate limit reached)',
        502: 'Bad Gateway',
      };
      for (final MapEntry(key: status, value: hint) in hints.entries) {
        final e = await _thrown<MapboxDirectionsHttpException>(
          serve(
            '<html>Bad Gateway</html>',
            status: status,
          ).provider.route(a, b),
        );
        expect(e.statusCode, status);
        expect(
          e.message,
          startsWith('Mapbox request failed with HTTP $status'),
        );
        expect(e.message, contains(hint), reason: '$status');
        expect(e.message, endsWith(': <html>Bad Gateway</html>'));
      }
    });

    test('a 401 or 403 is a MapboxDirectionsHttpException even when its '
        'body has a code', () async {
      final unauthorized = jsonEncode({
        'message': 'Not Authorized - Invalid Token',
        'code': 'InvalidToken',
      });
      final e = await _thrown<MapboxDirectionsHttpException>(
        serve(unauthorized, status: 401).provider.route(a, b),
      );
      expect(e.statusCode, 401);
      expect(
        e.message,
        'Mapbox request failed with HTTP 401 (the access token is missing or '
        'not valid): {"message":"Not Authorized - Invalid Token","code":'
        '"InvalidToken"}',
      );
      final forbidden = await _thrown<MapboxDirectionsHttpException>(
        serve(
          jsonEncode({'message': 'Forbidden', 'code': 'Forbidden'}),
          status: 403,
        ).provider.route(a, b),
      );
      expect(forbidden.statusCode, 403);
      expect(
        forbidden.message,
        endsWith(': {"message":"Forbidden","code":"Forbidden"}'),
      );
    });

    test('a long body is cut, and not inside a character', () async {
      final e = await _thrown<MapboxDirectionsHttpException>(
        serve('${'x' * 199}😀😀', status: 500).provider.route(a, b),
      );
      expect(e.message, endsWith(': ${'x' * 199}😀…'));
    });

    test('an answer that is not a JSON object throws '
        'MapboxDirectionsFormatException', () async {
      final cases = {
        'not json': 'the answer is not a JSON object: invalid JSON',
        '[1]': 'the answer is not a JSON object: got an array',
        '{"code": 1}': 'code: expected a string, got a number',
        '{"routes": []}': 'code: expected a string, got null',
      };
      for (final MapEntry(key: body, value: message) in cases.entries) {
        final e = await _thrown<MapboxDirectionsFormatException>(
          serve(body).provider.route(a, b),
        );
        expect(e.message, startsWith(message), reason: body);
        expect(e.statusCode, isNull);
      }
      final e = await _thrown<MapboxDirectionsFormatException>(
        MapboxDirectionsRouteProvider(
          accessToken: token,
          client: MockClient(
            (_) async => http.Response.bytes([0x7b, 0xff, 0x7d], 200),
          ),
        ).route(a, b),
      );
      expect(
        e.message,
        'the answer is not a JSON object: the body is not UTF-8',
      );
    });

    test('a route of an unexpected shape: the OSRM parser\'s error, as a '
        'MapboxDirectionsFormatException that keeps it as its cause', () async {
      Future<MapboxDirectionsFormatException> thrown(
        void Function(Map<String, Object?> json) edit,
      ) async {
        final json = fixtureJson('directions_alternatives.json');
        edit(json);
        return _thrown<MapboxDirectionsFormatException>(
          serve(jsonEncode(json)).provider.routes(a, b),
        );
      }

      final cases = {
        'routes: an Ok answer with no routes': (Map<String, Object?> j) =>
            j['routes'] = <Object?>[],
        'routes[1].legs: expected an array, got null':
            (Map<String, Object?> j) => routesOf(j)[1].remove('legs'),
        'routes[0].geometry: expected a polyline6 string':
            (Map<String, Object?> j) => routesOf(j)[0]['geometry'] = 3,
        'routes[0].geometry: the polyline ends inside a value':
            (Map<String, Object?> j) => routesOf(j)[0]['geometry'] = 'gynbg@',
      };
      for (final MapEntry(key: message, value: edit) in cases.entries) {
        final e = await thrown(edit);
        expect(e.message, message);
        expect(
          e.cause,
          isA<OsrmFormatException>().having(
            (c) => c.message,
            'message',
            message,
          ),
        );
        expect(e.toString(), 'MapboxDirectionsFormatException: $message');
      }
    });
  });

  group('timeout', () {
    test('a server that never answers times out and the request is '
        'aborted', () async {
      final requests = <http.BaseRequest>[];
      final p = MapboxDirectionsRouteProvider(
        accessToken: token,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((req, _) {
          requests.add(req);
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final e = await _thrown<MapboxDirectionsTimeoutException>(p.routes(a, b));
      expect(e, isA<MapboxDirectionsException>());
      expect(e, isA<TimeoutException>());
      expect(e.timeout, const Duration(milliseconds: 50));
      expect(e.duration, const Duration(milliseconds: 50));
      expect(e.message, 'Mapbox request timed out after 50 ms');
      final trigger = (requests.single as http.Abortable).abortTrigger;
      expect(trigger, isNotNull);
      await trigger!.timeout(const Duration(seconds: 1));
    });

    test('a TimeoutException from the client is not reported as the '
        "provider's own timeout", () async {
      final p = MapboxDirectionsRouteProvider(
        accessToken: token,
        client: MockClient((_) async => throw TimeoutException('inner')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<TimeoutException>()
              .having(
                (e) => e,
                'type',
                isNot(isA<MapboxDirectionsTimeoutException>()),
              )
              .having((e) => e.message, 'message', 'inner'),
        ),
      );
    });

    test('a body that stalls times out too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final p = MapboxDirectionsRouteProvider(
        accessToken: token,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((_, _) async {
          body.add(utf8.encode('{"code":'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      await _thrown<MapboxDirectionsTimeoutException>(p.route(a, b));
    });
  });

  group('close', () {
    MockClient answering() => MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(fixture('directions_alternatives.json')),
        200,
      ),
    );

    test('close() leaves an injected client open', () async {
      final client = RecordingClient(answering());
      final p = MapboxDirectionsRouteProvider(
        accessToken: token,
        client: client,
      );
      await p.route(a, b);
      p.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the provider created', () async {
      final created = RecordingClient(answering());
      final p = http.runWithClient(
        () => MapboxDirectionsRouteProvider(accessToken: token),
        () => created,
      );
      await p.route(a, b);
      expect(created.closed, isFalse);
      p.close();
      expect(created.closed, isTrue);
      p.close();
    });

    test('a closed provider throws StateError', () async {
      final s = serve(fixture('directions_alternatives.json'));
      s.provider.close();
      await expectLater(s.provider.route(a, b), throwsStateError);
      await expectLater(s.provider.routes(a, b), throwsStateError);
      expect(s.requests, isEmpty);
    });
  });
}

/// The error [future] fails with, which must be a [T].
Future<T> _thrown<T extends Object>(Future<Object?> future) async {
  try {
    await future;
  } on T catch (e) {
    return e;
  }
  fail('expected a $T');
}
