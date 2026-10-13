import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_google_maps/navigation_google_maps.dart';

// Fixtures (test/routing/fixtures), all hand-written in the shape of the
// Routes API v2 reference
// (https://developers.google.com/maps/documentation/routes/reference/rest/v2/TopLevel/computeRoutes);
// none was recorded, and none holds a key:
// - compute_routes.json: two routes in Ho Chi Minh City, as the field mask
//   asks for them. The first (DEFAULT_ROUTE) has DEPART, TURN_LEFT and
//   TURN_RIGHT steps; the second (DEFAULT_ROUTE_ALTERNATE) a first step
//   without a manoeuvre, a ROUNDABOUT_RIGHT, a NAME_CHANGE step of one
//   point with no distanceMeters and no staticDuration (Google omits zero
//   values) and a STRAIGHT step.
// - no_route.json: `{}`, Google's answer when there is no route.
// - error_invalid_argument.json, error_permission_denied.json,
//   error_resource_exhausted.json: Google RPC error bodies.

String fixture(String name) =>
    File('test/routing/fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

/// The routes of [json], to edit in place.
List<Map<String, Object?>> routesOf(Map<String, Object?> json) =>
    (json['routes']! as List<Object?>).cast<Map<String, Object?>>();

/// The steps of the first leg of [route], to edit in place.
List<Map<String, Object?>> stepsOf(Map<String, Object?> route) =>
    (((route['legs']! as List<Object?>).first!
                as Map<String, Object?>)['steps']!
            as List<Object?>)
        .cast<Map<String, Object?>>();

const a = GeoPoint(10.77243, 106.69805); // Ben Thanh Market
const b = GeoPoint(10.77978, 106.69902); // Notre-Dame Cathedral

/// A fake key: requests must carry it, messages must not.
const key = 'test-key';

/// The field mask the provider must send, as briefed.
const mask =
    'routes.distanceMeters,routes.duration,routes.staticDuration,'
    'routes.polyline.encodedPolyline,routes.routeLabels,'
    'routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,'
    'routes.legs.steps.polyline.encodedPolyline,'
    'routes.legs.steps.navigationInstruction';

/// A provider whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({GoogleRoutesRouteProvider provider, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? reasonPhrase,
  String? apiKey = key,
  Uri? routesBaseUrl,
  GoogleTravelMode travelMode = GoogleTravelMode.drive,
  GoogleRoutingPreference routingPreference =
      GoogleRoutingPreference.trafficAware,
  String? languageCode,
  bool alternatives = true,
  bool sendHeading = true,
  Map<String, String> headers = const {},
  String? userAgent = GoogleRoutesRouteProvider.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final provider = GoogleRoutesRouteProvider(
    apiKey: apiKey,
    routesBaseUrl: routesBaseUrl,
    travelMode: travelMode,
    routingPreference: routingPreference,
    languageCode: languageCode,
    alternatives: alternatives,
    sendHeading: sendHeading,
    headers: headers,
    userAgent: userAgent,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        reasonPhrase: reasonPhrase,
        headers: {'content-type': 'application/json; charset=UTF-8'},
      );
    }),
  );
  return (provider: provider, requests: requests);
}

/// The JSON body of [request].
Map<String, Object?> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

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

/// The vertex index of each step of [r].
List<int> vertices(NavRoute r) => [
  for (final s in r.steps)
    [for (var i = 0; i < r.points.length; i++) i]
        .firstWhere((i) => r.distanceAtVertex(i) == s.distance),
];

/// The seconds of each segment of [r].
List<double> segmentSeconds(NavRoute r) => [
  for (var i = 0; i + 1 < r.points.length; i++)
    r.durationAt(r.distanceAtVertex(i + 1)) -
        r.durationAt(r.distanceAtVertex(i)),
];

