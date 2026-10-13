import 'dart:convert';
import 'dart:io';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_osrm/navigation_osrm.dart';
import 'package:test/test.dart';

// The fixtures of osrm_route_provider_test.dart (see its header), parsed
// without a provider or a request.

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

/// The first leg of the first route of [json], to edit in place.
Map<String, Object?> legOf(Map<String, Object?> json) {
  final route = (json['routes']! as List<Object?>).first! as Map;
  return (route['legs']! as List<Object?>).first! as Map<String, Object?>;
}

typedef StepView = (ManeuverType, ManeuverModifier, String);

List<StepView> view(NavRoute r) => [
  for (final s in r.steps) (s.type, s.modifier, s.roadName),
];

Matcher formatError(String message) => throwsA(
  isA<OsrmFormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('parse', () {
    test('steps, manoeuvres, road names, summary and name', () {
      final routes = OsrmResponseParser.parse(fixtureJson('route_steps.json'));
      expect(routes, hasLength(1));
      final r = routes.single;
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
      expect(r.points, hasLength(15));
      expect(r.points.first, const GeoPoint(10.8, 106.7));
      expect(r.points.last, const GeoPoint(10.8112, 106.7118));
      expect(r.summary, 'Cao tốc Long Thành, Phạm Văn Đồng');
      expect(r.name, 'OSRM 2192 m');
    });

    test('lanes come from the manoeuvre\'s intersection', () {
      final r = OsrmResponseParser.parse(
        fixtureJson('route_steps.json'),
      ).single;
      expect(r.steps[0].lanes, isEmpty);
      expect(r.steps[1].lanes, const [
        Lane(directions: {LaneDirection.straight}),
        Lane(
          directions: {LaneDirection.straight, LaneDirection.slightRight},
          valid: true,
          active: LaneDirection.slightRight,
        ),
      ]);
      // `none`: no arrow, read as straight.
      expect(r.steps[6].lanes, const [
        Lane(directions: {LaneDirection.straight}),
        Lane(
          directions: {LaneDirection.straight},
          valid: true,
          active: LaneDirection.straight,
        ),
      ]);
    });

    test('durations: the annotations, scaled to the leg', () {
      final r = OsrmResponseParser.parse(
        fixtureJson('route_steps.json'),
      ).single;
      expect(r.hasProviderDurations, isTrue);
      expect(r.duration, closeTo(173.6, 1e-9));

      final json = fixtureJson('route_steps.json');
      legOf(json).remove('annotation');
      final none = OsrmResponseParser.parse(json).single;
      expect(none.hasProviderDurations, isFalse);
    });

    test('speed limits from maxspeed only when asked for', () {
      const kmh = 1 / 3.6;
      const mph = 0.44704;
      double? limitAfter(NavRoute r, int k) =>
          r.speedLimitAt(r.steps[k].distance + 1);

      final json = fixtureJson('route_speed_limits.json');
      final r = OsrmResponseParser.parse(json, speedLimits: true).single;
      expect(limitAfter(r, 0), closeTo(40 * kmh, 1e-9));
      expect(limitAfter(r, 3), closeTo(65 * mph, 1e-9));
      expect(limitAfter(r, 6), isNull); // {unknown: true}
      expect(limitAfter(r, 7), isNull); // {none: true}

      final off = OsrmResponseParser.parse(json).single;
      for (var k = 0; k < off.steps.length; k++) {
        expect(limitAfter(off, k), isNull, reason: '$k');
      }
    });

    test('a polyline6 geometry decodes to the same route as geojson', () {
      final geo = OsrmResponseParser.parse(
        fixtureJson('route_steps.json'),
      ).single;
      final poly = OsrmResponseParser.parse(
        fixtureJson('route_steps_polyline6.json'),
        geometries: OsrmGeometries.polyline6,
      ).single;
      expect(poly.points, hasLength(geo.points.length));
      for (var i = 0; i < geo.points.length; i++) {
        expect(poly.points[i].lat, closeTo(geo.points[i].lat, 1e-9));
        expect(poly.points[i].lng, closeTo(geo.points[i].lng, 1e-9));
      }
      expect(view(poly), view(geo));
    });

    test('every route by default; maxAlternatives keeps the first N + 1', () {
      final json = fixtureJson('route_alternatives.json');
      final all = OsrmResponseParser.parse(json);
      expect(all, hasLength(2));
      expect(all[0].summary, 'Lý Tự Trọng, Nguyễn Hữu Cảnh');
      expect(all[1].summary, 'Nguyễn Thị Minh Khai, Điện Biên Phủ');
      expect(OsrmResponseParser.parse(json, maxAlternatives: 1), hasLength(2));
      final best = OsrmResponseParser.parse(json, maxAlternatives: 0);
      expect(best, hasLength(1));
      expect(best.single.summary, 'Lý Tự Trọng, Nguyễn Hữu Cảnh');
      expect(
        () => OsrmResponseParser.parse(json, maxAlternatives: -1),
        throwsArgumentError,
      );
    });

    test('providerName starts each route name', () {
      final r = OsrmResponseParser.parse(
        fixtureJson('route_steps.json'),
        providerName: 'Mapbox',
      ).single;
      expect(r.name, 'Mapbox 2192 m');
    });

    test('fields it does not know, such as Mapbox\'s instructions, are '
        'ignored', () {
      final json = fixtureJson('route_steps.json');
      final steps = legOf(json)['steps']! as List<Object?>;
      (steps[1]! as Map<String, Object?>)
        ..['voiceInstructions'] = [
          {'announcement': 'Keep right'},
        ]
        ..['bannerInstructions'] = [
          {
            'primary': {'text': 'CT01'},
          },
        ];
      final r = OsrmResponseParser.parse(json).single;
      expect(r.steps[1].roadName, 'CT01');
    });
  });

  group('errors', () {
    test('no routes', () {
      expect(
        () => OsrmResponseParser.parse({'code': 'Ok', 'routes': <Object?>[]}),
        formatError('routes: an Ok answer with no routes'),
      );
      expect(
        () => OsrmResponseParser.parse({'code': 'Ok'}),
        formatError('routes: expected an array, got null'),
      );
    });

    test('a malformed field is named', () {
      final json = fixtureJson('route_steps.json');
      final steps = legOf(json)['steps']! as List<Object?>;
      (steps[2]! as Map<String, Object?>)['maneuver'] = 'merge';
      expect(
        () => OsrmResponseParser.parse(json),
        formatError(
          'routes[0].legs[0].steps[2].maneuver: expected an object, got a '
          'string',
        ),
      );
    });

    test('a geometry of the other kind', () {
      expect(
        () => OsrmResponseParser.parse(
          fixtureJson('route_steps.json'),
          geometries: OsrmGeometries.polyline6,
        ),
        formatError('routes[0].geometry: expected a polyline6 string'),
      );
      expect(
        () =>
            OsrmResponseParser.parse(fixtureJson('route_steps_polyline6.json')),
        formatError('routes[0].geometry: expected an object, got a string'),
      );
    });

    test('a polyline6 geometry cut short', () {
      final json = fixtureJson('route_steps_polyline6.json');
      final route = (json['routes']! as List<Object?>).first! as Map;
      route['geometry'] = '_wdrS';
      expect(
        () => OsrmResponseParser.parse(
          json,
          geometries: OsrmGeometries.polyline6,
        ),
        formatError('routes[0].geometry: the polyline ends inside a value'),
      );
    });
  });
}
