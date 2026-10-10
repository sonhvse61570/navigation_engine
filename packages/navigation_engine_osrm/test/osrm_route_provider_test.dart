import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';
import 'package:test/test.dart';

// Fixtures (test/fixtures):
// - route_alternatives.json: a response recorded from the public demo server
//   for Ben Thanh -> Landmark 81 (Ho Chi Minh City) with alternatives=2,
//   steps=true, geometries=geojson, overview=full and annotations=true.
//   Route data (c) OpenStreetMap contributors, ODbL 1.0.
// - route_steps.json / route_steps_polyline6.json: one hand-written route in
//   OSRM's format (geojson / polyline6 geometry), with the manoeuvres and
//   lanes that the recorded route lacks.
// - no_route.json, no_segment.json: OSRM's error bodies.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

/// The steps of the first leg of the first route of [json], to edit in place.
List<Map<String, Object?>> stepsOf(Map<String, Object?> json) {
  final route = (json['routes']! as List<Object?>).first! as Map;
  final leg = (route['legs']! as List<Object?>).first! as Map;
  return (leg['steps']! as List<Object?>).cast<Map<String, Object?>>();
}

/// The annotation of the first leg of the first route of [json].
Map<String, Object?> annotationOf(Map<String, Object?> json) {
  final route = (json['routes']! as List<Object?>).first! as Map;
  final leg = (route['legs']! as List<Object?>).first! as Map;
  return leg['annotation']! as Map<String, Object?>;
}

/// Its `maxspeed` list, to edit in place.
List<Object?> maxspeedOf(Map<String, Object?> json) =>
    annotationOf(json)['maxspeed']! as List<Object?>;

const a = GeoPoint(10.771897, 106.698226);
const b = GeoPoint(10.795172, 106.721646);

