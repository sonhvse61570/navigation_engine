import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_goong/navigation_engine_goong.dart';
import 'package:test/test.dart';

// Fixtures (test/fixtures), all hand-written in the shape of Goong's
// direction v2 documentation
// (https://help.goong.io/kb/rest-api-v2/directions-rest-api-v2/directions-v2/),
// which is Google Directions' shape; none was recorded, and none holds a key
// (the place ids are redacted):
// - direction_alternatives.json: two routes in Hanoi from Trần Cung. The
//   first has Goong's own forms (a first step "right", plain Vietnamese
//   instructions, "slight right", a final zero-length arrival step with an
//   empty maneuver) mixed with Google's (turn-right, keep-left,
//   roundabout-right, `<b>` tags, a `<div>` note, an entity). The second is
//   Google-like: no maneuver on the first step, and no arrival step.
// - direction_zero_results.json, direction_invalid_request.json: Google's
//   `status` / `error_message` error shape.
// - error_api_key_missing.json: the `{"error": {"code", "message"}}` shape
//   Goong's servers answer a request without a key with.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

/// The routes of [json], to edit in place.
List<Map<String, Object?>> routesOf(Map<String, Object?> json) =>
    (json['routes']! as List<Object?>).cast<Map<String, Object?>>();

/// The steps of the first leg of the first route of [json], to edit in
/// place.
List<Map<String, Object?>> stepsOf(Map<String, Object?> json) =>
    (((routesOf(json).first['legs']! as List<Object?>).first!
                as Map<String, Object?>)['steps']!
            as List<Object?>)
        .cast<Map<String, Object?>>();

const a = GeoPoint(21.04663, 105.79022);
const b = GeoPoint(21.05671, 105.79017);

/// A fake key: requests must carry it, messages must not.
const key = 'test-api-key';

