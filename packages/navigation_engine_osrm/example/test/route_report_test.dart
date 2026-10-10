import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_osrm/navigation_engine_osrm.dart';
import 'package:navigation_engine_osrm_example/route_report.dart';
import 'package:test/test.dart';

void main() {
  test('describes the route a server sends', () async {
    final step = {'name': 'Main Street', 'intersections': <Object?>[]};
    final body = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 1000,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [106.7, 10.8],
              [106.7, 10.809],
            ],
          },
          'legs': [
            {
              'summary': 'Main Street',
              'duration': 120,
              'annotation': {
                'duration': [120],
              },
              'steps': [
                {
                  ...step,
                  'maneuver': {
                    'type': 'depart',
                    'location': [106.7, 10.8],
                  },
                },
                {
                  ...step,
                  'maneuver': {
                    'type': 'arrive',
                    'location': [106.7, 10.809],
                  },
                },
              ],
            },
          ],
        },
      ],
    });
    final provider = OsrmRouteProvider(
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode(body), 200),
      ),
    );
    final lines = await routeReport(
      provider,
      const GeoPoint(10.8, 106.7),
      const GeoPoint(10.809, 106.7),
    );
    expect(lines.first, 'Best: 1.0 km, 2 min, via Main Street');
    expect(lines[1], contains('depart none onto Main Street'));
    expect(lines[2], contains('arrive none'));
  });
}