/// A provider whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({OsrmRouteProvider provider, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  Uri? baseUrl,
  String profile = 'driving',
  OsrmGeometries geometries = OsrmGeometries.geojson,
  bool speedLimits = false,
  String? userAgent = OsrmRouteProvider.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final provider = OsrmRouteProvider(
    baseUrl: baseUrl,
    profile: profile,
    geometries: geometries,
    speedLimits: speedLimits,
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

void main() {
  group('request', () {
    test('route() asks for one route with steps, full geometry and '
        'duration/distance annotations', () async {
      final s = serve(fixture('route_steps.json'));
      await s.provider.route(a, b);
      expect(s.requests, hasLength(1));
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.scheme, 'https');
      expect(req.url.host, 'router.project-osrm.org');
      expect(
        req.url.path,
        '/route/v1/driving/106.698226,10.771897;106.721646,10.795172',
      );
      expect(req.url.queryParameters, {
        'alternatives': 'false',
        'steps': 'true',
        'geometries': 'geojson',
        'overview': 'full',
        'annotations': 'duration,distance',
      });
      // Written as OSRM's documentation writes them, not percent-encoded.
      expect(req.url.query, contains('annotations=duration,distance'));
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], OsrmRouteProvider.defaultUserAgent);
    });

    test('routes() asks for maxAlternatives alternatives', () async {
      final s = serve(fixture('route_alternatives.json'));
      await s.provider.routes(a, b);
      await s.provider.routes(a, b, maxAlternatives: 1);
      await s.provider.routes(a, b, maxAlternatives: 3);
      await s.provider.routes(a, b, maxAlternatives: 0);
      expect(
        [for (final r in s.requests) r.url.queryParameters['alternatives']],
        ['2', '1', '3', 'false'],
      );
      for (final r in s.requests) {
        expect(r.url.queryParameters['steps'], 'true');
        expect(r.url.queryParameters['overview'], 'full');
        expect(r.url.queryParameters['annotations'], 'duration,distance');
      }
    });

    test('a negative maxAlternatives throws before any request', () async {
      final s = serve(fixture('route_alternatives.json'));
      await expectLater(
        s.provider.routes(a, b, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('the heading is sent as the bearing of the start only', () async {
      final s = serve(fixture('route_steps.json'));
      for (final h in [90.0, 0.0, -10.4, 359.6, 450.0, 271.5]) {
        await s.provider.route(a, b, heading: h);
      }
      await s.provider.routes(a, b, heading: 45);
      expect(
        [for (final r in s.requests) r.url.queryParameters['bearings']],
        ['90,45;', '0,45;', '350,45;', '0,45;', '90,45;', '272,45;', '45,45;'],
      );
      expect(s.requests.first.url.query, contains('bearings=90,45;'));
    });

    test(
      'no heading, or a heading that is not finite, sends no bearings',
      () async {
        final s = serve(fixture('route_steps.json'));
        await s.provider.route(a, b);
        await s.provider.route(a, b, heading: double.nan);
        await s.provider.routes(a, b, heading: double.infinity);
        for (final r in s.requests) {
          expect(r.url.queryParameters.containsKey('bearings'), isFalse);
        }
      },
    );

    test('baseUrl keeps its path; profile and geometries are used', () async {
      final s = serve(
        fixture('route_steps_polyline6.json'),
        baseUrl: Uri.parse('http://osrm.example.test:5000/osrm/'),
        profile: 'bike',
        geometries: OsrmGeometries.polyline6,
      );
      await s.provider.route(a, b);
      final url = s.requests.single.url;
      expect(url.scheme, 'http');
      expect(url.host, 'osrm.example.test');
      expect(url.port, 5000);
      expect(
        url.path,
        '/osrm/route/v1/bike/106.698226,10.771897;106.721646,10.795172',
      );
      expect(url.queryParameters['geometries'], 'polyline6');
    });

    test('baseUrl query parameters are kept', () async {
      final s = serve(
        fixture('route_steps.json'),
        baseUrl: Uri.parse('https://osrm.example.test/v5?api_key=demo'),
      );
      await s.provider.route(a, b, heading: 10);
      final url = s.requests.single.url;
      expect(
        url.path,
        '/v5/route/v1/driving/106.698226,10.771897;106.721646,10.795172',
      );
      expect(url.queryParameters['api_key'], 'demo');
      expect(url.queryParameters['bearings'], '10,45;');
      expect(url.queryParameters['steps'], 'true');
    });

    test('coordinates are written with six decimals', () async {
      final s = serve(fixture('route_steps.json'));
      await s.provider.route(
        const GeoPoint(1e-7, -0.5),
        const GeoPoint(-33.8688197, 151.2092957),
      );
      expect(
        s.requests.single.url.path,
        '/route/v1/driving/-0.500000,0.000000;151.209296,-33.868820',
      );
    });

    test('a coordinate that rounds to zero is not written as -0', () async {
      final s = serve(fixture('route_steps.json'));
      await s.provider.route(
        const GeoPoint(-1e-7, -4e-7),
        const GeoPoint(-0.5, 0.5),
      );
      expect(
        s.requests.single.url.path,
        '/route/v1/driving/0.000000,0.000000;0.500000,-0.500000',
      );
    });

    test('a coordinate that is not finite throws before any request', () async {
      final s = serve(fixture('route_steps.json'));
      await expectLater(
        s.provider.route(const GeoPoint(double.nan, 106.7), b),
        throwsArgumentError,
      );
      await expectLater(
        s.provider.routes(a, const GeoPoint(10.8, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('userAgent is sent as given; null sends none', () async {
      final custom = serve(
        fixture('route_steps.json'),
        userAgent: 'my_app/2.0',
      );
      await custom.provider.route(a, b);
      expect(custom.requests.single.headers['User-Agent'], 'my_app/2.0');

      final none = serve(fixture('route_steps.json'), userAgent: null);
      await none.provider.route(a, b);
      expect(none.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final p = OsrmRouteProvider(client: MockClient((_) async => throw 0));
      expect(p.baseUrl, Uri.parse('https://router.project-osrm.org'));
      expect(p.baseUrl, OsrmRouteProvider.demoServer);
      expect(p.profile, 'driving');
      expect(p.timeout, const Duration(seconds: 12));
      expect(p.geometries, OsrmGeometries.geojson);
      expect(p.userAgent, 'navigation_engine_osrm/0.1.0');
      expect(p.speedLimits, isFalse);
    });
  });

  group('alternatives', () {
    test('routes() returns the best route, then the alternative', () async {
      final routes = await serve(
        fixture('route_alternatives.json'),
      ).provider.routes(a, b, heading: 90);
      expect(routes, hasLength(2));
      expect(routes[0].duration, closeTo(496.4, 0.05));
      expect(routes[1].duration, closeTo(517.7, 0.05));
      expect(routes[0].length, closeTo(5468.4, 5));
      expect(routes[1].length, closeTo(6639.5, 6));
      expect(routes[0].points, hasLength(205));
      expect(routes[1].points, hasLength(202));
      expect(routes[0].summary, 'Lý Tự Trọng, Nguyễn Hữu Cảnh');
      expect(routes[1].summary, 'Nguyễn Thị Minh Khai, Điện Biên Phủ');
      expect(routes[0].steps, hasLength(14));
      expect(routes[1].steps, hasLength(16));
      expect(routes[0].points.first, const GeoPoint(10.771897, 106.698226));
    });

    test('routes() keeps at most maxAlternatives + 1 routes', () async {
      final s = serve(fixture('route_alternatives.json'));
      final routes = await s.provider.routes(a, b, maxAlternatives: 0);
      expect(routes, hasLength(1));
      expect(routes.single.duration, closeTo(496.4, 0.05));
    });

    test(
      'route() returns the best route even when the server sends more',
      () async {
        final r = await serve(
          fixture('route_alternatives.json'),
        ).provider.route(a, b);
        expect(r.duration, closeTo(496.4, 0.05));
        expect(r.summary, 'Lý Tự Trọng, Nguyễn Hữu Cảnh');
      },
    );
  });

  group('steps', () {
    test('the recorded routes: turns, new names, end of road, fork, '
        'roundabout and rotary', () async {
      final routes = await serve(
        fixture('route_alternatives.json'),
      ).provider.routes(a, b);
      expect(view(routes[0]), <StepView>[
        (
          ManeuverType.depart,
          ManeuverModifier.none,
          'Công trường Quách Thị Trang',
        ),
        (ManeuverType.newName, ManeuverModifier.slightRight, 'Lê Lai'),
        (ManeuverType.turn, ManeuverModifier.right, 'Trương Định'),
        (ManeuverType.turn, ManeuverModifier.right, 'Lý Tự Trọng'),
        (ManeuverType.endOfRoad, ManeuverModifier.right, 'Tôn Đức Thắng'),
        (ManeuverType.continueOn, ManeuverModifier.uturn, 'Tôn Đức Thắng'),
        (ManeuverType.turn, ManeuverModifier.slightRight, 'Nguyễn Hữu Cảnh'),
        (ManeuverType.fork, ManeuverModifier.slightRight, 'Nguyễn Hữu Cảnh'),
        (
          ManeuverType.roundabout,
          ManeuverModifier.slightRight,
          'Nguyễn Hữu Cảnh',
        ),
        (
          ManeuverType.exitRoundabout,
          ManeuverModifier.right,
          'Nguyễn Hữu Cảnh',
        ),
        (ManeuverType.turn, ManeuverModifier.right, ''),
        (ManeuverType.turn, ManeuverModifier.straight, 'Vạn Hoa 4'),
        (ManeuverType.turn, ManeuverModifier.right, ''),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(view(routes[1]).sublist(2, 6), <StepView>[
        (ManeuverType.turn, ManeuverModifier.slightRight, 'Phạm Hồng Thái'),
        (
          ManeuverType.roundabout,
          ManeuverModifier.slightRight,
          'Cách Mạng Tháng Tám',
        ),
        (
          ManeuverType.exitRoundabout,
          ManeuverModifier.straight,
          'Cách Mạng Tháng Tám',
        ),
        (ManeuverType.turn, ManeuverModifier.right, 'Nguyễn Thị Minh Khai'),
      ]);
      expect(view(routes[1]).sublist(6, 11), <StepView>[
        (ManeuverType.newName, ManeuverModifier.straight, 'Cầu Thị Nghè 1'),
        (ManeuverType.newName, ManeuverModifier.straight, 'Xô Viết Nghệ Tĩnh'),
        (ManeuverType.roundabout, ManeuverModifier.right, 'Điện Biên Phủ'),
        (ManeuverType.exitRoundabout, ManeuverModifier.right, 'Điện Biên Phủ'),
        (
          ManeuverType.continueOn,
          ManeuverModifier.slightRight,
          'Điện Biên Phủ',
        ),
      ]);
      for (final r in routes) {
        expect(r.steps.every((s) => s.lanes.isEmpty), isTrue);
      }
    });

    test('ramps, merge, notification, use lane, fork, end of road and '
        'roundabout turn', () async {
      final r = await serve(fixture('route_steps.json')).provider.route(a, b);
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Nguyễn Văn Trỗi'),
        (ManeuverType.onRamp, ManeuverModifier.slightRight, 'CT01'),
        (ManeuverType.merge, ManeuverModifier.slightLeft, 'Cao tốc Long Thành'),
        (
          ManeuverType.continueOn,
          ManeuverModifier.straight,
          'Cao tốc Long Thành',
        ),
        (
          ManeuverType.continueOn,
          ManeuverModifier.straight,
          'Cao tốc Long Thành',
        ),
        (ManeuverType.fork, ManeuverModifier.slightLeft, 'Cao tốc Long Thành'),
        (ManeuverType.offRamp, ManeuverModifier.slightRight, ''),
        (ManeuverType.endOfRoad, ManeuverModifier.left, 'Phạm Văn Đồng'),
        (ManeuverType.turn, ManeuverModifier.left, 'Võ Văn Ngân'),
        (ManeuverType.arrive, ManeuverModifier.left, 'Võ Văn Ngân'),
      ]);
    });

    test('the road name falls back to ref', () async {
      final json = fixtureJson('route_steps.json');
      final steps = stepsOf(json);
      steps[0]
        ..['name'] = ''
        ..['ref'] = 'QL1A';
      steps[1]
        ..['name'] = 'Ramp Road'
        ..['ref'] = 'CT01';
      steps[2]
        ..remove('name')
        ..['ref'] = 'AH1';
      steps[3]
        ..['name'] = ''
        ..remove('ref');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(
        [for (final s in r.steps.take(4)) s.roadName],
        ['QL1A', 'Ramp Road', 'AH1', ''],
      );
    });

    test('every OSRM type and modifier', () async {
      const types = {
        'turn': ManeuverType.turn,
        'new name': ManeuverType.newName,
        'depart': ManeuverType.depart,
        'arrive': ManeuverType.arrive,
        'merge': ManeuverType.merge,
        'on ramp': ManeuverType.onRamp,
        'off ramp': ManeuverType.offRamp,
        'fork': ManeuverType.fork,
        'end of road': ManeuverType.endOfRoad,
        'use lane': ManeuverType.continueOn,
        'continue': ManeuverType.continueOn,
        'roundabout': ManeuverType.roundabout,
        'rotary': ManeuverType.roundabout,
        'roundabout turn': ManeuverType.turn,
        'notification': ManeuverType.continueOn,
        'exit roundabout': ManeuverType.exitRoundabout,
        'exit rotary': ManeuverType.exitRoundabout,
        // OSRM: a type the client does not know is handled like a turn.
        'some future type': ManeuverType.turn,
      };
      const modifiers = {
        'uturn': ManeuverModifier.uturn,
        'sharp right': ManeuverModifier.sharpRight,
        'right': ManeuverModifier.right,
        'slight right': ManeuverModifier.slightRight,
        'straight': ManeuverModifier.straight,
        'slight left': ManeuverModifier.slightLeft,
        'left': ManeuverModifier.left,
        'sharp left': ManeuverModifier.sharpLeft,
        'sideways': ManeuverModifier.none,
      };
      Future<RouteStep> step(String type, String? modifier) async {
        final json = fixtureJson('route_steps.json');
        final maneuver = stepsOf(json)[4]['maneuver']! as Map<String, Object?>;
        maneuver['type'] = type;
        if (modifier == null) {
          maneuver.remove('modifier');
        } else {
          maneuver['modifier'] = modifier;
        }
        final r = await serve(jsonEncode(json)).provider.route(a, b);
        return r.steps[4];
      }

      for (final MapEntry(:key, :value) in types.entries) {
        expect((await step(key, 'left')).type, value, reason: key);
      }
      for (final MapEntry(:key, :value) in modifiers.entries) {
        expect((await step('turn', key)).modifier, value, reason: key);
      }
      expect((await step('turn', null)).modifier, ManeuverModifier.none);
    });

    test('lanes come from the manoeuvre\'s intersection', () async {
      final r = await serve(fixture('route_steps.json')).provider.route(a, b);
      const s = LaneDirection.straight;
      expect(r.steps[0].lanes, isEmpty);
      // The on ramp's second intersection has lanes of its own: not used.
      expect(r.steps[1].lanes, const [
        Lane(directions: {s}),
        Lane(
          directions: {s, LaneDirection.slightRight},
          valid: true,
          active: LaneDirection.slightRight,
        ),
      ]);
      expect(r.steps[2].lanes, isEmpty);
      expect(r.steps[4].lanes, const [
        Lane(directions: {LaneDirection.left}),
        Lane(directions: {s}, valid: true, active: s),
        Lane(directions: {s, LaneDirection.right}, valid: true, active: s),
      ]);
      expect(r.steps[5].lanes, const [
        Lane(
          directions: {LaneDirection.slightLeft},
          valid: true,
          active: LaneDirection.slightLeft,
        ),
        Lane(directions: {LaneDirection.slightRight}),
      ]);
      // "none": no arrow painted, so a straight one.
      expect(r.steps[6].lanes, const [
        Lane(directions: {s}),
        Lane(directions: {s}, valid: true, active: s),
      ]);
      expect(r.steps[7].lanes, const [
        Lane(
          directions: {LaneDirection.left},
          valid: true,
          active: LaneDirection.left,
        ),
        Lane(directions: {LaneDirection.right}),
      ]);
      expect(r.steps[1].lanes, isA<List<Lane>>());
      expect(
        () => r.steps[1].lanes.add(const Lane(directions: {})),
        throwsUnsupportedError,
      );
    });

    test('a valid lane\'s arrow: valid_indication, else the one the '
        'manoeuvre follows, else the first', () async {
      final json = fixtureJson('route_steps.json');
      final intersection =
          (stepsOf(json)[4]['intersections']! as List<Object?>).first!
              as Map<String, Object?>;
      intersection['lanes'] = [
        {
          'indications': ['straight', 'right'],
          'valid': true,
          'valid_indication': 'right',
        },
        {
          'indications': ['left', 'slight left'],
          'valid': true,
        },
        {'indications': <String>[], 'valid': true},
        {
          'indications': ['uturn', 'sharp left', 'sharp right'],
        },
      ];
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[4].modifier, ManeuverModifier.straight);
      expect(r.steps[4].lanes, const [
        Lane(
          directions: {LaneDirection.straight, LaneDirection.right},
          valid: true,
          active: LaneDirection.right,
        ),
        Lane(
          directions: {LaneDirection.left, LaneDirection.slightLeft},
          valid: true,
          active: LaneDirection.left,
        ),
        Lane(
          directions: {LaneDirection.straight},
          valid: true,
          active: LaneDirection.straight,
        ),
        Lane(
          directions: {
            LaneDirection.uturn,
            LaneDirection.sharpLeft,
            LaneDirection.sharpRight,
          },
        ),
      ]);
    });

    test('step distances are measured along the route', () async {
      final r = await serve(fixture('route_steps.json')).provider.route(a, b);
      // OSRM's own step distances, summed: where each manoeuvre is.
      final osrm = <double>[0];
      for (final s in stepsOf(fixtureJson('route_steps.json'))) {
        osrm.add(osrm.last + (s['distance']! as num).toDouble());
      }
      expect(r.steps.first.distance, 0);
      expect(r.steps.last.distance, r.length);
      for (var i = 0; i < r.steps.length; i++) {
        // NavRoute measures in its own planar frame: within 0.2 %.
        expect(
          r.steps[i].distance,
          closeTo(osrm[i], 1 + osrm[i] * 0.002),
          reason: '$i',
        );
      }
      // The vertices of the manoeuvres.
      final vertices = [0, 2, 4, 5, 6, 7, 8, 10, 12, 14];
      for (var i = 0; i < vertices.length; i++) {
        expect(
          r.pointAt(r.steps[i].distance).lat,
          closeTo(r.points[vertices[i]].lat, 1e-9),
        );
      }
    });

    test(
      'a step whose location revisits the road is placed in order',
      () async {
        final routes = await serve(
          fixture('route_alternatives.json'),
        ).provider.routes(a, b);
        final distances = [for (final s in routes[0].steps) s.distance];
        for (var i = 1; i < distances.length; i++) {
          expect(distances[i], greaterThanOrEqualTo(distances[i - 1]));
        }
      },
    );
  });

  group('durations', () {
    test('per-segment durations are the annotation durations, scaled to the '
        'leg duration', () async {
      final r = await serve(fixture('route_steps.json')).provider.route(a, b);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(173.6, 1e-9));
      const raw = [10.1, 9.7, 9.6, 10.5, 14.3, 14.7, 14.2, 14.3, 10.7, 12.1];
      const k = 173.6 / 164.6;
      // At the on ramp (vertex 2) and the end of the road (vertex 10).
      expect(
        r.durationAt(r.steps[1].distance),
        closeTo((10.1 + 9.7) * k, 1e-9),
      );
      expect(
        r.durationAt(r.steps[7].distance),
        closeTo(raw.fold<double>(0, (s, d) => s + d) * k, 1e-9),
      );
    });

    test('the recorded routes keep OSRM\'s durations', () async {
      final routes = await serve(
        fixture('route_alternatives.json'),
      ).provider.routes(a, b);
      expect(routes.every((r) => r.hasProviderDurations), isTrue);
    });

    test('without annotations, or with a count that does not match the '
        'geometry, the durations are estimated', () async {
      final none = fixtureJson('route_steps.json');
      final leg =
          (((none['routes']! as List).first! as Map)['legs']! as List).first!
              as Map<String, Object?>;
      leg.remove('annotation');
      final r1 = await serve(jsonEncode(none)).provider.route(a, b);
      expect(r1.hasProviderDurations, isFalse);
      expect(r1.steps, hasLength(10));

      final short = fixtureJson('route_steps.json');
      final annotation =
          ((((short['routes']! as List).first! as Map)['legs']! as List).first!
                  as Map)['annotation']!
              as Map<String, Object?>;
      (annotation['duration']! as List).removeLast();
      final r2 = await serve(jsonEncode(short)).provider.route(a, b);
      expect(r2.hasProviderDurations, isFalse);
    });

    test('annotations that sum to 0 are kept only for a leg of 0 s', () async {
      Future<NavRoute> zeros({required double legDuration}) async {
        final json = fixtureJson('route_steps.json');
        final leg =
            (((json['routes']! as List).first! as Map)['legs']! as List).first!
                as Map<String, Object?>;
        final annotation = leg['annotation']! as Map<String, Object?>;
        annotation['duration'] = [
          for (final _ in annotation['duration']! as List) 0,
        ];
        leg['duration'] = legDuration;
        return serve(jsonEncode(json)).provider.route(a, b);
      }

      final still = await zeros(legDuration: 0);
      expect(still.hasProviderDurations, isTrue);
      expect(still.duration, 0);

      final broken = await zeros(legDuration: 173.6);
      expect(broken.hasProviderDurations, isFalse);
      expect(broken.duration, greaterThan(0));
    });
  });

  group('speed limits', () {
    const kmh = 1 / 3.6;
    const mph = 0.44704;

    /// The limit on the segment that starts at step [k]'s manoeuvre.
    double? limitAfter(NavRoute r, int k) =>
        r.speedLimitAt(r.steps[k].distance + 1);

    test('maxspeed in km/h and mph; unknown and none are no limit', () async {
      final s = serve(fixture('route_speed_limits.json'), speedLimits: true);
      final r = await s.provider.route(a, b);
      // OSRM's grammar has no `maxspeed` value: only `true` returns it.
      expect(s.requests.single.url.queryParameters['annotations'], 'true');
      expect(limitAfter(r, 0), closeTo(40 * kmh, 1e-9)); // segment 0
      expect(limitAfter(r, 1), closeTo(60 * kmh, 1e-9)); // segment 2
      expect(limitAfter(r, 2), closeTo(100 * kmh, 1e-9)); // segment 4
      expect(limitAfter(r, 3), closeTo(65 * mph, 1e-9)); // segment 5
      expect(limitAfter(r, 6), isNull); // segment 8: {unknown: true}
      expect(limitAfter(r, 7), isNull); // segment 10: {none: true}
      expect(limitAfter(r, 8), closeTo(30 * mph, 1e-9)); // segment 12
      // The durations still come from the annotations.
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(173.6, 1e-9));
    });

    test(
      'by default (speedLimits off), maxspeed is neither asked for nor read',
      () async {
        final requests = <http.Request>[];
        final body = fixture('route_speed_limits.json');
        final provider = OsrmRouteProvider(
          client: MockClient((req) async {
            requests.add(req);
            return http.Response.bytes(utf8.encode(body), 200);
          }),
        );
        final r = await provider.route(a, b);
        expect(
          requests.single.url.queryParameters['annotations'],
          'duration,distance',
        );
        for (var k = 0; k < r.steps.length; k++) {
          expect(limitAfter(r, k), isNull, reason: '$k');
        }
        expect(r.hasProviderDurations, isTrue);
      },
    );

    test('no maxspeed, or a count that does not match, is no limit', () async {
      final none = await serve(
        fixture('route_steps.json'),
        speedLimits: true,
      ).provider.route(a, b);
      expect(limitAfter(none, 0), isNull);

      final json = fixtureJson('route_speed_limits.json');
      (maxspeedOf(json)).removeLast();
      final short = await serve(
        jsonEncode(json),
        speedLimits: true,
      ).provider.route(a, b);
      expect(limitAfter(short, 0), isNull);
      expect(short.hasProviderDurations, isTrue);
    });

    test('a speed that is not positive is no limit', () async {
      final json = fixtureJson('route_speed_limits.json');
      final limits = maxspeedOf(json);
      limits[0] = {'speed': 0, 'unit': 'km/h'};
      limits[2] = {'speed': -5, 'unit': 'mph'};
      final r = await serve(
        jsonEncode(json),
        speedLimits: true,
      ).provider.route(a, b);
      expect(limitAfter(r, 0), isNull);
      expect(limitAfter(r, 1), isNull);
      expect(limitAfter(r, 3), closeTo(65 * mph, 1e-9));
    });

    test('a malformed maxspeed throws OsrmFormatException', () async {
      for (final (entry, field) in [
        ('fast', 'maxspeed[3]'),
        ({'speed': 'fast', 'unit': 'km/h'}, 'maxspeed[3].speed'),
        ({'speed': 50, 'unit': 7}, 'maxspeed[3].unit'),
      ]) {
        final json = fixtureJson('route_speed_limits.json');
        maxspeedOf(json)[3] = entry;
        final e = await _thrown<OsrmFormatException>(
          serve(jsonEncode(json), speedLimits: true).provider.route(a, b),
        );
        expect(
          e.message,
          contains('routes[0].legs[0].annotation.$field'),
          reason: '$entry',
        );
      }
      final json = fixtureJson('route_speed_limits.json');
      annotationOf(json)['maxspeed'] = 'none';
      final e = await _thrown<OsrmFormatException>(
        serve(jsonEncode(json), speedLimits: true).provider.route(a, b),
      );
      expect(e.message, contains('routes[0].legs[0].annotation.maxspeed'));
    });
  });

  group('polyline6', () {
    test('decodes to the same route as geojson', () async {
      final geo = await serve(fixture('route_steps.json')).provider.route(a, b);
      final poly = await serve(
        fixture('route_steps_polyline6.json'),
        geometries: OsrmGeometries.polyline6,
      ).provider.route(a, b);
      expect(poly.points, hasLength(geo.points.length));
      for (var i = 0; i < geo.points.length; i++) {
        expect(poly.points[i].lat, closeTo(geo.points[i].lat, 1e-9));
        expect(poly.points[i].lng, closeTo(geo.points[i].lng, 1e-9));
      }
      expect(view(poly), view(geo));
      expect(poly.duration, closeTo(geo.duration, 1e-9));
      for (var i = 0; i < geo.steps.length; i++) {
        expect(poly.steps[i].distance, closeTo(geo.steps[i].distance, 1e-6));
        expect(poly.steps[i].lanes, geo.steps[i].lanes);
      }
    });

    test('negative coordinates and large jumps decode', () async {
      // From the polyline algorithm's documentation, at precision 5 the
      // points (38.5, -120.2), (40.7, -120.95), (43.252, -126.453) encode as
      // "_p~iF~ps|U_ulLnnqC_mqNvxq`@"; at precision 6 they are:
      final json = fixtureJson('route_steps_polyline6.json');
      final route = (json['routes']! as List).first! as Map<String, Object?>;
      route['geometry'] = '_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI';
      final leg = (route['legs']! as List).first! as Map<String, Object?>;
      leg.remove('annotation');
      leg['steps'] = <Object?>[];
      final r = await serve(
        jsonEncode(json),
        geometries: OsrmGeometries.polyline6,
      ).provider.route(a, b);
      expect(r.points, hasLength(3));
      expect(r.points[0].lat, closeTo(38.5, 1e-9));
      expect(r.points[0].lng, closeTo(-120.2, 1e-9));
      expect(r.points[1].lat, closeTo(40.7, 1e-9));
      expect(r.points[1].lng, closeTo(-120.95, 1e-9));
      expect(r.points[2].lat, closeTo(43.252, 1e-9));
      expect(r.points[2].lng, closeTo(-126.453, 1e-9));
    });
  });

  group('errors', () {
    test('NoRoute throws OsrmCodeException with a clear message', () async {
      final s = serve(fixture('no_route.json'), status: 400);
      final e = await _thrown<OsrmCodeException>(s.provider.routes(a, b));
      expect(e, isA<OsrmException>());
      expect(e.code, 'NoRoute');
      expect(e.serverMessage, 'Impossible route between points');
      expect(e.statusCode, 400);
      expect(e.message, contains('NoRoute'));
      expect(e.message, contains('no route between the points'));
      expect(e.message, contains('Impossible route between points'));
      expect(e.toString(), startsWith('OsrmCodeException: '));
    });

    test('NoSegment throws OsrmCodeException with a clear message', () async {
      final s = serve(fixture('no_segment.json'), status: 400);
      final e = await _thrown<OsrmCodeException>(s.provider.route(a, b));
      expect(e.code, 'NoSegment');
      expect(e.statusCode, 400);
      expect(e.message, contains('NoSegment'));
      expect(e.message, contains('not near a road'));
    });

    test('other codes, and codes in an HTTP 200 response', () async {
      const cases = {
        'TooBig': 'too big',
        'InvalidQuery': 'rejected the request',
        'InvalidOptions': 'rejected the request',
        'InvalidValue': 'rejected the request',
        'InvalidUrl': 'rejected the request',
        'InvalidService': 'rejected the request',
        'InvalidVersion': 'rejected the request',
        'NotImplemented': 'does not support',
        'SomethingNew': 'SomethingNew',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final s = serve(jsonEncode({'code': key}));
        final e = await _thrown<OsrmCodeException>(s.provider.route(a, b));
        expect(e.code, key);
        expect(e.statusCode, 200);
        expect(e.serverMessage, isNull);
        expect(e.message, contains(value), reason: key);
      }
    });

    test(
      'an HTTP error without an OSRM code throws OsrmHttpException',
      () async {
        final odd = serve('{"code":"NoRoute","message":42}', status: 400);
        final e0 = await _thrown<OsrmCodeException>(odd.provider.route(a, b));
        expect(e0.serverMessage, isNull);

        final html = serve('<html>Bad Gateway</html>', status: 502);
        final e1 = await _thrown<OsrmHttpException>(html.provider.route(a, b));
        expect(e1, isA<OsrmException>());
        expect(e1.statusCode, 502);
        expect(e1.message, contains('502'));

        final limited = serve('{"message":"Too Many Requests"}', status: 429);
        final e2 = await _thrown<OsrmHttpException>(
          limited.provider.route(a, b),
        );
        expect(e2.statusCode, 429);
        expect(e2.message, contains('429'));
        expect(e2.message, contains('Too Many Requests'));
      },
    );

    test('the body excerpt does not split a character', () async {
      final body = '${'a' * 199}😀${'b' * 10}';
      final e = await _thrown<OsrmHttpException>(
        serve(body, status: 502).provider.route(a, b),
      );
      expect(e.message, contains('a😀…'));
      expect(e.message, isNot(contains('b')));
    });

    test('malformed JSON throws OsrmFormatException', () async {
      for (final body in [
        '{"code":"Ok","routes":[',
        '',
        '<html>ok</html>',
        '[1, 2]',
        '"Ok"',
      ]) {
        final e = await _thrown<OsrmFormatException>(
          serve(body).provider.route(a, b),
        );
        expect(e, isA<OsrmException>());
        expect(e.message, isNotEmpty);
      }
    });

    test('a body that is not UTF-8 throws OsrmFormatException', () async {
      final p = OsrmRouteProvider(
        client: MockClient(
          (_) async => http.Response.bytes([0x7b, 0xff, 0xfe, 0x7d], 200),
        ),
      );
      await _thrown<OsrmFormatException>(p.route(a, b));
    });

    test('an unexpected shape names the field', () async {
      Future<OsrmFormatException> broken(
        void Function(Map<String, Object?> json) edit,
      ) async {
        final json = fixtureJson('route_steps.json');
        edit(json);
        return _thrown<OsrmFormatException>(
          serve(jsonEncode(json)).provider.route(a, b),
        );
      }

      Map<String, Object?> route0(Map<String, Object?> j) =>
          (j['routes']! as List).first! as Map<String, Object?>;

      var e = await broken((j) => j.remove('routes'));
      expect(e.message, contains('routes'));

      e = await broken((j) => j['routes'] = <Object?>[]);
      expect(e.message, contains('no routes'));

      e = await broken((j) => route0(j).remove('geometry'));
      expect(e.message, contains('routes[0].geometry'));

      e = await broken(
        (j) => (route0(j)['geometry']! as Map)['coordinates'] = [
          [106.7, 10.8],
        ],
      );
      expect(e.message, contains('routes[0].geometry'));

      e = await broken((j) => stepsOf(j)[3]['maneuver'] = 'left');
      expect(e.message, contains('routes[0].legs[0].steps[3].maneuver'));

      e = await broken(
        (j) => (stepsOf(j)[2]['maneuver']! as Map)['location'] = [106.7],
      );
      expect(
        e.message,
        contains('routes[0].legs[0].steps[2].maneuver.location'),
      );

      e = await broken((j) => (stepsOf(j)[2]['maneuver']! as Map)['type'] = 3);
      expect(e.message, contains('routes[0].legs[0].steps[2].maneuver.type'));

      e = await broken(
        (j) =>
            ((stepsOf(j)[1]['intersections']! as List).first! as Map)['lanes'] =
                'none',
      );
      expect(
        e.message,
        contains('routes[0].legs[0].steps[1].intersections[0].lanes'),
      );

      e = await broken((j) {
        final leg = (route0(j)['legs']! as List).first! as Map;
        (leg['annotation']! as Map)['duration'] = 'fast';
      });
      expect(e.message, contains('routes[0].legs[0].annotation.duration'));

      e = await broken((j) {
        final leg = (route0(j)['legs']! as List).first! as Map;
        ((leg['annotation']! as Map)['duration']! as List)[0] = -1;
      });
      expect(e.message, contains('routes[0].legs[0].annotation.duration[0]'));
      expect(e.message, contains('negative'));
    });

    test('a polyline6 geometry that is not a string, or is cut short, throws '
        'OsrmFormatException', () async {
      for (final geometry in [
        <String, Object?>{'type': 'LineString', 'coordinates': <Object?>[]},
        '_izlhA~rlgdF_{geC~ywl@_kwzC',
        '_izlhA~rlgdF_',
      ]) {
        final json = fixtureJson('route_steps_polyline6.json');
        ((json['routes']! as List).first! as Map)['geometry'] = geometry;
        final e = await _thrown<OsrmFormatException>(
          serve(
            jsonEncode(json),
            geometries: OsrmGeometries.polyline6,
          ).provider.route(a, b),
        );
        expect(e.message, contains('routes[0].geometry'));
      }
    });

    test('transport errors pass through unchanged', () async {
      final p = OsrmRouteProvider(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            'offline',
          ),
        ),
      );
    });
  });

  group('timeout', () {
    test('a server that never answers times out and the request is '
        'aborted', () async {
      final requests = <http.BaseRequest>[];
      final p = OsrmRouteProvider(
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((req, _) {
          requests.add(req);
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final e = await _thrown<OsrmTimeoutException>(p.routes(a, b));
      expect(e, isA<OsrmException>());
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
      final p = OsrmRouteProvider(
        timeout: const Duration(seconds: 5),
        client: MockClient((_) async => throw TimeoutException('inner')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<TimeoutException>()
              .having((e) => e, 'type', isNot(isA<OsrmTimeoutException>()))
              .having((e) => e.message, 'message', 'inner'),
        ),
      );
    });

    test('a body that stalls times out too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final p = OsrmRouteProvider(
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((_, _) async {
          body.add(utf8.encode('{"code":"Ok",'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      await _thrown<OsrmTimeoutException>(p.route(a, b));
    });

    test('a request in time is not aborted', () async {
      final requests = <http.BaseRequest>[];
      final body = fixture('route_steps.json');
      final p = OsrmRouteProvider(
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
            utf8.encode(fixture('route_steps.json')),
            200,
          ),
        ),
      );
      final p = OsrmRouteProvider(client: client);
      await p.route(a, b);
      p.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the provider created', () async {
      final created = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('route_steps.json')),
            200,
          ),
        ),
      );
      final p = http.runWithClient(OsrmRouteProvider.new, () => created);
      await p.route(a, b);
      expect(created.closed, isFalse);
      p.close();
      expect(created.closed, isTrue);
      p.close();
    });

    test('a closed provider throws StateError', () async {
      final s = serve(fixture('route_steps.json'));
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
