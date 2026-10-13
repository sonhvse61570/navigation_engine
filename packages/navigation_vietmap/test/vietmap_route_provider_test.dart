import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:test/test.dart';

// Fixtures (test/fixtures), all hand-written in the shape of Vietmap's route
// v4 documentation (https://maps.vietmap.vn/docs/map-api/route-version/route-v4/);
// none was recorded, and none holds a key:
// - route_alternatives.json: two paths from Lê Lợi (Ho Chi Minh City) with
//   instructions for continue, right, keep left, left, roundabout, slight
//   right and finish (the first path), and continue, sharp right and finish
//   (the second).
// - route_zero_results.json, route_invalid_request.json: error bodies with
//   the documented `code` and `messages`.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

/// The paths of [json], to edit in place.
List<Map<String, Object?>> pathsOf(Map<String, Object?> json) =>
    (json['paths']! as List<Object?>).cast<Map<String, Object?>>();

/// The instructions of the first path of [json], to edit in place.
List<Map<String, Object?>> instructionsOf(Map<String, Object?> json) =>
    (pathsOf(json).first['instructions']! as List<Object?>)
        .cast<Map<String, Object?>>();

const a = GeoPoint(10.7729, 106.698);
const b = GeoPoint(10.7761, 106.7031);

/// A fake key: requests must carry it, messages must not.
const key = 'test-services-key';

/// A provider whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({VietmapRouteProvider provider, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? apiKey = key,
  Uri? baseUrl,
  VietmapVehicle vehicle = VietmapVehicle.car,
  int? capacity,
  Map<String, String> headers = const {},
  String? userAgent = VietmapRouteProvider.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final provider = VietmapRouteProvider(
    apiKey: apiKey,
    baseUrl: baseUrl,
    vehicle: vehicle,
    capacity: capacity,
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
  for (var i = 0; i < seconds.length; i++) {
    final share = distanceBetween(r.points[i], r.points[i + 1]);
    expect(seconds[i], closeTo(r.duration * share / totalLength(r), 1e-6));
  }
}

/// The sum of [r]'s segment lengths, as the provider measures them.
double totalLength(NavRoute r) => [
  for (var i = 0; i + 1 < r.points.length; i++)
    distanceBetween(r.points[i], r.points[i + 1]),
].fold(0.0, (a, b) => a + b);

/// A straight path of [vertices] points heading north-east, with
/// [instructions], encoded as Vietmap sends it.
Map<String, Object?> straightPath(
  int vertices,
  List<Map<String, Object?>> instructions,
) => {
  'distance': 100.0 * (vertices - 1),
  'time': 0,
  'points_encoded': true,
  'points': encode([
    for (var i = 0; i < vertices; i++)
      GeoPoint(10.77 + i * 0.001, 106.69 + i * 0.001),
  ]),
  'instructions': instructions,
};

/// Google's polyline algorithm at precision 5, for hand-made paths.
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

String okBody(List<Map<String, Object?>> paths) =>
    jsonEncode({'license': 'vietmap', 'code': 'OK', 'paths': paths});

