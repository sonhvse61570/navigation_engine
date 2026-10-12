import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_mapbox_directions/navigation_engine_mapbox_directions.dart';
import 'package:navigation_engine_mapbox_directions_example/trip_report.dart';
import 'package:test/test.dart';

void main() {
  test('searches, resolves and describes the route a server sends', () async {
    final bodies = {
      'suggest': {
        'suggestions': [
          {
            'name': 'Hồ Tây',
            'mapbox_id': 'REDACTED-id',
            'feature_type': 'poi',
            'place_formatted': 'Tây Hồ, Hà Nội, Việt Nam',
          },
        ],
      },
      'retrieve': {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [105.8, 21.059],
            },
            'properties': {
              'name': 'Hồ Tây',
              'mapbox_id': 'REDACTED-id',
              'full_address': 'Hồ Tây, Tây Hồ, Hà Nội, Việt Nam',
            },
          },
        ],
      },
      'directions': {
        'code': 'Ok',
        'routes': [
          {
            'distance': 1000.8,
            'duration': 120,
            // (21.05, 105.8) -> (21.059, 105.8), precision 6.
            'geometry': '_hxcg@_soxhEoqP?',
            'legs': [
              {
                'summary': 'Thanh Niên',
                'duration': 120,
                'annotation': {
                  'duration': [120],
                  'maxspeed': [
                    {'speed': 50, 'unit': 'km/h'},
                  ],
                },
                'steps': [
                  {
                    'name': 'Thanh Niên',
                    'maneuver': {
                      'type': 'depart',
                      'location': [105.8, 21.05],
                    },
                    'voiceInstructions': <Object?>[],
                    'bannerInstructions': <Object?>[],
                  },
                  {
                    'name': 'Thanh Niên',
                    'maneuver': {
                      'type': 'arrive',
                      'location': [105.8, 21.059],
                    },
                  },
                ],
              },
            ],
          },
        ],
      },
    };
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req);
      final segments = req.url.pathSegments;
      final endpoint = segments.first == 'directions'
          ? 'directions'
          : segments[3];
      return http.Response.bytes(
        utf8.encode(jsonEncode(bodies[endpoint])),
        200,
      );
    });
    final lines = await tripReport(
      MapboxSearch(accessToken: 'test-token', client: client),
      MapboxDirectionsRouteProvider(accessToken: 'test-token', client: client),
      const GeoPoint(21.05, 105.8),
      'ho tay',
    );
    expect(lines, [
      'To Hồ Tây (Hồ Tây, Tây Hồ, Hà Nội, Việt Nam)',
      'Best: 1.0 km, 2 min, via Thanh Niên',
      '       0 m  depart none onto Thanh Niên (limit 50 km/h)',
      '     995 m  arrive none onto Thanh Niên',
    ]);
    // One session: the same token on suggest and retrieve.
    final tokens = [
      for (final r in requests.take(2)) r.url.queryParameters['session_token'],
    ];
    expect(tokens.first, hasLength(36));
    expect(tokens.last, tokens.first);
  });
}
