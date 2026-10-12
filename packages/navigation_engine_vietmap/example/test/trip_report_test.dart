import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_vietmap/navigation_engine_vietmap.dart';
import 'package:navigation_engine_vietmap_example/trip_report.dart';
import 'package:test/test.dart';

void main() {
  test('searches, resolves and describes the route a server sends', () async {
    final bodies = {
      '/api/autocomplete/v4': [
        {
          'ref_id': 'auto:ref',
          'name': 'Landmark 81',
          'display': 'Landmark 81, Bình Thạnh',
        },
      ],
      '/api/place/v4': {
        'name': 'Landmark 81',
        'display': 'Landmark 81, Bình Thạnh',
        'lat': 10.809,
        'lng': 106.7,
      },
      '/api/route/v4': {
        'code': 'OK',
        'paths': [
          {
            'distance': 1000,
            'time': 120000,
            // (10.8, 106.7) -> (10.809, 106.7)
            'points': '_k|`A_zfjSgw@?',
            'instructions': [
              {
                'sign': 0,
                'interval': [0, 1],
                'time': 120000,
                'street_name': 'Main Street',
              },
              {
                'sign': 4,
                'interval': [1, 1],
                'time': 0,
                'street_name': '',
              },
            ],
          },
        ],
      },
    };
    final client = MockClient(
      (req) async => http.Response.bytes(
        utf8.encode(jsonEncode(bodies[req.url.path])),
        200,
      ),
    );
    final lines = await tripReport(
      VietmapPlaceSearch(apiKey: 'test-key', client: client),
      VietmapRouteProvider(apiKey: 'test-key', client: client),
      const GeoPoint(10.8, 106.7),
      'landmark',
    );
    expect(lines.first, 'To Landmark 81 (Landmark 81, Bình Thạnh)');
    expect(lines[1], 'Best: 1.0 km, 2 min, via Main Street');
    expect(lines[2], contains('depart none onto Main Street'));
    expect(lines[3], contains('arrive none'));
  });
}