/// A provider whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({GoongRouteProvider provider, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? apiKey = key,
  Uri? baseUrl,
  GoongVehicle vehicle = GoongVehicle.car,
  Map<String, String> headers = const {},
  String? userAgent = GoongRouteProvider.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final provider = GoongRouteProvider(
    apiKey: apiKey,
    baseUrl: baseUrl,
    vehicle: vehicle,
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

/// The seconds of each segment of [r].
List<double> segmentSeconds(NavRoute r) => [
  for (var i = 0; i + 1 < r.points.length; i++)
    r.durationAt(r.distanceAtVertex(i + 1)) -
        r.durationAt(r.distanceAtVertex(i)),
];

/// Expects each segment of [r] to take a time in proportion to its length.
void expectSpreadByLength(NavRoute r) {
  final seconds = segmentSeconds(r);
  final total = [
    for (var i = 0; i + 1 < r.points.length; i++)
      distanceBetween(r.points[i], r.points[i + 1]),
  ].fold(0.0, (a, b) => a + b);
  for (var i = 0; i < seconds.length; i++) {
    final share = distanceBetween(r.points[i], r.points[i + 1]);
    expect(seconds[i], closeTo(r.duration * share / total, 1e-6));
  }
}

/// Google's polyline algorithm at precision 5, for hand-made steps.
String encode(List<GeoPoint> points) {
  final out = StringBuffer();
  var lastLat = 0;
  var lastLng = 0;
  void value(int v) {
    var s = v < 0 ? ~(v << 1) : v << 1;
    while (s >= 0x20) {
      out.writeCharCode((0x20 | (s & 0x1f)) + 63);
      s >>= 5;
    }
    out.writeCharCode(s + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lng = (p.lng * 1e5).round();
    value(lat - lastLat);
    value(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return out.toString();
}

/// A step over [points], [seconds] long, with [maneuver] (absent when
/// null) and [html].
Map<String, Object?> step(
  List<GeoPoint> points, {
  num seconds = 10,
  String? maneuver,
  String html = '',
}) => {
  'distance': {'text': '', 'value': 100},
  'duration': {'text': '', 'value': seconds},
  'html_instructions': html,
  'maneuver': ?maneuver,
  'polyline': {'points': encode(points)},
  'travel_mode': 'DRIVING',
};

/// The [i]th point of a straight line heading north-east, built as the
/// decoder builds it (an integer over 1e5), so that it compares equal.
GeoPoint ne(int i) =>
    GeoPoint((2100000 + i * 100) / 1e5, (10580000 + i * 100) / 1e5);

/// An OK answer with one route of one leg made of [steps].
String okBody(List<Map<String, Object?>> steps, {String summary = ''}) =>
    jsonEncode({
      'geocoded_waypoints': <Object?>[],
      'routes': [
        {
          'legs': [
            {
              'distance': {'text': '', 'value': 1000},
              'duration': {'text': '', 'value': 0},
              'steps': steps,
            },
          ],
          'overview_polyline': {'points': ''},
          'summary': summary,
        },
      ],
    });

void main() {
  group('request', () {
    test('route() asks direction v2 for one route from origin to '
        'destination, lat,lng, with the key last', () async {
      final s = serve(fixture('direction_alternatives.json'));
      await s.provider.route(a, b);
      expect(s.requests, hasLength(1));
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.scheme, 'https');
      expect(req.url.host, 'rsapi.goong.io');
      expect(req.url.path, '/v2/direction');
      expect(req.url.queryParametersAll, {
        'origin': ['21.046630,105.790220'],
        'destination': ['21.056710,105.790170'],
        'vehicle': ['car'],
        'alternatives': ['false'],
        'api_key': [key],
      });
      // Written as Goong's documentation writes them.
      expect(
        req.url.query,
        'origin=21.046630,105.790220&destination=21.056710,105.790170'
        '&vehicle=car&alternatives=false&api_key=$key',
      );
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], GoongRouteProvider.defaultUserAgent);
    });

    test(
      'routes() asks for alternatives unless maxAlternatives is 0',
      () async {
        final s = serve(fixture('direction_alternatives.json'));
        await s.provider.routes(a, b);
        await s.provider.routes(a, b, maxAlternatives: 1);
        await s.provider.routes(a, b, maxAlternatives: 0);
        expect(
          [for (final r in s.requests) r.url.queryParameters['alternatives']],
          ['true', 'true', 'false'],
        );
      },
    );

    test('a negative maxAlternatives throws before any request', () async {
      final s = serve(fixture('direction_alternatives.json'));
      await expectLater(
        s.provider.routes(a, b, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('the heading is not sent: direction v2 takes none', () async {
      final s = serve(fixture('direction_alternatives.json'));
      await s.provider.route(a, b, heading: 90);
      await s.provider.routes(a, b, heading: 270);
      for (final r in s.requests) {
        expect(
          r.url.queryParameters.keys,
          unorderedEquals([
            'origin',
            'destination',
            'vehicle',
            'alternatives',
            'api_key',
          ]),
        );
      }
    });

    test('each vehicle is sent by its name', () async {
      final sent = <String>[];
      for (final vehicle in GoongVehicle.values) {
        final s = serve(
          fixture('direction_alternatives.json'),
          vehicle: vehicle,
        );
        await s.provider.route(a, b);
        sent.add(s.requests.single.url.queryParameters['vehicle']!);
      }
      expect(sent, ['car', 'bike', 'taxi', 'truck', 'hd']);
    });

    test('a null apiKey sends no key, for a proxy that adds it', () async {
      final s = serve(fixture('direction_alternatives.json'), apiKey: null);
      await s.provider.route(a, b);
      expect(
        s.requests.single.url.queryParameters.containsKey('api_key'),
        isFalse,
      );
    });

    test('the key is encoded', () async {
      final s = serve(
        fixture('direction_alternatives.json'),
        apiKey: 'a b&c=d',
      );
      await s.provider.route(a, b);
      expect(s.requests.single.url.queryParameters['api_key'], 'a b&c=d');
      expect(s.requests.single.url.query, endsWith('&api_key=a%20b%26c%3Dd'));
    });

    test('baseUrl keeps its path and query parameters', () async {
      final s = serve(
        fixture('direction_alternatives.json'),
        apiKey: null,
        baseUrl: Uri.parse('http://proxy.example.test:8080/goong/?tenant=t1'),
      );
      await s.provider.route(a, b);
      final url = s.requests.single.url;
      expect(url.scheme, 'http');
      expect(url.host, 'proxy.example.test');
      expect(url.port, 8080);
      expect(url.path, '/goong/v2/direction');
      expect(url.queryParameters['tenant'], 't1');
      expect(url.queryParameters['origin'], '21.046630,105.790220');
    });

    test('extra headers are sent, and may replace the defaults', () async {
      final s = serve(
        fixture('direction_alternatives.json'),
        headers: {'X-Proxy-Token': 'proxy-secret', 'User-Agent': 'my_app/3'},
      );
      await s.provider.route(a, b);
      final headers = s.requests.single.headers;
      expect(headers['X-Proxy-Token'], 'proxy-secret');
      expect(headers['User-Agent'], 'my_app/3');
      expect(headers['Accept'], 'application/json');
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('direction_alternatives.json'), userAgent: null);
      await s.provider.route(a, b);
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('a coordinate that rounds to zero is not written as -0', () async {
      final s = serve(fixture('direction_alternatives.json'));
      await s.provider.route(
        const GeoPoint(-0.0000001, -0.0000004),
        const GeoPoint(0.001, 0.001),
      );
      expect(
        s.requests.single.url.queryParameters['origin'],
        '0.000000,0.000000',
      );
    });

    test('a coordinate that is not finite throws before any request', () async {
      final s = serve(fixture('direction_alternatives.json'));
      await expectLater(
        s.provider.route(const GeoPoint(double.nan, 105.8), b),
        throwsArgumentError,
      );
      await expectLater(
        s.provider.routes(a, const GeoPoint(21.0, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('the defaults', () {
      final p = GoongRouteProvider(apiKey: key);
      addTearDown(p.close);
      expect(p.baseUrl, Uri.parse('https://rsapi.goong.io/'));
      expect(p.baseUrl, GoongRouteProvider.defaultBaseUrl);
      expect(p.vehicle, GoongVehicle.car);
      expect(p.headers, isEmpty);
      expect(p.timeout, const Duration(seconds: 12));
      expect(p.timeout, GoongRouteProvider.defaultTimeout);
      expect(
        GoongRouteProvider.defaultUserAgent,
        'navigation_engine_goong/0.1.0',
      );
    });
  });

  group('alternatives', () {
    test('routes() returns every route, best first', () async {
      final s = serve(fixture('direction_alternatives.json'));
      final routes = await s.provider.routes(a, b);
      expect(routes, hasLength(2));
      expect(routes[0].name, 'Goong 2512 m');
      expect(routes[1].name, 'Goong 2778 m');
      expect(routes[0].points, hasLength(10));
      expect(routes[1].points, hasLength(5));
      // NavRoute measures in a planar frame; the fixture's distances were
      // computed with haversine (2512.9 m and 2778.2 m), hence the names.
      expect(routes[0].length, closeTo(2508.5, 0.5));
      expect(routes[1].length, closeTo(2772.5, 0.5));
      expect(routes[0].duration, closeTo(255, 1e-9));
      expect(routes[1].duration, closeTo(300, 1e-9));
      expect(view(routes[1]), [
        (ManeuverType.depart, ManeuverModifier.none, 'Trần Cung'),
        (ManeuverType.turn, ManeuverModifier.left, 'Phạm Văn Đồng'),
        (ManeuverType.turn, ManeuverModifier.slightRight, 'Xuân Đỉnh'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      // Its `summary`, as Goong sent it.
      expect(routes[1].summary, 'Phạm Văn Đồng');
    });

    test('route() and routes() keep at most maxAlternatives + 1', () async {
      final s = serve(fixture('direction_alternatives.json'));
      final one = await s.provider.route(a, b);
      expect(one.name, 'Goong 2512 m');
      expect(await s.provider.routes(a, b, maxAlternatives: 0), hasLength(1));
      expect(
        [
          for (final r in await s.provider.routes(a, b, maxAlternatives: 1))
            r.name,
        ],
        ['Goong 2512 m', 'Goong 2778 m'],
      );
      expect(await s.provider.routes(a, b, maxAlternatives: 5), hasLength(2));
    });
  });

  group('geometry', () {
    test(
      'the step polylines are joined, the shared joint points kept once',
      () async {
        final r = await serve(
          fixture('direction_alternatives.json'),
        ).provider.route(a, b);
        const expected = [
          (21.04663, 105.79022),
          (21.04626, 105.79026),
          (21.04620, 105.79300),
          (21.04607, 105.79752),
          (21.04800, 105.79760),
          (21.05100, 105.79770),
          (21.05200, 105.79800),
          (21.05400, 105.79750),
          (21.05500, 105.79600),
          (21.05671, 105.79017),
        ];
        expect([for (final p in r.points) (p.lat, p.lng)], expected);
      },
    );

    test('a step that does not start where the previous one ended keeps both '
        'points: the gap belongs to that step', () async {
      final r = await serve(
        okBody([
          step([ne(0), ne(1)], seconds: 10),
          step([ne(2), ne(3)], seconds: 20, maneuver: 'turn-left'),
        ]),
      ).provider.route(a, b);
      expect(r.points, [ne(0), ne(1), ne(2), ne(3)]);
      // The turn is where the first step ended.
      expect(r.steps[1].distance, r.distanceAtVertex(1));
      final seconds = segmentSeconds(r);
      expect(seconds[0], closeTo(10, 1e-6));
      expect(seconds[1] + seconds[2], closeTo(20, 1e-6));
    });

    test('a repeated point inside a step is kept', () async {
      final r = await serve(
        okBody([
          step([ne(0), ne(1), ne(1), ne(2)], seconds: 30),
        ]),
      ).provider.route(a, b);
      expect(r.points, [ne(0), ne(1), ne(1), ne(2)]);
    });

    test('legs are joined in order', () async {
      final json =
          jsonDecode(
                okBody([
                  step([ne(0), ne(1)], seconds: 10),
                ]),
              )
              as Map<String, Object?>;
      final legs = routesOf(json).first['legs']! as List<Object?>;
      legs.add({
        'distance': {'text': '', 'value': 500},
        'duration': {'text': '', 'value': 0},
        'steps': [
          step([ne(1), ne(2)], seconds: 5, maneuver: 'turn-right'),
        ],
      });
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, [ne(0), ne(1), ne(2)]);
      expect(r.name, 'Goong 1500 m');
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, ''),
        (ManeuverType.turn, ManeuverModifier.right, ''),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(r.duration, closeTo(15, 1e-9));
    });

    test('a route without steps takes the overview polyline and spreads the '
        "legs' duration over it", () async {
      final json = fixtureJson('direction_alternatives.json');
      final leg =
          (routesOf(json).first['legs']! as List<Object?>).first!
              as Map<String, Object?>;
      leg['steps'] = <Object?>[];
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, hasLength(10));
      expect(view(r), [(ManeuverType.arrive, ManeuverModifier.none, '')]);
      expect(r.steps.single.distance, r.length);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(255, 1e-9));
      expectSpreadByLength(r);
    });
  });

  group('steps', () {
    test('the fixture route: a step where each one starts, and the arrival '
        'at the end', () async {
      final s = serve(fixture('direction_alternatives.json'));
      final r = await s.provider.route(a, b);
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, 'Trần Cung'),
        (ManeuverType.turn, ManeuverModifier.left, 'Hoàng Quốc Việt'),
        (ManeuverType.turn, ManeuverModifier.right, 'Phạm Văn Đồng'),
        (ManeuverType.turn, ManeuverModifier.slightRight, ''),
        (ManeuverType.fork, ManeuverModifier.slightLeft, 'Xuân Tảo'),
        (ManeuverType.roundabout, ManeuverModifier.right, 'Nguyễn Văn Huyên'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      const vertices = [0, 1, 3, 5, 6, 7, 9];
      for (var i = 0; i < vertices.length; i++) {
        expect(
          r.steps[i].distance,
          r.distanceAtVertex(vertices[i]),
          reason: 'step $i',
        );
      }
      expect(r.steps.last.distance, r.length, reason: 'arrival at the end');
      expect(r.steps.last.isArrival, isTrue);
      // Goong sent no summary: the longest named road (825 m of it).
      expect(r.summary, 'Nguyễn Văn Huyên');
    });

    test('a final step of no length sent as two points is the arrival, '
        'with no repeated vertex', () async {
      final r = await serve(
        okBody([
          step([ne(0), ne(1)], seconds: 10),
          step([ne(1), ne(2)], seconds: 20, maneuver: 'turn-left'),
          step([ne(2), ne(2)], seconds: 0, maneuver: ''),
        ]),
      ).provider.route(a, b);
      expect(r.points, [ne(0), ne(1), ne(2)]);
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, ''),
        (ManeuverType.turn, ManeuverModifier.left, ''),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(r.steps.last.distance, r.length);
      expect(r.duration, closeTo(30, 1e-9));
    });

    test('a leg without a distance names the route by its length', () async {
      final json = fixtureJson('direction_alternatives.json');
      final leg =
          (routesOf(json).first['legs']! as List<Object?>).first!
              as Map<String, Object?>;
      leg.remove('distance');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      final length = [
        for (var i = 0; i + 1 < r.points.length; i++)
          distanceBetween(r.points[i], r.points[i + 1]),
      ].fold(0.0, (a, b) => a + b);
      expect(r.name, 'Goong ${length.round()} m');
      expect(r.name, isNot('Goong 2512 m'));
      expect(r.steps, hasLength(7));
    });

    test(
      'a route whose last step has length gets an arrival at its end',
      () async {
        final r = await serve(
          okBody([
            step([ne(0), ne(1)]),
            step([ne(1), ne(2)], maneuver: 'turn-left'),
          ]),
        ).provider.route(a, b);
        expect(view(r), [
          (ManeuverType.depart, ManeuverModifier.none, ''),
          (ManeuverType.turn, ManeuverModifier.left, ''),
          (ManeuverType.arrive, ManeuverModifier.none, ''),
        ]);
        expect(r.steps.last.distance, r.length);
      },
    );

    test('every maneuver string', () async {
      // Google's values, then Goong's own forms, then the unknown ones.
      const maneuvers = <String?, StepView>{
        'turn-left': (ManeuverType.turn, ManeuverModifier.left, ''),
        'turn-right': (ManeuverType.turn, ManeuverModifier.right, ''),
        'turn-slight-left': (
          ManeuverType.turn,
          ManeuverModifier.slightLeft,
          '',
        ),
        'turn-slight-right': (
          ManeuverType.turn,
          ManeuverModifier.slightRight,
          '',
        ),
        'turn-sharp-left': (ManeuverType.turn, ManeuverModifier.sharpLeft, ''),
        'turn-sharp-right': (
          ManeuverType.turn,
          ManeuverModifier.sharpRight,
          '',
        ),
        'uturn-left': (ManeuverType.turn, ManeuverModifier.uturn, ''),
        'uturn-right': (ManeuverType.turn, ManeuverModifier.uturn, ''),
        'roundabout-left': (ManeuverType.roundabout, ManeuverModifier.left, ''),
        'roundabout-right': (
          ManeuverType.roundabout,
          ManeuverModifier.right,
          '',
        ),
        'keep-left': (ManeuverType.fork, ManeuverModifier.slightLeft, ''),
        'keep-right': (ManeuverType.fork, ManeuverModifier.slightRight, ''),
        'merge': (ManeuverType.merge, ManeuverModifier.none, ''),
        'fork-left': (ManeuverType.fork, ManeuverModifier.slightLeft, ''),
        'fork-right': (ManeuverType.fork, ManeuverModifier.slightRight, ''),
        'ramp-left': (ManeuverType.onRamp, ManeuverModifier.left, ''),
        'ramp-right': (ManeuverType.onRamp, ManeuverModifier.right, ''),
        'straight': (ManeuverType.continueOn, ManeuverModifier.straight, ''),
        'ferry': (ManeuverType.continueOn, ManeuverModifier.none, ''),
        'ferry-train': (ManeuverType.continueOn, ManeuverModifier.none, ''),
        // No maneuver: keep going.
        null: (ManeuverType.continueOn, ManeuverModifier.none, ''),
        '': (ManeuverType.continueOn, ManeuverModifier.none, ''),
        // Goong's documented forms, without the `turn-` prefix.
        'left': (ManeuverType.turn, ManeuverModifier.left, ''),
        'right': (ManeuverType.turn, ManeuverModifier.right, ''),
        'slight left': (ManeuverType.turn, ManeuverModifier.slightLeft, ''),
        'slight right': (ManeuverType.turn, ManeuverModifier.slightRight, ''),
        'sharp left': (ManeuverType.turn, ManeuverModifier.sharpLeft, ''),
        'sharp right': (ManeuverType.turn, ManeuverModifier.sharpRight, ''),
        'uturn': (ManeuverType.turn, ManeuverModifier.uturn, ''),
        // Case and spacing do not matter.
        ' Turn-Left ': (ManeuverType.turn, ManeuverModifier.left, ''),
        'keep_right': (ManeuverType.fork, ManeuverModifier.slightRight, ''),
        // A value Goong may add: a turn, direction unknown.
        'teleport': (ManeuverType.turn, ManeuverModifier.none, ''),
      };
      final values = maneuvers.keys.toList();
      // A start, then one step per value on its own segment.
      final steps = [
        step([ne(0), ne(1)], maneuver: 'straight'),
        for (var i = 0; i < values.length; i++)
          step([ne(i + 1), ne(i + 2)], maneuver: values[i]),
      ];
      final r = await serve(okBody(steps)).provider.route(a, b);
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, ''),
        ...maneuvers.values,
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
    });

    test('a JSON null maneuver is a continue', () async {
      final json = fixtureJson('direction_alternatives.json');
      stepsOf(json)[1]['maneuver'] = null;
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].type, ManeuverType.continueOn);
      expect(r.steps[1].modifier, ManeuverModifier.none);
      expect(r.steps[1].roadName, 'Hoàng Quốc Việt');
    });

    test('the first step is the departure, whatever its maneuver', () async {
      for (final maneuver in [null, '', 'right', 'turn-left', 'uturn-right']) {
        final r = await serve(
          okBody([
            step([ne(0), ne(1)], maneuver: maneuver),
          ]),
        ).provider.route(a, b);
        expect(r.steps.first.type, ManeuverType.depart, reason: maneuver);
        expect(r.steps.first.modifier, ManeuverModifier.none, reason: maneuver);
      }
    });

    test(
      'the road name comes from a step name field when there is one',
      () async {
        final json = fixtureJson('direction_alternatives.json');
        stepsOf(json)[1]['name'] = 'Đường Hoàng Quốc Việt';
        stepsOf(json)[3]['name'] = '';
        final r = await serve(jsonEncode(json)).provider.route(a, b);
        expect(r.steps[1].roadName, 'Đường Hoàng Quốc Việt');
        // An empty name falls back to the instructions (none there).
        expect(r.steps[3].roadName, '');
      },
    );

    test('no html_instructions is no road name', () async {
      final json = fixtureJson('direction_alternatives.json');
      stepsOf(json)[1].remove('html_instructions');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].roadName, '');
      expect(r.steps[1].modifier, ManeuverModifier.left);
    });
  });

  group('durations', () {
    test(
      "each step's duration is spread over its segments by length",
      () async {
        final r = await serve(
          fixture('direction_alternatives.json'),
        ).provider.route(a, b);
        expect(r.hasProviderDurations, isTrue);
        final p = r.points;
        double d(int i) => distanceBetween(p[i], p[i + 1]);
        final expected = [
          10.0,
          95 * d(1) / (d(1) + d(2)),
          95 * d(2) / (d(1) + d(2)),
          60 * d(3) / (d(3) + d(4)),
          60 * d(4) / (d(3) + d(4)),
          20.0,
          30.0,
          40 * d(7) / (d(7) + d(8)),
          40 * d(8) / (d(7) + d(8)),
        ];
        final actual = segmentSeconds(r);
        expect(actual, hasLength(expected.length));
        for (var i = 0; i < expected.length; i++) {
          expect(actual[i], closeTo(expected[i], 1e-6), reason: 'segment $i');
        }
        expect(r.duration, closeTo(255, 1e-9));
      },
    );

    test(
      'a step whose segments have no length spreads its time evenly',
      () async {
        final r = await serve(
          okBody([
            step([ne(0), ne(0), ne(0)], seconds: 6),
            step([ne(0), ne(1)], seconds: 4, maneuver: 'turn-left'),
          ]),
        ).provider.route(a, b);
        expect(r.hasProviderDurations, isTrue);
        expect(r.duration, closeTo(10, 1e-9));
        // Half-way along the only segment with length (4 s): 6 s, then 2 s.
        expect(r.durationAt(r.length / 2), closeTo(8, 1e-9));
      },
    );

    test(
      'the time of a step without segments goes to the segment before it',
      () async {
        final json = fixtureJson('direction_alternatives.json');
        (stepsOf(json).last['duration']! as Map<String, Object?>)['value'] = 5;
        final r = await serve(jsonEncode(json)).provider.route(a, b);
        expect(r.duration, closeTo(260, 1e-9));
        final p = r.points;
        final d7 = distanceBetween(p[7], p[8]);
        final d8 = distanceBetween(p[8], p[9]);
        expect(segmentSeconds(r).last, closeTo(40 * d8 / (d7 + d8) + 5, 1e-6));
      },
    );

    test('a step without a duration spreads the legs\' duration over the '
        'route by length', () async {
      final json = fixtureJson('direction_alternatives.json');
      stepsOf(json)[2].remove('duration');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(255, 1e-9));
      expectSpreadByLength(r);
      expect(r.steps, hasLength(7));
    });

    test('a zero-length step without a duration takes none', () async {
      final json = fixtureJson('direction_alternatives.json');
      stepsOf(json).last.remove('duration');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.duration, closeTo(255, 1e-9));
      expect(segmentSeconds(r).first, closeTo(10, 1e-6));
    });

    test('without step durations or a legs\' duration, the engine estimates '
        'them', () async {
      final json = fixtureJson('direction_alternatives.json');
      stepsOf(json)[2].remove('duration');
      final leg =
          (routesOf(json).first['legs']! as List<Object?>).first!
              as Map<String, Object?>;
      leg.remove('duration');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.hasProviderDurations, isFalse);
    });

    test('a duration that is negative or not a number throws', () async {
      for (final value in [-1, 'soon']) {
        final json = fixtureJson('direction_alternatives.json');
        (stepsOf(json)[3]['duration']! as Map<String, Object?>)['value'] =
            value;
        final e = await _thrown<GoongFormatException>(
          serve(jsonEncode(json)).provider.route(a, b),
        );
        expect(
          e.message,
          contains('routes[0].legs[0].steps[3].duration.value'),
          reason: '$value',
        );
      }
    });
  });

  group('errors', () {
    test(
      'ZERO_RESULTS throws GoongCodeException with a clear message',
      () async {
        final s = serve(fixture('direction_zero_results.json'));
        final e = await _thrown<GoongCodeException>(s.provider.routes(a, b));
        expect(e, isA<GoongException>());
        expect(e.code, 'ZERO_RESULTS');
        expect(e.serverMessage, 'Không tìm thấy đường đi giữa các điểm');
        expect(e.statusCode, 200);
        expect(
          e.message,
          'Goong ZERO_RESULTS: no result for the request '
          '(Không tìm thấy đường đi giữa các điểm) [HTTP 200]',
        );
        expect(
          e.toString(),
          startsWith('GoongCodeException: Goong ZERO_RESULTS'),
        );
      },
    );

    test('INVALID_REQUEST with an HTTP error keeps the status', () async {
      final s = serve(fixture('direction_invalid_request.json'), status: 400);
      final e = await _thrown<GoongCodeException>(s.provider.route(a, b));
      expect(e.code, 'INVALID_REQUEST');
      expect(e.statusCode, 400);
      expect(
        e.serverMessage,
        "Invalid request. Missing the 'destination' parameter.",
      );
      expect(e.message, contains('the server rejected the request'));
    });

    test('the {"error": {"code", "message"}} shape is a GoongCodeException '
        'too, with an HTTP error or 200', () async {
      for (final status in [403, 200]) {
        final s = serve(fixture('error_api_key_missing.json'), status: status);
        final e = await _thrown<GoongCodeException>(s.provider.route(a, b));
        expect(e.code, 'API_KEY_MISSING');
        expect(e.serverMessage, 'The api_key parameter is missing');
        expect(e.statusCode, status);
        expect(e.message, contains('no key was sent'));
      }
      // An error without a code, or as a plain string.
      for (final body in [
        {
          'error': {'message': 'blocked'},
        },
        {'error': 'blocked'},
      ]) {
        final e = await _thrown<GoongCodeException>(
          serve(jsonEncode(body), status: 403).provider.route(a, b),
        );
        expect(e.code, 'ERROR', reason: '$body');
        expect(e.serverMessage, 'blocked', reason: '$body');
      }
    });

    test('the other codes', () async {
      const cases = {
        'NOT_FOUND': 'a point or place was not found',
        'OVER_QUERY_LIMIT': 'the rate limit or quota is reached',
        'OVER_DAILY_LIMIT': 'the rate limit or quota is reached',
        'REQUEST_DENIED':
            'the request was denied (check the key and its restrictions)',
        'UNKNOWN_ERROR': 'an unexpected server error',
        'MAX_WAYPOINTS_EXCEEDED': 'too many points',
        'SOMETHING_NEW': 'the server reported an error',
      };
      for (final MapEntry(key: code, value: meaning) in cases.entries) {
        final s = serve(jsonEncode({'status': code, 'routes': <Object?>[]}));
        final e = await _thrown<GoongCodeException>(s.provider.route(a, b));
        expect(e.code, code);
        expect(e.serverMessage, isNull);
        expect(e.message, 'Goong $code: $meaning [HTTP 200]', reason: code);
      }
    });

    test('an HTTP error without a code throws GoongHttpException, with a '
        'hint', () async {
      const hints = {
        401: '(the key is missing or not valid)',
        403: '(the key is missing, not valid, blocked, or a Maptiles key)',
        429: '(rate limit reached)',
        502: 'Bad Gateway',
      };
      for (final MapEntry(key: status, value: hint) in hints.entries) {
        final s = serve('<html>Bad Gateway</html>', status: status);
        final e = await _thrown<GoongHttpException>(s.provider.route(a, b));
        expect(e, isA<GoongException>());
        expect(e.statusCode, status);
        expect(e.message, startsWith('Goong request failed with HTTP $status'));
        expect(e.message, contains(hint), reason: '$status');
        expect(e.message, endsWith(': <html>Bad Gateway</html>'));
      }
    });

    test('a key the server echoes, raw or percent-encoded, is scrubbed from '
        'the body and the server message', () async {
      // A key whose percent-encoded form differs from the raw one.
      const secret = 'k3y/with+chars=';
      const encoded = 'k3y%2Fwith%2Bchars%3D';
      Future<String> thrown(
        String body,
        int status, {
        String? reasonPhrase,
      }) async {
        final p = GoongRouteProvider(
          apiKey: secret,
          client: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode(body),
              status,
              reasonPhrase: reasonPhrase,
            ),
          ),
        );
        try {
          await p.route(a, b);
        } on GoongException catch (e) {
          return e.toString();
        }
        fail('expected a GoongException');
      }

      final texts = [
        // An HTTP error body.
        await thrown(
          'invalid api_key $secret in GET /v2/direction?api_key=$encoded',
          401,
        ),
        // A Goong status, its error_message echoing the key, with 200 and
        // 400.
        for (final status in [200, 400])
          await thrown(
            jsonEncode({
              'status': 'REQUEST_DENIED',
              'error_message': 'api_key=$encoded; key $secret is not valid',
            }),
            status,
          ),
        // The error-object shape.
        await thrown(
          jsonEncode({
            'error': {'code': 'INVALID_KEY', 'message': 'bad key $secret'},
          }),
          403,
        ),
        // Lower-case percent-encoding.
        await thrown('api_key=k3y%2fwith%2bchars%3d', 403),
        // The code itself, in either shape, and the HTTP reason phrase.
        await thrown(jsonEncode({'status': 'BAD_KEY_$secret'}), 200),
        await thrown(
          jsonEncode({
            'error': {'code': 'key $encoded'},
          }),
          403,
        ),
        await thrown('', 401, reasonPhrase: 'Bad key $secret'),
      ];
      expect(texts, [
        'GoongHttpException: Goong request failed with HTTP 401 (the key is '
            'missing or not valid): invalid api_key REDACTED in GET '
            '/v2/direction?api_key=REDACTED',
        'GoongCodeException: Goong REQUEST_DENIED: the request was denied '
            '(check the key and its restrictions) (api_key=REDACTED; key '
            'REDACTED is not valid) [HTTP 200]',
        'GoongCodeException: Goong REQUEST_DENIED: the request was denied '
            '(check the key and its restrictions) (api_key=REDACTED; key '
            'REDACTED is not valid) [HTTP 400]',
        'GoongCodeException: Goong INVALID_KEY: the server reported an error '
            '(bad key REDACTED) [HTTP 403]',
        'GoongHttpException: Goong request failed with HTTP 403 (the key is '
            'missing, not valid, blocked, or a Maptiles key): '
            'api_key=REDACTED',
        'GoongCodeException: Goong BAD_KEY_REDACTED: the server reported an '
            'error [HTTP 200]',
        'GoongCodeException: Goong key REDACTED: the server reported an error '
            '[HTTP 403]',
        'GoongHttpException: Goong request failed with HTTP 401 Bad key '
            'REDACTED (the key is missing or not valid)',
      ]);
      for (final text in texts) {
        expect(text.contains(secret), isFalse, reason: text);
        expect(
          text.toLowerCase().contains(encoded.toLowerCase()),
          isFalse,
          reason: text,
        );
      }
    });

    test('an empty key scrubs nothing', () async {
      final p = GoongRouteProvider(
        apiKey: '',
        client: MockClient((_) async => http.Response('bad request', 400)),
      );
      final e = await _thrown<GoongHttpException>(p.route(a, b));
      expect(e.message, 'Goong request failed with HTTP 400: bad request');
    });

    test('a long body is cut, and not inside a character', () async {
      final s = serve('${'x' * 199}😀😀', status: 500);
      final e = await _thrown<GoongHttpException>(s.provider.route(a, b));
      expect(e.message, endsWith(': ${'x' * 199}😀…'));
    });

    test('malformed JSON throws GoongFormatException', () async {
      final s = serve('{"routes":[');
      final e = await _thrown<GoongFormatException>(s.provider.route(a, b));
      expect(e.message, startsWith('invalid JSON'));
      expect(e.toString(), startsWith('GoongFormatException: invalid JSON'));
    });

    test('a body that is not UTF-8 throws GoongFormatException', () async {
      final p = GoongRouteProvider(
        apiKey: key,
        client: MockClient(
          (_) async => http.Response.bytes([0xff, 0xfe, 0x7b], 200),
        ),
      );
      final e = await _thrown<GoongFormatException>(p.route(a, b));
      expect(e.message, 'the body is not UTF-8');
    });

    test('an unexpected shape names the field', () async {
      Future<void> expectField(Object body, String field) async {
        final e = await _thrown<GoongFormatException>(
          serve(jsonEncode(body)).provider.routes(a, b),
        );
        expect(e.message, contains(field), reason: jsonEncode(body));
      }

      await expectField([1, 2], 'the answer is not a JSON object');
      await expectField({'status': 7}, 'status: expected a string');
      await expectField({'status': 'OK'}, 'routes: expected an array');
      await expectField({
        'status': 'OK',
        'routes': <Object?>[],
      }, 'routes: an OK answer with no routes');
      await expectField({
        'routes': ['x'],
      }, 'routes[0]: expected an object');

      Map<String, Object?> edited(void Function(Map<String, Object?>) edit) {
        final json = fixtureJson('direction_alternatives.json');
        edit(json);
        return json;
      }

      await expectField(
        edited((j) => routesOf(j).first.remove('legs')),
        'routes[0].legs',
      );
      await expectField(
        edited((j) => routesOf(j).first['legs'] = ['x']),
        'routes[0].legs[0]',
      );
      await expectField(
        edited((j) => stepsOf(j)[2].remove('polyline')),
        'routes[0].legs[0].steps[2].polyline',
      );
      await expectField(
        edited(
          (j) =>
              (stepsOf(j)[2]['polyline']! as Map<String, Object?>)['points'] =
                  7,
        ),
        'routes[0].legs[0].steps[2].polyline.points',
      );
      await expectField(
        edited(
          (j) =>
              (stepsOf(j)[2]['polyline']! as Map<String, Object?>)['points'] =
                  'saw`A',
        ),
        'routes[0].legs[0].steps[2].polyline.points',
      );
      await expectField(
        edited(
          (j) =>
              (stepsOf(j)[2]['polyline']! as Map<String, Object?>)['points'] =
                  '',
        ),
        'routes[0].legs[0].steps[2].polyline.points: no points',
      );
      await expectField(
        edited((j) => stepsOf(j)[2]['maneuver'] = 5),
        'routes[0].legs[0].steps[2].maneuver',
      );
      await expectField(
        edited((j) => stepsOf(j)[2]['html_instructions'] = ['x']),
        'routes[0].legs[0].steps[2].html_instructions',
      );
      await expectField(
        edited((j) => stepsOf(j)[2]['duration'] = 60),
        'routes[0].legs[0].steps[2].duration',
      );
      await expectField(
        edited(
          (j) =>
              ((routesOf(j).first['legs']! as List<Object?>).first!
                      as Map<String, Object?>)['distance'] =
                  5,
        ),
        'routes[0].legs[0].distance',
      );
      await expectField(
        edited((j) => routesOf(j)[1]['legs'] = 'x'),
        'routes[1].legs',
      );
      // No steps and no overview polyline.
      await expectField(
        edited((j) {
          final leg =
              (routesOf(j).first['legs']! as List<Object?>).first!
                  as Map<String, Object?>;
          leg['steps'] = <Object?>[];
          routesOf(j).first.remove('overview_polyline');
        }),
        'routes[0].overview_polyline',
      );
      // A single point: no route.
      await expectField(
        jsonDecode(
              okBody([
                step([ne(0)]),
              ]),
            )
            as Object,
        'routes[0]: 1 point(s), a route needs at least 2',
      );
    });

    test(
      'transport errors pass through, without the key in their URL',
      () async {
        final p = GoongRouteProvider(
          apiKey: key,
          client: MockClient(
            (req) async => throw http.ClientException('offline', req.url),
          ),
        );
        final e = await _thrown<http.ClientException>(p.route(a, b));
        expect(e.message, 'offline');
        expect(e.uri, isNotNull);
        expect(e.uri!.path, '/v2/direction');
        expect(e.uri!.queryParameters['api_key'], 'REDACTED');
        expect(e.uri!.queryParameters['origin'], '21.046630,105.790220');
        expect(e.toString().contains(key), isFalse, reason: e.toString());
        expect(e.toString(), contains('api_key=REDACTED'));
      },
    );

    test('a transport error message that holds the key, raw or encoded, is '
        'scrubbed', () async {
      const secret = 'k3y/with+chars=';
      final p = GoongRouteProvider(
        apiKey: secret,
        client: MockClient(
          (_) async => throw http.ClientException(
            'refused for api_key=k3y%2Fwith%2Bchars%3D ($secret)',
          ),
        ),
      );
      final e = await _thrown<http.ClientException>(p.route(a, b));
      expect(e.message, 'refused for api_key=REDACTED (REDACTED)');
      expect(e.uri, isNull);
    });

    test(
      'a transport error without the key passes through unchanged',
      () async {
        final error = http.ClientException('offline');
        final p = GoongRouteProvider(
          apiKey: key,
          client: MockClient((_) async => throw error),
        );
        await expectLater(p.route(a, b), throwsA(same(error)));
      },
    );
  });

  group('timeout', () {
    test('a server that never answers times out and the request is '
        'aborted', () async {
      final requests = <http.BaseRequest>[];
      final p = GoongRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((req, _) {
          requests.add(req);
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final e = await _thrown<GoongTimeoutException>(p.routes(a, b));
      expect(e, isA<GoongException>());
      expect(e, isA<TimeoutException>());
      expect(e.timeout, const Duration(milliseconds: 50));
      expect(e.duration, const Duration(milliseconds: 50));
      expect(e.message, 'Goong request timed out after 50 ms');
      final trigger = (requests.single as http.Abortable).abortTrigger;
      expect(trigger, isNotNull);
      await trigger!.timeout(const Duration(seconds: 1));
    });

    test('a TimeoutException from the client is not reported as the '
        "provider's own timeout", () async {
      final p = GoongRouteProvider(
        apiKey: key,
        timeout: const Duration(seconds: 5),
        client: MockClient((_) async => throw TimeoutException('inner')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<TimeoutException>()
              .having((e) => e, 'type', isNot(isA<GoongTimeoutException>()))
              .having((e) => e.message, 'message', 'inner'),
        ),
      );
    });

    test('a body that stalls times out too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final p = GoongRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((_, _) async {
          body.add(utf8.encode('{"routes":'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      await _thrown<GoongTimeoutException>(p.route(a, b));
    });
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('direction_alternatives.json')),
            200,
          ),
        ),
      );
      final p = GoongRouteProvider(apiKey: key, client: client);
      await p.route(a, b);
      p.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the provider created', () async {
      final created = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('direction_alternatives.json')),
            200,
          ),
        ),
      );
      final p = http.runWithClient(
        () => GoongRouteProvider(apiKey: key),
        () => created,
      );
      await p.route(a, b);
      expect(created.closed, isFalse);
      p.close();
      expect(created.closed, isTrue);
      p.close();
    });

    test('a closed provider throws StateError', () async {
      final s = serve(fixture('direction_alternatives.json'));
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