void main() {
  group('request', () {
    test('route() POSTs computeRoutes with the key and the field mask '
        'headers, and the documented body', () async {
      final s = serve(fixture('compute_routes.json'));
      await s.provider.route(a, b);
      expect(s.requests, hasLength(1));
      final req = s.requests.single;
      expect(req.method, 'POST');
      expect(
        req.url.toString(),
        'https://routes.googleapis.com/directions/v2:computeRoutes',
      );
      expect(req.headers['X-Goog-Api-Key'], 'test-key');
      expect(req.headers['X-Goog-FieldMask'], mask);
      expect(GoogleRoutesRouteProvider.fieldMask, mask);
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], 'navigation_google_maps/0.1.0');
      expect(bodyOf(req), {
        'origin': {
          'location': {
            'latLng': {'latitude': 10.77243, 'longitude': 106.69805},
          },
        },
        'destination': {
          'location': {
            'latLng': {'latitude': 10.77978, 'longitude': 106.69902},
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
        'polylineQuality': 'HIGH_QUALITY',
        'polylineEncoding': 'ENCODED_POLYLINE',
      });
      // The key is in a header, never in the URL.
      expect(req.url.hasQuery, isFalse);
    });

    test('routes() asks for alternatives; the heading is the origin\'s, an '
        'integer 0..359, and the destination has none', () async {
      final s = serve(fixture('compute_routes.json'));
      await s.provider.routes(a, b, heading: 90.4);
      final body = bodyOf(s.requests.single);
      expect(body['computeAlternativeRoutes'], isTrue);
      expect(body['origin'], {
        'location': {
          'latLng': {'latitude': 10.77243, 'longitude': 106.69805},
          'heading': 90,
        },
      });
      expect(
        (body['destination']! as Map<String, Object?>)['location'],
        isNot(contains('heading')),
      );
    });

    test('the heading is normalised to 0..359, and one that is not finite '
        'sends none', () async {
      final s = serve(fixture('compute_routes.json'));
      for (final heading in [
        359.6,
        -90.0,
        720.0,
        double.nan,
        double.infinity,
        null,
      ]) {
        await s.provider.route(a, b, heading: heading);
      }
      expect(
        [
          for (final r in s.requests)
            ((bodyOf(r)['origin']! as Map)['location']! as Map)['heading'],
        ],
        [0, 270, 0, null, null, null],
      );
      for (final r in s.requests.skip(3)) {
        expect(((bodyOf(r)['origin']! as Map)['location']! as Map).keys, [
          'latLng',
        ]);
      }
    });

    test('sendHeading: false sends no heading, whatever the engine passes, '
        'for route() and routes(); true (the default) sends it', () async {
      final off = serve(fixture('compute_routes.json'), sendHeading: false);
      await off.provider.route(a, b, heading: 90);
      await off.provider.routes(a, b, heading: 90);
      for (final r in off.requests) {
        expect(((bodyOf(r)['origin']! as Map)['location']! as Map).keys, [
          'latLng',
        ]);
      }
      expect(off.requests, hasLength(2));
      final on = serve(fixture('compute_routes.json'));
      expect(on.provider.sendHeading, isTrue);
      await on.provider.route(a, b, heading: 90);
      expect(
        ((bodyOf(on.requests.single)['origin']! as Map)['location']!
            as Map)['heading'],
        90,
      );
    });

    test('travel mode, routing preference and language code', () async {
      final s = serve(
        fixture('compute_routes.json'),
        travelMode: GoogleTravelMode.twoWheeler,
        routingPreference: GoogleRoutingPreference.trafficUnaware,
        languageCode: 'vi',
      );
      await s.provider.route(a, b);
      final body = bodyOf(s.requests.single);
      expect(body['travelMode'], 'TWO_WHEELER');
      // The docs allow routingPreference with DRIVE and TWO_WHEELER.
      expect(body['routingPreference'], 'TRAFFIC_UNAWARE');
      expect(body['languageCode'], 'vi');
      expect(
        [for (final m in GoogleTravelMode.values) m.id],
        ['DRIVE', 'TWO_WHEELER'],
      );
      expect(
        [for (final p in GoogleRoutingPreference.values) p.id],
        ['TRAFFIC_AWARE', 'TRAFFIC_UNAWARE'],
      );
    });

    test('two-wheeler with traffic-aware routing sends both', () async {
      final s = serve(
        fixture('compute_routes.json'),
        travelMode: GoogleTravelMode.twoWheeler,
      );
      await s.provider.route(a, b);
      final body = bodyOf(s.requests.single);
      expect(body['travelMode'], 'TWO_WHEELER');
      expect(body['routingPreference'], 'TRAFFIC_AWARE');
    });

    test('a coordinate that is not finite throws before any request', () async {
      final s = serve(fixture('compute_routes.json'));
      await expectLater(
        s.provider.route(const GeoPoint(double.nan, 106), b),
        throwsArgumentError,
      );
      await expectLater(
        s.provider.routes(a, const GeoPoint(10, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('a null apiKey sends none, for a proxy that adds it', () async {
      final s = serve(fixture('compute_routes.json'), apiKey: null);
      await s.provider.route(a, b);
      expect(s.requests.single.headers.containsKey('X-Goog-Api-Key'), isFalse);
      expect(s.requests.single.headers['X-Goog-FieldMask'], mask);
    });

    test('routesBaseUrl keeps its path and query parameters', () async {
      final s = serve(
        fixture('compute_routes.json'),
        apiKey: null,
        routesBaseUrl: Uri.parse('https://proxy.example.com/google/?tenant=a'),
      );
      await s.provider.route(a, b);
      expect(
        s.requests.single.url.toString(),
        'https://proxy.example.com/google/directions/v2:computeRoutes'
        '?tenant=a',
      );
    });

    test('extra headers are sent, and may replace the defaults', () async {
      final s = serve(
        fixture('compute_routes.json'),
        headers: {'X-Proxy-Token': 'p', 'X-Goog-FieldMask': 'routes.duration'},
      );
      await s.provider.route(a, b);
      final headers = s.requests.single.headers;
      expect(headers['X-Proxy-Token'], 'p');
      expect(headers['X-Goog-FieldMask'], 'routes.duration');
      expect(s.provider.headers, {
        'X-Proxy-Token': 'p',
        'X-Goog-FieldMask': 'routes.duration',
      });
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('compute_routes.json'), userAgent: null);
      await s.provider.route(a, b);
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final p = GoogleRoutesRouteProvider(apiKey: key);
      expect(p.routesBaseUrl, Uri.parse('https://routes.googleapis.com'));
      expect(GoogleRoutesRouteProvider.defaultRoutesBaseUrl, p.routesBaseUrl);
      expect(p.travelMode, GoogleTravelMode.drive);
      expect(p.routingPreference, GoogleRoutingPreference.trafficAware);
      expect(p.languageCode, isNull);
      expect(p.alternatives, isTrue);
      expect(p.headers, isEmpty);
      expect(p.timeout, const Duration(seconds: 12));
      expect(p.userAgent, 'navigation_google_maps/0.1.0');
      p.close();
    });
  });

  group('alternatives', () {
    test('routes() returns every route in Google\'s order', () async {
      final s = serve(fixture('compute_routes.json'));
      final routes = await s.provider.routes(a, b);
      expect(
        [for (final r in routes) r.name],
        ['Google 990 m', 'Google 1240 m'],
      );
    });

    test('Google\'s order is kept, whatever the labels', () async {
      final json = fixtureJson('compute_routes.json');
      routesOf(json)[0]['routeLabels'] = ['DEFAULT_ROUTE_ALTERNATE'];
      routesOf(json)[1]['routeLabels'] = ['DEFAULT_ROUTE'];
      final routes = await serve(jsonEncode(json)).provider.routes(a, b);
      expect(
        [for (final r in routes) r.name],
        ['Google 990 m', 'Google 1240 m'],
      );
    });

    test('route() and routes() keep at most maxAlternatives + 1', () async {
      final s = serve(fixture('compute_routes.json'));
      expect((await s.provider.route(a, b)).name, 'Google 990 m');
      expect(await s.provider.routes(a, b, maxAlternatives: 0), hasLength(1));
      expect(await s.provider.routes(a, b, maxAlternatives: 1), hasLength(2));
      expect(
        [for (final r in s.requests) bodyOf(r)['computeAlternativeRoutes']],
        [false, false, true],
      );
    });

    test('alternatives: false never asks for them', () async {
      final s = serve(fixture('compute_routes.json'), alternatives: false);
      expect(await s.provider.routes(a, b), hasLength(1));
      expect(bodyOf(s.requests.single)['computeAlternativeRoutes'], isFalse);
    });

    test('a negative maxAlternatives throws before any request', () async {
      final s = serve(fixture('compute_routes.json'));
      await expectLater(
        s.provider.routes(a, b, maxAlternatives: -1),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('routes', () {
    test(
      'the step polylines are stitched, each shared joint kept once',
      () async {
        final routes = await serve(fixture('compute_routes.json')).provider
            .routes(a, b);
        expect(routes[0].points, const [
          GeoPoint(10.77243, 106.69805),
          GeoPoint(10.7731, 106.6987),
          GeoPoint(10.774, 106.6995),
          GeoPoint(10.7752, 106.6986),
          GeoPoint(10.777, 106.6972),
          GeoPoint(10.77978, 106.69902),
        ]);
        // The NAME_CHANGE step of one point adds none.
        expect(routes[1].points, const [
          GeoPoint(10.77243, 106.69805),
          GeoPoint(10.7715, 106.6995),
          GeoPoint(10.7756, 106.7018),
          GeoPoint(10.77978, 106.69902),
        ]);
      },
    );

    test('manoeuvres and road names; the arrival is the last point', () async {
      final routes = await serve(fixture('compute_routes.json')).provider
          .routes(a, b);
      expect(view(routes[0]), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.turn, ManeuverModifier.left, 'Pasteur'),
        (ManeuverType.turn, ManeuverModifier.right, 'Công xã Paris'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(vertices(routes[0]), [0, 2, 4, 5]);
      // A first step without a manoeuvre departs.
      expect(view(routes[1]), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.roundabout, ManeuverModifier.right, 'Đồng Khởi'),
        (ManeuverType.newName, ManeuverModifier.none, 'Đồng Khởi'),
        (ManeuverType.continueOn, ManeuverModifier.straight, 'Đồng Khởi'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(vertices(routes[1]), [0, 1, 2, 2, 3]);
      expect(routes[0].summary, 'Pasteur');
    });

    test('durations: each step\'s staticDuration spread over its segments by '
        'length, scaled to the route\'s duration', () async {
      final routes = await serve(fixture('compute_routes.json')).provider
          .routes(a, b);
      final r = routes[0];
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(210, 1e-9));
      const scale = 210 / 175.5;
      expect(r.durationAt(r.distanceAtVertex(2)), closeTo(40 * scale, 1e-9));
      expect(
        r.durationAt(r.distanceAtVertex(4)),
        closeTo((40 + 75.5) * scale, 1e-9),
      );
      // By length within a step.
      final seconds = segmentSeconds(r);
      final l0 = r.distanceAtVertex(1);
      final l1 = r.distanceAtVertex(2) - l0;
      // (The provider measures great-circle lengths, NavRoute planar ones.)
      expect(seconds[0] / seconds[1], closeTo(l0 / l1, 1e-5));
      // The alternative: the step with no staticDuration counts 0.
      final alt = routes[1];
      expect(alt.duration, closeTo(200, 1e-9));
      expect(segmentSeconds(alt), [
        closeTo(50 * 200 / 185, 1e-9),
        closeTo(90 * 200 / 185, 1e-9),
        closeTo(45 * 200 / 185, 1e-9),
      ]);
    });

    test('without a route duration, its staticDuration (here the steps\' sum) '
        'is the target', () async {
      final json = fixtureJson('compute_routes.json');
      routesOf(json)[0].remove('duration');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.duration, closeTo(175.5, 1e-9));
    });

    test('steps without durations: the route duration is spread by '
        'length', () async {
      final json = fixtureJson('compute_routes.json');
      for (final step in stepsOf(routesOf(json)[0])) {
        step.remove('staticDuration');
      }
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(210, 1e-9));
      expect(
        r.durationAt(r.distanceAtVertex(2)),
        closeTo(210 * r.distanceAtVertex(2) / r.length, 1e-3),
      );
    });

    test('no duration anywhere: the times are estimated', () async {
      final json = fixtureJson('compute_routes.json');
      final route = routesOf(json)[0]
        ..remove('duration')
        ..remove('staticDuration');
      for (final step in stepsOf(route)) {
        step.remove('staticDuration');
      }
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.hasProviderDurations, isFalse);
    });

    test('without any step polyline, the route polyline, with a departure '
        'and an arrival', () async {
      final json = fixtureJson('compute_routes.json');
      for (final step in stepsOf(routesOf(json)[0])) {
        step.remove('polyline');
      }
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, hasLength(6));
      expect(r.points.last, const GeoPoint(10.77978, 106.69902));
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(r.duration, closeTo(210, 1e-9));
    });

    test('without legs, the route polyline', () async {
      final json = fixtureJson('compute_routes.json');
      routesOf(json)[0].remove('legs');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, hasLength(6));
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, ''),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
    });

    test('a step that is not the first may lack a manoeuvre: it keeps '
        'going', () async {
      final json = fixtureJson('compute_routes.json');
      (stepsOf(routesOf(json)[0])[1]['navigationInstruction']!
              as Map<String, Object?>)
          .remove('maneuver');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].type, ManeuverType.continueOn);
      expect(r.steps[1].modifier, ManeuverModifier.none);
      expect(r.steps[1].roadName, 'Pasteur');
    });

    test('an unknown manoeuvre is a turn without a direction', () async {
      final json = fixtureJson('compute_routes.json');
      (stepsOf(routesOf(json)[0])[1]['navigationInstruction']!
              as Map<String, Object?>)['maneuver'] =
          'TURN_SIDEWAYS';
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.steps[1].type, ManeuverType.turn);
      expect(r.steps[1].modifier, ManeuverModifier.none);
    });

    test('a DESTINATION step is the arrival, not a step of its own', () async {
      final json = fixtureJson('compute_routes.json');
      // A step of one point, at the destination.
      stepsOf(routesOf(json)[0]).add({
        'polyline': {'encodedPolyline': 'slx`A{sfjS'},
        'navigationInstruction': {'maneuver': 'DESTINATION'},
      });
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, hasLength(6));
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.turn, ManeuverModifier.left, 'Pasteur'),
        (ManeuverType.turn, ManeuverModifier.right, 'Công xã Paris'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(r.steps.last.distance, r.length);
    });

    test('a last step of no length (one point, at the destination) gives '
        'way to the arrival', () async {
      final json = fixtureJson('compute_routes.json');
      stepsOf(routesOf(json)[0]).add({
        'polyline': {'encodedPolyline': 'slx`A{sfjS'},
        'navigationInstruction': {
          'maneuver': 'STRAIGHT',
          'instructions': 'Continue onto Công xã Paris',
        },
      });
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.points, hasLength(6));
      expect(view(r), <StepView>[
        (ManeuverType.depart, ManeuverModifier.none, 'Lê Lợi'),
        (ManeuverType.turn, ManeuverModifier.left, 'Pasteur'),
        (ManeuverType.turn, ManeuverModifier.right, 'Công xã Paris'),
        (ManeuverType.arrive, ManeuverModifier.none, ''),
      ]);
      expect(vertices(r), [0, 2, 4, 5]);
    });

    test('no lanes and no speed limits: Routes v2 gives neither', () async {
      final r = await serve(fixture('compute_routes.json')).provider
          .route(a, b);
      expect(r.steps.every((s) => s.lanes.isEmpty), isTrue);
      expect(r.speedLimitAt(10), isNull);
    });

    test('a route without distanceMeters is named by its length', () async {
      final json = fixtureJson('compute_routes.json');
      routesOf(json)[0].remove('distanceMeters');
      final r = await serve(jsonEncode(json)).provider.route(a, b);
      expect(r.name, 'Google ${r.length.round()} m');
    });
  });

  group('durations', () {
    test('"123s" and "12.5s" (up to nine decimals) are read; anything else '
        'is a format error', () async {
      Future<NavRoute> withDuration(Object? value) {
        final json = fixtureJson('compute_routes.json');
        stepsOf(routesOf(json)[0])[0]['staticDuration'] = value;
        routesOf(json)[0]
          ..remove('duration')
          ..remove('staticDuration');
        return serve(jsonEncode(json)).provider.route(a, b);
      }

      expect(
        (await withDuration('123s')).duration,
        closeTo(123 + 75.5 + 60, 1e-9),
      );
      expect(
        (await withDuration('12.5s')).duration,
        closeTo(12.5 + 75.5 + 60, 1e-9),
      );
      expect(
        (await withDuration('0.000000001s')).duration,
        closeTo(75.5 + 60, 1e-6),
      );
      expect((await withDuration('0s')).duration, closeTo(135.5, 1e-9));
      for (final bad in <Object>[
        '123',
        '12.5',
        '-3s',
        '1e3s',
        '12.s',
        '.5s',
        ' 12s',
        '12s ',
        '12.0000000001s',
        '12 s',
        'NaNs',
        '12m',
        '',
        12,
        <Object?>[],
      ]) {
        final e = await _thrown<GoogleRoutesFormatException>(withDuration(bad));
        expect(
          e.message,
          startsWith('routes[0].legs[0].steps[0].staticDuration: '),
          reason: '$bad',
        );
        expect(e.statusCode, isNull);
      }
    });
  });

  group('errors', () {
    test('an empty answer is a GoogleRoutesNoRouteException', () async {
      for (final body in [fixture('no_route.json'), '{"routes": []}']) {
        final e = await _thrown<GoogleRoutesNoRouteException>(
          serve(body).provider.route(a, b),
        );
        expect(e, isA<GoogleRoutesException>());
        expect(e.statusCode, 200);
        expect(
          e.toString(),
          'GoogleRoutesNoRouteException: Google found no route between the '
          'points',
        );
      }
    });

    test('a Google RPC error is a GoogleRoutesStatusException with the HTTP '
        'status, the RPC status and the message', () async {
      final cases = [
        (
          fixture('error_invalid_argument.json'),
          400,
          'INVALID_ARGUMENT',
          'Google INVALID_ARGUMENT: the server rejected the request (Invalid '
              'JSON payload received. Unknown name "travelMod": Cannot find '
              'field.) [HTTP 400]',
        ),
        (
          fixture('error_resource_exhausted.json'),
          429,
          'RESOURCE_EXHAUSTED',
          "Google RESOURCE_EXHAUSTED: quota or rate limit reached (Quota "
              "exceeded for quota metric 'Compute routes requests' and limit "
              "'Compute routes requests per minute' of service "
              "'routes.googleapis.com'.) [HTTP 429]",
        ),
        (
          jsonEncode({
            'error': {
              'code': 404,
              'message': 'Not found',
              'status': 'NOT_FOUND',
            },
          }),
          404,
          'NOT_FOUND',
          'Google NOT_FOUND: not found (Not found) [HTTP 404]',
        ),
        (
          jsonEncode({
            'error': {
              'code': 503,
              'message': 'The service is currently unavailable.',
              'status': 'UNAVAILABLE',
            },
          }),
          503,
          'UNAVAILABLE',
          'Google UNAVAILABLE: a server error; retrying may succeed (The '
              'service is currently unavailable.) [HTTP 503]',
        ),
        (
          jsonEncode({
            'error': {'code': 500, 'message': '', 'status': 'INTERNAL'},
          }),
          500,
          'INTERNAL',
          'Google INTERNAL: a server error; retrying may succeed [HTTP 500]',
        ),
        (
          jsonEncode({
            'error': {'code': 409, 'message': 'x', 'status': 'ABORTED'},
          }),
          409,
          'ABORTED',
          'Google ABORTED: the server reported an error (x) [HTTP 409]',
        ),
      ];
      for (final (body, status, rpc, message) in cases) {
        final e = await _thrown<GoogleRoutesStatusException>(
          serve(body, status: status).provider.route(a, b),
        );
        expect(e, isA<GoogleRoutesException>());
        expect(e.statusCode, status);
        expect(e.status, rpc);
        expect(e.message, message);
        expect(e.toString(), 'GoogleRoutesStatusException: $message');
      }
    });

    test('a 401 or 403 is a GoogleRoutesHttpException, with the RPC status '
        'and message when the body has them', () async {
      final e = await _thrown<GoogleRoutesHttpException>(
        serve(
          fixture('error_permission_denied.json'),
          status: 403,
        ).provider.route(a, b),
      );
      expect(e, isA<GoogleRoutesException>());
      expect(e.statusCode, 403);
      expect(e.status, 'PERMISSION_DENIED');
      expect(
        e.message,
        'Google request failed with HTTP 403 (the key is missing or not '
        "allowed: check that the API is enabled for the key's project, the "
        "key's API and application restrictions, and billing): "
        'PERMISSION_DENIED: Requests '
        'to this API routes.googleapis.com method '
        'google.maps.routing.v2.Routes.ComputeRoutes are blocked.',
      );
      final unauthorized = await _thrown<GoogleRoutesHttpException>(
        serve(
          jsonEncode({
            'error': {
              'code': 401,
              'message': 'Request is missing required authentication.',
              'status': 'UNAUTHENTICATED',
            },
          }),
          status: 401,
          reasonPhrase: 'Unauthorized',
        ).provider.route(a, b),
      );
      expect(unauthorized.statusCode, 401);
      expect(unauthorized.status, 'UNAUTHENTICATED');
      expect(
        unauthorized.message,
        'Google request failed with HTTP 401 Unauthorized (the request is '
        'not authenticated): UNAUTHENTICATED: Request is missing required '
        'authentication.',
      );
    });

    test('an HTTP error without a Google error body is a '
        'GoogleRoutesHttpException, with a hint', () async {
      const hints = {
        400: '(the request is not valid)',
        401: '(the request is not authenticated)',
        403: '(the key is missing or not allowed: check',
        404: '(not found)',
        429: '(quota or rate limit reached)',
        502: 'Google request failed with HTTP 502: ',
      };
      for (final MapEntry(key: status, value: hint) in hints.entries) {
        final e = await _thrown<GoogleRoutesHttpException>(
          serve(
            '<html>Bad Gateway</html>',
            status: status,
          ).provider.route(a, b),
        );
        expect(e.statusCode, status);
        expect(e.status, isNull);
        expect(
          e.message,
          startsWith('Google request failed with HTTP $status'),
        );
        expect(e.message, contains(hint), reason: '$status');
        expect(e.message, endsWith(': <html>Bad Gateway</html>'));
      }
    });

    test('a long body is cut, and not inside a character', () async {
      final e = await _thrown<GoogleRoutesHttpException>(
        serve('${'x' * 199}😀😀', status: 500).provider.route(a, b),
      );
      expect(e.message, endsWith(': ${'x' * 199}😀…'));
    });

    test('an answer that is not what Google sends throws '
        'GoogleRoutesFormatException naming the field', () async {
      Future<GoogleRoutesFormatException> thrown(
        void Function(Map<String, Object?> json) edit,
      ) async {
        final json = fixtureJson('compute_routes.json');
        edit(json);
        return _thrown<GoogleRoutesFormatException>(
          serve(jsonEncode(json)).provider.routes(a, b),
        );
      }

      final cases = <String, void Function(Map<String, Object?>)>{
        'routes: expected an array, got an object': (j) => j['routes'] = {},
        'routes[1]: expected an object, got a number': (j) =>
            (j['routes']! as List<Object?>)[1] = 3,
        'routes[0].legs: expected an array, got a string': (j) =>
            routesOf(j)[0]['legs'] = 'x',
        'routes[0].legs[0].steps[1].polyline.encodedPolyline: expected a '
            'string, got a number': (j) =>
            stepsOf(routesOf(j)[0])[1]['polyline'] = {'encodedPolyline': 3},
        'routes[0].legs[0].steps[1].polyline.encodedPolyline: the polyline '
            'ends inside a value': (j) =>
            stepsOf(routesOf(j)[0])[1]['polyline'] = {
              'encodedPolyline': 'ohw`A',
            },
        'routes[0].legs[0].steps[1].navigationInstruction.maneuver: '
            'expected a string, got a number': (j) =>
            stepsOf(routesOf(j)[0])[1]['navigationInstruction'] = {
              'maneuver': 1,
            },
        'routes[0].legs[0].steps[1].distanceMeters: expected a number, got '
            'a string': (j) =>
            stepsOf(routesOf(j)[0])[1]['distanceMeters'] = '400',
        'routes[0].legs[0].steps[1].distanceMeters: negative (-1.0)': (j) =>
            stepsOf(routesOf(j)[0])[1]['distanceMeters'] = -1,
        'routes[0].duration: expected a duration such as "12.5s", got '
            '"1h"': (j) =>
            routesOf(j)[0]['duration'] = '1h',
        'routes[0].polyline: no step polyline and no route polyline': (j) {
          routesOf(j)[0].remove('polyline');
          for (final s in stepsOf(routesOf(j)[0])) {
            s.remove('polyline');
          }
        },
        'routes[0]: 1 point(s), a route needs at least 2': (j) {
          routesOf(j)[0].remove('legs');
          routesOf(j)[0]['polyline'] = {'encodedPolyline': 'u~v`AymfjS'};
        },
      };
      for (final MapEntry(key: message, value: edit) in cases.entries) {
        final e = await thrown(edit);
        expect(e.message, message);
        expect(e.toString(), 'GoogleRoutesFormatException: $message');
      }
      final cases2 = {
        'not json': 'the answer is not a JSON object: invalid JSON',
        '[1]': 'the answer is not a JSON object: got an array',
      };
      for (final MapEntry(key: body, value: message) in cases2.entries) {
        final e = await _thrown<GoogleRoutesFormatException>(
          serve(body).provider.route(a, b),
        );
        expect(e.message, startsWith(message), reason: body);
      }
      final e = await _thrown<GoogleRoutesFormatException>(
        GoogleRoutesRouteProvider(
          apiKey: key,
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
  });

  group('timeout', () {
    test('a server that never answers times out and the request is '
        'aborted', () async {
      final requests = <http.BaseRequest>[];
      final p = GoogleRoutesRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((req, _) {
          requests.add(req);
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final e = await _thrown<GoogleRoutesTimeoutException>(p.routes(a, b));
      expect(e, isA<GoogleRoutesException>());
      expect(e, isA<TimeoutException>());
      expect(e.timeout, const Duration(milliseconds: 50));
      expect(e.duration, const Duration(milliseconds: 50));
      expect(e.message, 'Google request timed out after 50 ms');
      final trigger = (requests.single as http.Abortable).abortTrigger;
      expect(trigger, isNotNull);
      await trigger!.timeout(const Duration(seconds: 1));
    });

    test('a TimeoutException from the client is not reported as the '
        "provider's own timeout", () async {
      final p = GoogleRoutesRouteProvider(
        apiKey: key,
        client: MockClient((_) async => throw TimeoutException('inner')),
      );
      await expectLater(
        p.route(a, b),
        throwsA(
          isA<TimeoutException>()
              .having(
                (e) => e,
                'type',
                isNot(isA<GoogleRoutesTimeoutException>()),
              )
              .having((e) => e.message, 'message', 'inner'),
        ),
      );
    });

    test('a body that stalls times out too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final p = GoogleRoutesRouteProvider(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming((_, _) async {
          body.add(utf8.encode('{"routes":'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      await _thrown<GoogleRoutesTimeoutException>(p.route(a, b));
    });
  });

  group('close', () {
    MockClient answering() => MockClient(
      (_) async =>
          http.Response.bytes(utf8.encode(fixture('compute_routes.json')), 200),
    );

    test('close() leaves an injected client open', () async {
      final client = RecordingClient(answering());
      final p = GoogleRoutesRouteProvider(apiKey: key, client: client);
      await p.route(a, b);
      p.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the provider created', () async {
      final created = RecordingClient(answering());
      final p = http.runWithClient(
        () => GoogleRoutesRouteProvider(apiKey: key),
        () => created,
      );
      await p.route(a, b);
      expect(created.closed, isFalse);
      p.close();
      expect(created.closed, isTrue);
      p.close();
    });

    test('a closed provider throws StateError', () async {
      final s = serve(fixture('compute_routes.json'));
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