void main() {
  group('request', () {
    test('route() asks route v4 for one route between the two points, '
        'lat,lng, with an encoded polyline', () async {
      final s = serve(fixture('route_alternatives.json'));
      await s.provider.route(a, b);
      expect(s.requests, hasLength(1));
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.scheme, 'https');
      expect(req.url.host, 'maps.vietmap.vn');
      expect(req.url.path, '/api/route/v4');
      expect(req.url.queryParametersAll, {
        'apikey': [key],
        'point': ['10.772900,106.698000', '10.776100,106.703100'],
        'vehicle': ['car'],
        'alternative': ['false'],
        'points_encoded': ['true'],
      });
      // Written as Vietmap's documentation writes them.
      expect(
        req.url.query,
        contains('point=10.772900,106.698000&point=10.776100,106.703100'),
      );
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], VietmapRouteProvider.defaultUserAgent);
    });

    test(
      'routes() asks for alternatives unless maxAlternatives is 0',
      () async {
        final s = serve(fixture('route_alternatives.json'));
        await s.provider.routes(a, b);
        await s.provider.routes(a, b, maxAlternatives: 1);
        await s.provider.routes(a, b, maxAlternatives: 0);
        expect(
          [for (final r in s.requests) r.url.queryParameters['alternative']],
          ['true', 'true', 'false'],
        );
      },
    );

    test('a negative maxAlternatives throws before any request', () async {
      final s = serve(fixture('route_alternatives.json'));
      await expectLater(
        s.provider.routes(a, b, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('the heading is sent in whole degrees, 0 to 359', () async {
      final s = serve(fixture('route_alternatives.json'));
      for (final h in [90.0, 0.0, -10.4, 359.6, 450.0, 271.5]) {
        await s.provider.route(a, b, heading: h);
      }
      await s.provider.routes(a, b, heading: 45);
      expect(
        [for (final r in s.requests) r.url.queryParameters['heading']],
        ['90', '0', '350', '0', '90', '272', '45'],
      );
    });

    test('no heading, or one that is not finite, sends none', () async {
      final s = serve(fixture('route_alternatives.json'));
      await s.provider.route(a, b);
      await s.provider.route(a, b, heading: double.nan);
      await s.provider.routes(a, b, heading: double.infinity);
      for (final r in s.requests) {
        expect(r.url.queryParameters.containsKey('heading'), isFalse);
      }
    });

    test('the vehicle, and a truck\'s capacity, are sent', () async {
      final moto = serve(
        fixture('route_alternatives.json'),
        vehicle: VietmapVehicle.motorcycle,
      );
      await moto.provider.route(a, b);
      expect(moto.requests.single.url.queryParameters['vehicle'], 'motorcycle');
      expect(
        moto.requests.single.url.queryParameters.containsKey('capacity'),
        isFalse,
      );

      final truck = serve(
        fixture('route_alternatives.json'),
        vehicle: VietmapVehicle.truck,
        capacity: 2000,
      );
      await truck.provider.route(a, b);
      expect(truck.requests.single.url.queryParameters['vehicle'], 'truck');
      expect(truck.requests.single.url.queryParameters['capacity'], '2000');

      final container = serve(
        fixture('route_alternatives.json'),
        vehicle: VietmapVehicle.container,
      );
      await container.provider.route(a, b);
      expect(
        container.requests.single.url.queryParameters['vehicle'],
        'container',
      );
    });

    test('a truck needs a positive capacity', () {
      expect(
        () => VietmapRouteProvider(apiKey: key, vehicle: VietmapVehicle.truck),
        throwsArgumentError,
      );
      expect(
        () => VietmapRouteProvider(
          apiKey: key,
          vehicle: VietmapVehicle.truck,
          capacity: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => VietmapRouteProvider(apiKey: key, capacity: -5),
        throwsArgumentError,
      );
    });

    test('a null apiKey sends no key, for a proxy that adds it', () async {
      final s = serve(fixture('route_alternatives.json'), apiKey: null);
      await s.provider.route(a, b);
      expect(
        s.requests.single.url.queryParameters.containsKey('apikey'),
        isFalse,
      );
    });

    test('the key is encoded', () async {
      final s = serve(fixture('route_alternatives.json'), apiKey: 'a b&c=d');
      await s.provider.route(a, b);
      expect(s.requests.single.url.queryParameters['apikey'], 'a b&c=d');
    });

    test('baseUrl keeps its path and query parameters', () async {
      final s = serve(
        fixture('route_alternatives.json'),
        apiKey: null,
        baseUrl: Uri.parse('http://proxy.example.test:8080/vietmap/?tenant=t1'),
      );
      await s.provider.route(a, b);
      final url = s.requests.single.url;
      expect(url.scheme, 'http');
      expect(url.host, 'proxy.example.test');
      expect(url.port, 8080);
      expect(url.path, '/vietmap/route/v4');
      expect(url.queryParameters['tenant'], 't1');
      expect(url.queryParametersAll['point'], hasLength(2));
    });

    test('extra headers are sent, and may replace the defaults', () async {
      final s = serve(
        fixture('route_alternatives.json'),
        headers: {'X-Proxy-Token': 'proxy-secret', 'User-Agent': 'my_app/3'},
      );
      await s.provider.route(a, b);
      final headers = s.requests.single.headers;
      expect(headers['X-Proxy-Token'], 'proxy-secret');
      expect(headers['User-Agent'], 'my_app/3');
      expect(headers['Accept'], 'application/json');
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('route_alternatives.json'), userAgent: null);
      await s.provider.route(a, b);
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('a coordinate that rounds to zero is not written as -0', () async {
      final s = serve(fixture('route_alternatives.json'));
      await s.provider.route(
        const GeoPoint(-0.0000001, -0.0000004),
        const GeoPoint(0.001, 0.001),
      );
      expect(
        s.requests.single.url.queryParametersAll['point']!.first,
        '0.000000,0.000000',
      );
    });

    test('a coordinate that is not finite throws before any request', () async {
      final s = serve(fixture('route_alternatives.json'));
      await expectLater(
        s.provider.route(const GeoPoint(double.nan, 106.7), b),
        throwsArgumentError,
      );
      await expectLater(
        s.provider.routes(a, const GeoPoint(10.7, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('the defaults', () {
      final p = VietmapRouteProvider(apiKey: key);
      addTearDown(p.close);
      expect(p.baseUrl, Uri.parse('https://maps.vietmap.vn/api/'));
      expect(p.baseUrl, VietmapRouteProvider.defaultBaseUrl);
      expect(p.vehicle, VietmapVehicle.car);
      expect(p.capacity, isNull);
      expect(p.headers, isEmpty);
      expect(p.timeout, const Duration(seconds: 12));
      expect(p.timeout, VietmapRouteProvider.defaultTimeout);
    });
  });

  group('alternatives', () {
    test('routes() returns every path, best first', () async {
      final s = serve(fixture('route_alternatives.json'));
      final routes = await s.provider.routes(a, b);
      expect(routes, hasLength(2));
      expect(routes[0].name, 'Vietmap 744 m');
      expect(routes[1].name, 'Vietmap 818 m');
      expect(routes[0].points, hasLength(10));
      expect(routes[1].points, hasLength(6));
      expect(routes[0].length, closeTo(744.2, 3));
      expect(routes[1].length, closeTo(817.6, 3));
      expect(routes[0].duration, closeTo(119, 1e-9));
      expect(routes[1].duration, closeTo(100, 1e-9));
      expect(view(routes[1]), [
        (ManeuverType.depart, ManeuverModifier.none, 'Đồng Khởi'),
        (ManeuverType.turn, ManeuverModifier.sharpRight, 'Lý Tự Trọng'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
    });

    test('route() and routes() keep at most maxAlternatives + 1', () async {
      final s = serve(fixture('route_alternatives.json'));
      final one = await s.provider.route(a, b);
      expect(one.name, 'Vietmap 744 m');
      expect(await s.provider.routes(a, b, maxAlternatives: 0), hasLength(1));
      expect(await s.provider.routes(a, b, maxAlternatives: 1), hasLength(2));
      expect(await s.provider.routes(a, b, maxAlternatives: 5), hasLength(2));
    });
  });

  group('steps', () {
    test('the fixture route: each instruction becomes a step at the start '
        'of its interval', () async {
      final s = serve(fixture('route_alternatives.json'));
      final r = await s.provider.route(a, b);
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.turn, ManeuverModifier.right, 'Nguyễn Huệ'),
        (ManeuverType.fork, ManeuverModifier.slightLeft, 'Hàm Nghi'),
        (ManeuverType.turn, ManeuverModifier.left, 'Tôn Đức Thắng'),
        (ManeuverType.roundabout, ManeuverModifier.none, ''),
        (ManeuverType.turn, ManeuverModifier.slightRight, 'Nguyễn Tất Thành'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      const vertices = [0, 2, 4, 6, 7, 8, 9];
      for (var i = 0; i < vertices.length; i++) {
        expect(
          r.steps[i].distance,
          r.distanceAtVertex(vertices[i]),
          reason: 'step $i',
        );
        expect(r.steps[i].lanes, isEmpty, reason: 'no lanes in route v4');
      }
      expect(r.steps.last.distance, r.length, reason: 'arrival at the end');
      expect(r.steps.last.isArrival, isTrue);
    });

    test('every sign code', () async {
      const signs = <int, StepView>{
        -98: (ManeuverType.turn, ManeuverModifier.uturn, ''),
        -8: (ManeuverType.turn, ManeuverModifier.uturn, ''),
        -7: (ManeuverType.fork, ManeuverModifier.slightLeft, ''),
        -6: (ManeuverType.exitRoundabout, ManeuverModifier.none, ''),
        -3: (ManeuverType.turn, ManeuverModifier.sharpLeft, ''),
        -2: (ManeuverType.turn, ManeuverModifier.left, ''),
        -1: (ManeuverType.turn, ManeuverModifier.slightLeft, ''),
        0: (ManeuverType.continueOn, ManeuverModifier.straight, ''),
        1: (ManeuverType.turn, ManeuverModifier.slightRight, ''),
        2: (ManeuverType.turn, ManeuverModifier.right, ''),
        3: (ManeuverType.turn, ManeuverModifier.sharpRight, ''),
        5: (ManeuverType.continueOn, ManeuverModifier.none, ''),
        6: (ManeuverType.roundabout, ManeuverModifier.none, ''),
        7: (ManeuverType.fork, ManeuverModifier.slightRight, ''),
        8: (ManeuverType.turn, ManeuverModifier.uturn, ''),
        // A code Vietmap may add: a turn, direction unknown.
        42: (ManeuverType.turn, ManeuverModifier.none, ''),
        -42: (ManeuverType.turn, ManeuverModifier.none, ''),
        4: (ManeuverType.arrive, ManeuverModifier.none, ''),
      };
      final codes = signs.keys.toList();
      // A start, then one instruction per code on its own segment.
      final instructions = [
        {
          'sign': 0,
          'interval': [0, 1],
          'time': 1000,
        },
        for (var i = 0; i < codes.length; i++)
          {
            'sign': codes[i],
            'interval': [i + 1, i == codes.length - 1 ? i + 1 : i + 2],
            'time': i == codes.length - 1 ? 0 : 1000,
          },
      ];
      final s = serve(okBody([straightPath(codes.length + 1, instructions)]));
      final r = await s.provider.route(a, b);
      expect(view(r), [
        (ManeuverType.depart, ManeuverModifier.none, ''),
        ...signs.values,
      ]);
    });

    test(
      'only a first instruction that goes straight on is the departure',
      () async {
        final s = serve(
          okBody([
            straightPath(3, [
              {
                'sign': 8,
                'interval': [0, 1],
                'time': 1000,
              },
              {
                'sign': 0,
                'interval': [1, 2],
                'time': 1000,
              },
              {
                'sign': 4,
                'interval': [2, 2],
                'time': 0,
              },
            ]),
          ]),
        );
        final r = await s.provider.route(a, b);
        expect(view(r), [
          (ManeuverType.turn, ManeuverModifier.uturn, ''),
          (ManeuverType.continueOn, ManeuverModifier.straight, ''),
          (ManeuverType.arrive, ManeuverModifier.none, ''),
        ]);
      },
    );

    test('a sign sent as a whole double is read; a fraction is not', () async {
      final json = fixtureJson('route_alternatives.json');
      instructionsOf(json)[1]['sign'] = 2.0;
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].modifier, ManeuverModifier.right);

      instructionsOf(json)[1]['sign'] = 2.5;
      final e = await _thrown<VietmapFormatException>(
        serve(jsonEncode(json)).provider.route(a, b),
      );
      expect(e.message, contains('paths[0].instructions[1].sign'));
    });

    test('the road name falls back to street_ref, else is empty', () async {
      final json = fixtureJson('route_alternatives.json');
      final instructions = instructionsOf(json);
      instructions[1]
        ..['street_name'] = ''
        ..['street_ref'] = 'QL1A';
      instructions[2].remove('street_name');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].roadName, 'QL1A');
      expect(r.steps[2].roadName, '');
    });

    test('a path without instructions has no steps', () async {
      final json = fixtureJson('route_alternatives.json');
      pathsOf(json).first.remove('instructions');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps, isEmpty);
      expect(r.points, hasLength(10));
      // The path's time, spread by length.
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(119, 1e-9));
    });

    test('the summary is the road covering the longest distance', () async {
      final r = await serve(
        fixture('route_alternatives.json'),
      ).provider.route(a, b);
      expect(r.summary, 'Lê Lợi');
    });
  });

  group('durations', () {
    test('each instruction\'s time is spread over its interval\'s segments '
        'by length', () async {
      final r = await serve(
        fixture('route_alternatives.json'),
      ).provider.route(a, b);
      expect(r.hasProviderDurations, isTrue);
      final p = r.points;
      double d(int i) => distanceBetween(p[i], p[i + 1]);
      final expected = [
        36 * d(0) / (d(0) + d(1)),
        36 * d(1) / (d(0) + d(1)),
        30 * d(2) / (d(2) + d(3)),
        30 * d(3) / (d(2) + d(3)),
        24 * d(4) / (d(4) + d(5)),
        24 * d(5) / (d(4) + d(5)),
        12.0,
        9.0,
        8.0,
      ];
      final actual = segmentSeconds(r);
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], closeTo(expected[i], 1e-6), reason: 'segment $i');
      }
      expect(r.duration, closeTo(119, 1e-9));
    });

    test('an interval of zero-length segments keeps its time, spread evenly '
        '(no division by zero)', () async {
      final s = serve(
        okBody([
          {
            'distance': 0,
            'time': 4000,
            'points': encode(const [
              GeoPoint(10.77, 106.69),
              GeoPoint(10.77, 106.69),
              GeoPoint(10.77, 106.69),
              GeoPoint(10.771, 106.69),
            ]),
            'instructions': [
              {
                'sign': 0,
                'interval': [0, 2],
                'time': 3000,
              },
              {
                'sign': 2,
                'interval': [2, 3],
                'time': 1000,
              },
              {
                'sign': 4,
                'interval': [3, 3],
                'time': 0,
              },
            ],
          },
        ]),
      );
      final r = await s.provider.route(a, b);
      // Segments of no length take no distance: only the total shows.
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(4, 1e-9));
      // Half-way along the last segment (1 s): the 3 s before, then 0.5 s.
      expect(r.durationAt(r.length / 2), closeTo(3.5, 1e-9));
    });

    test('the time of an instruction without segments goes to the segment '
        'before it', () async {
      final json = fixtureJson('route_alternatives.json');
      instructionsOf(json).last['time'] = 5000;
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.duration, closeTo(124, 1e-9));
      expect(segmentSeconds(r).last, closeTo(13, 1e-6));
    });

    test('intervals that leave a gap or overlap spread the path\'s time over '
        'the path by length, and keep the steps', () async {
      for (final interval in [
        [3, 4], // overlaps [2, 4]
        [5, 6], // a gap: segment 4 is not covered
      ]) {
        final json = fixtureJson('route_alternatives.json');
        instructionsOf(json)[2]['interval'] = interval;
        final r = await serve(jsonEncode(json)).provider.route(a, b);
        expect(r.hasProviderDurations, isTrue, reason: '$interval');
        expect(r.duration, closeTo(119, 1e-9), reason: '$interval');
        expectSpreadByLength(r);
        expect(r.steps, hasLength(7), reason: '$interval');
      }
      // The last instruction must reach the end of the path.
      final json = fixtureJson('route_alternatives.json');
      final instructions = instructionsOf(json);
      instructions.removeLast();
      instructions.last['interval'] = [8, 8];
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.duration, closeTo(119, 1e-9));
      expectSpreadByLength(r);
    });

    test('without tiling intervals, a path time that is 0, absent or bad '
        'leaves the durations to the engine', () async {
      for (final time in [0, null]) {
        final json = fixtureJson('route_alternatives.json');
        pathsOf(json).first.remove('instructions');
        if (time == null) {
          pathsOf(json).first.remove('time');
        } else {
          pathsOf(json).first['time'] = time;
        }
        final r = await serve(jsonEncode(json)).provider.route(a, b);
        expect(r.hasProviderDurations, isFalse, reason: '$time');
      }
      final json = fixtureJson('route_alternatives.json');
      pathsOf(json).first['time'] = -5;
      final e = await _thrown<VietmapFormatException>(
        serve(jsonEncode(json)).provider.route(a, b),
      );
      expect(e.message, contains('paths[0].time'));
    });

    test('a time that is negative or not a number throws', () async {
      for (final time in [-1, 'soon']) {
        final json = fixtureJson('route_alternatives.json');
        instructionsOf(json)[3]['time'] = time;
        final e = await _thrown<VietmapFormatException>(
          serve(jsonEncode(json)).provider.route(a, b),
        );
        expect(e.message, contains('paths[0].instructions[3].time'));
      }
    });
  });

  group('errors', () {
    test(
      'ZERO_RESULTS throws VietmapCodeException with a clear message',
      () async {
        final s = serve(fixture('route_zero_results.json'));
        final e = await _thrown<VietmapCodeException>(s.provider.routes(a, b));
        expect(e, isA<VietmapException>());
        expect(e.code, 'ZERO_RESULTS');
        expect(e.serverMessage, 'Không tìm thấy đường đi giữa các điểm');
        expect(e.statusCode, 200);
        expect(e.message, contains('ZERO_RESULTS'));
        expect(e.message, contains('no route between the points'));
        expect(e.message, contains('Không tìm thấy đường đi'));
        expect(e.toString(), startsWith('VietmapCodeException: '));
      },
    );

    test('INVALID_REQUEST with an HTTP error keeps the status', () async {
      final s = serve(fixture('route_invalid_request.json'), status: 400);
      final e = await _thrown<VietmapCodeException>(s.provider.route(a, b));
      expect(e.code, 'INVALID_REQUEST');
      expect(e.statusCode, 400);
      expect(e.serverMessage, 'Point 1 is out of bounds: 91.0,106.7');
      expect(e.message, contains('rejected the request'));
    });

    test('the other codes', () async {
      const cases = {
        'OVER_DAILY_LIMIT': 'daily limit',
        'MAX_POINTS_EXCEED': 'too many points',
        'ERROR_UNKNOWN': 'unexpected server error',
        'SOMETHING_NEW': 'SOMETHING_NEW',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final s = serve(jsonEncode({'code': key, 'paths': <Object?>[]}));
        final e = await _thrown<VietmapCodeException>(s.provider.route(a, b));
        expect(e.code, key);
        expect(e.serverMessage, isNull);
        expect(e.message, contains(value), reason: key);
      }
    });

    test('messages as a list, or a single message, are kept', () async {
      var s = serve(
        jsonEncode({
          'code': 'INVALID_REQUEST',
          'messages': ['vehicle is invalid', 'point is missing'],
        }),
      );
      var e = await _thrown<VietmapCodeException>(s.provider.route(a, b));
      expect(e.serverMessage, 'vehicle is invalid; point is missing');

      s = serve(jsonEncode({'code': 'ERROR_UNKNOWN', 'message': 'boom'}));
      e = await _thrown<VietmapCodeException>(s.provider.route(a, b));
      expect(e.serverMessage, 'boom');
    });

    test('an HTTP error without a code throws VietmapHttpException, with a '
        'hint', () async {
      const hints = {
        401: 'key',
        403: 'key',
        423: 'services key',
        429: 'rate limit',
        502: 'HTTP 502',
      };
      for (final MapEntry(key: status, value: hint) in hints.entries) {
        final s = serve('<html>Bad Gateway</html>', status: status);
        final e = await _thrown<VietmapHttpException>(s.provider.route(a, b));
        expect(e, isA<VietmapException>());
        expect(e.statusCode, status);
        expect(e.message, contains('HTTP $status'));
        expect(e.message, contains(hint), reason: '$status');
        expect(e.message, contains('Bad Gateway'));
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
        final p = VietmapRouteProvider(
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
        } on VietmapException catch (e) {
          return e.toString();
        }
        fail('expected a VietmapException');
      }

      final texts = [
        // An HTTP error body.
        await thrown(
          'invalid apikey $secret in GET /route/v4?apikey=$encoded&point=1',
          401,
        ),
        // A Vietmap code, its messages echoing the key, with 200 and 400.
        for (final status in [200, 400])
          await thrown(
            jsonEncode({
              'code': 'INVALID_REQUEST',
              'messages': ['apikey=$encoded', 'key $secret is not valid'],
            }),
            status,
          ),
        // Lower-case percent-encoding.
        await thrown('apikey=k3y%2fwith%2bchars%3d', 403),
        // The code itself, with 200 and 400, and the HTTP reason phrase.
        await thrown(jsonEncode({'code': 'BAD_KEY_$secret'}), 200),
        await thrown(jsonEncode({'code': 'key $encoded'}), 400),
        await thrown('', 401, reasonPhrase: 'Bad key $secret'),
      ];
      for (final text in texts) {
        expect(text.contains(secret), isFalse, reason: text);
        expect(
          text.toLowerCase().contains(encoded.toLowerCase()),
          isFalse,
          reason: text,
        );
        expect(text, contains('REDACTED'));
      }
      expect(texts.first, contains('HTTP 401'));
      expect(texts[1], contains('INVALID_REQUEST'));
      expect(texts.sublist(4), [
        'VietmapCodeException: Vietmap BAD_KEY_REDACTED: the server reported '
            'an error [HTTP 200]',
        'VietmapCodeException: Vietmap key REDACTED: the server reported an '
            'error [HTTP 400]',
        'VietmapHttpException: Vietmap request failed with HTTP 401 Bad key '
            'REDACTED (the key is missing or not valid)',
      ]);
    });

    test('a malformed interval is described without quoting its strings, '
        'which may hold anything (the key included)', () async {
      final json = fixtureJson('route_alternatives.json');
      instructionsOf(json)[2]['interval'] = ['apikey=$key', 4];
      final e = await _thrown<VietmapFormatException>(
        serve(jsonEncode(json)).provider.route(a, b),
      );
      expect(
        e.message,
        'paths[0].instructions[2].interval: expected two vertex indices, '
        'got [a string, 4]',
      );
    });

    test('an empty key scrubs nothing', () async {
      final p = VietmapRouteProvider(
        apiKey: '',
        client: MockClient((_) async => http.Response('bad request', 400)),
      );
      final e = await _thrown<VietmapHttpException>(p.route(a, b));
      expect(e.message, endsWith(': bad request'));
    });

    test('a long body is cut, and not inside a character', () async {
      final s = serve('${'x' * 199}😀😀', status: 500);
      final e = await _thrown<VietmapHttpException>(s.provider.route(a, b));
      expect(e.message, endsWith('${'x' * 199}😀…'));
    });

    test('malformed JSON throws VietmapFormatException', () async {
      final s = serve('{"code":"OK","paths":[');
      final e = await _thrown<VietmapFormatException>(s.provider.route(a, b));
      expect(e.message, contains('invalid JSON'));
      expect(e.toString(), startsWith('VietmapFormatException: '));
    });

    test('a body that is not UTF-8 throws VietmapFormatException', () async {
      final p = VietmapRouteProvider(
        apiKey: key,
        client: MockClient(
          (_) async => http.Response.bytes([0xff, 0xfe, 0x7b], 200),
        ),
      );
      final e = await _thrown<VietmapFormatException>(p.route(a, b));
      expect(e.message, contains('not UTF-8'));
    });

    test('an unexpected shape names the field', () async {
      Future<void> expectField(Object body, String field) async {
        final e = await _thrown<VietmapFormatException>(
          serve(jsonEncode(body)).provider.routes(a, b),
        );
        expect(e.message, contains(field), reason: jsonEncode(body));
      }

      await expectField([1, 2], 'not a JSON object');
      await expectField({'code': 7}, 'code');
      await expectField({'code': 'OK'}, 'paths');
      await expectField({'code': 'OK', 'paths': <Object?>[]}, 'no paths');
      await expectField({
        'code': 'OK',
        'paths': ['x'],
      }, 'paths[0]');

      Map<String, Object?> edited(void Function(Map<String, Object?>) edit) {
        final json = fixtureJson('route_alternatives.json');
        edit(json);
        return json;
      }

      await expectField(
        edited(
          (j) => pathsOf(j).first['points'] = [
            [106.7, 10.8],
          ],
        ),
        'paths[0].points',
      );
      await expectField(
        edited((j) => pathsOf(j).first['points'] = 'saw`A'),
        'paths[0].points',
      );
      await expectField(
        edited((j) => pathsOf(j).first['points'] = 'saw`AomfjS'),
        'paths[0].points',
      );
      await expectField(
        edited((j) => pathsOf(j).first.remove('distance')),
        'paths[0].distance',
      );
      await expectField(
        edited((j) => pathsOf(j).first['instructions'] = 'none'),
        'paths[0].instructions',
      );
      await expectField(
        edited((j) => instructionsOf(j)[2].remove('sign')),
        'paths[0].instructions[2].sign',
      );
      await expectField(
        edited((j) => instructionsOf(j)[2]['interval'] = [4]),
        'paths[0].instructions[2].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j)[2]['interval'] = [4, 'x']),
        'paths[0].instructions[2].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j)[2]['interval'] = [4.5, 6]),
        'paths[0].instructions[2].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j)[2]['interval'] = [6, 4]),
        'paths[0].instructions[2].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j).last['interval'] = [9, 10]),
        'paths[0].instructions[6].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j)[3]['interval'] = [3, 7]),
        'paths[0].instructions[3].interval',
      );
      await expectField(
        edited((j) => instructionsOf(j)[1]['street_name'] = 12),
        'paths[0].instructions[1].street_name',
      );
      await expectField(
        edited((j) => pathsOf(j)[1]['points'] = 7),
        'paths[1].points',
      );
    });

    test(
      'transport errors pass through, without the key in their URL',
      () async {
        final p = VietmapRouteProvider(
          apiKey: key,
          client: MockClient(
            (req) async => throw http.ClientException('offline', req.url),
          ),
        );
        final e = await _thrown<http.ClientException>(p.route(a, b));
        expect(e.message, 'offline');
        expect(e.uri, isNotNull);
        expect(e.uri!.path, '/api/route/v4');
        expect(e.uri!.queryParameters['apikey'], 'REDACTED');
        expect(e.uri!.queryParametersAll['point'], hasLength(2));
        expect(e.toString(), isNot(contains(key)));
      },
    );

    test('a transport error message that holds the key is scrubbed', () async {
      final p = VietmapRouteProvider(
        apiKey: key,
        client: MockClient(
          (_) async => throw http.ClientException('refused for apikey=$key'),
        ),
      );
      final e = await _thrown<http.ClientException>(p.route(a, b));
      expect(e.message, 'refused for apikey=REDACTED');
      expect(e.uri, isNull);
    });

    test('a transport error without a URL passes through unchanged', () async {
      final error = http.ClientException('offline');
      final p = VietmapRouteProvider(
        apiKey: key,
        client: MockClient((_) async => throw error),
      );
      await expectLater(p.route(a, b), throwsA(same(error)));
    });
  });

  group('timeout', () {
    test('a server that never answers times out and the request is '
        'aborted', () async {
      final requests = <http.BaseRequest>[];
      final p = VietmapRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((req, _) {
          requests.add(req);
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final e = await _thrown<VietmapTimeoutException>(p.routes(a, b));
      expect(e, isA<VietmapException>());
      expect(e, isA<TimeoutException>());
      expect(e.timeout, const Duration(milliseconds: 50));
      expect(e.duration, const Duration(milliseconds: 50));
      expect(e.message, contains('50 ms'));
      final trigger = (requests.single as http.Abortable).abortTrigger;
      expect(trigger, isNotNull);
      await trigger!.timeout(const Duration(seconds: 1));
    });

    test('a TimeoutException from the client is not reported as the '
        "provider's own timeout", () async {
      final p = VietmapRouteProvider(
        apiKey: key,
        timeout: const Duration(seconds: 5),
        client: MockClient((_) async => throw TimeoutException('inner')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<TimeoutException>()
              .having((e) => e, 'type', isNot(isA<VietmapTimeoutException>()))
              .having((e) => e.message, 'message', 'inner'),
        ),
      );
    });

    test('a body that stalls times out too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final p = VietmapRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((_, _) async {
          body.add(utf8.encode('{"code":"OK",'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      await _thrown<VietmapTimeoutException>(p.route(a, b));
    });

    test('a request in time is not aborted', () async {
      final requests = <http.BaseRequest>[];
      final body = fixture('route_alternatives.json');
      final p = VietmapRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 200),
        client: MockClient.streaming((req, _) async {
          requests.add(req);
          return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        }),
      );
      // No wall clock: the timers the request starts are held, and fired
      // by hand once it has answered, as if its timeout had passed.
      final timers = <_HeldTimer>[];
      await runZoned(
        () => p.route(a, b),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == Duration.zero) {
              return parent.createTimer(zone, duration, callback);
            }
            final timer = _HeldTimer(duration, () => zone.run(callback));
            timers.add(timer);
            return timer;
          },
        ),
      );
      var aborted = false;
      unawaited(
        (requests.single as http.Abortable).abortTrigger!.then(
          (_) => aborted = true,
        ),
      );
      expect(
        timers.map((t) => t.duration),
        contains(const Duration(milliseconds: 200)),
        reason: 'the timeout runs on a timer',
      );
      for (final t in timers) {
        t.fire();
      }
      await pumpEventQueue();
      expect(aborted, isFalse);
    });
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('route_alternatives.json')),
            200,
          ),
        ),
      );
      final p = VietmapRouteProvider(apiKey: key, client: client);
      await p.route(a, b);
      p.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the provider created', () async {
      final created = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('route_alternatives.json')),
            200,
          ),
        ),
      );
      final p = http.runWithClient(
        () => VietmapRouteProvider(apiKey: key),
        () => created,
      );
      await p.route(a, b);
      expect(created.closed, isFalse);
      p.close();
      expect(created.closed, isTrue);
      p.close();
    });

    test('a closed provider throws StateError', () async {
      final s = serve(fixture('route_alternatives.json'));
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

/// A timer that never runs by itself: [fire] runs it, unless it was
/// cancelled.
class _HeldTimer implements Timer {
  _HeldTimer(this.duration, this._callback);

  /// The duration it was created with.
  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  /// Runs the callback, as if [duration] had passed.
  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
