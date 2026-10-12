import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_goong/navigation_engine_goong.dart';
import 'package:navigation_engine_goong_example/trip_report.dart';
import 'package:test/test.dart';

void main() {
  test('searches, resolves and describes the route a server sends', () async {
    final bodies = {
      '/v2/place/autocomplete': {
        'predictions': [
          {
            'place_id': 'REDACTED-place',
            'description': 'Hồ Tây, Tây Hồ, Hà Nội',
            'structured_formatting': {
              'main_text': 'Hồ Tây',
              'secondary_text': 'Tây Hồ, Hà Nội',
            },
          },
        ],
        'status': 'OK',
      },
      '/v2/place/detail': {
        'result': {
          'place_id': 'REDACTED-place',
          'name': 'Hồ Tây',
          'formatted_address': 'Hồ Tây, Tây Hồ, Hà Nội',
          'geometry': {
            'location': {'lat': 21.059, 'lng': 105.8},
          },
        },
        'status': 'OK',
      },
      '/v2/direction': {
        'routes': [
          {
            'legs': [
              {
                'distance': {'text': '1 km', 'value': 1000},
                'duration': {'text': '2 phút', 'value': 120},
                'steps': [
                  {
                    'duration': {'text': '2 phút', 'value': 120},
                    'html_instructions': 'Bắt đầu đi từ Thanh Niên',
                    'maneuver': '',
                    // (21.05, 105.8) -> (21.059, 105.8)
                    'polyline': {'points': 'oin_C_awdSgw@?'},
                  },
                ],
              },
            ],
            'summary': 'Thanh Niên',
          },
        ],
      },
    };
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(jsonEncode(bodies[req.url.path])),
        200,
      );
    });
    final lines = await tripReport(
      GoongPlaceSearch(apiKey: 'test-key', client: client),
      GoongRouteProvider(apiKey: 'test-key', client: client),
      const GeoPoint(21.05, 105.8),
      'ho tay',
    );
    expect(lines, [
      'To Hồ Tây (Hồ Tây, Tây Hồ, Hà Nội)',
      'Best: 1.0 km, 2 min, via Thanh Niên',
      '       0 m  depart none onto Thanh Niên',
      '     995 m  arrive none',
    ]);
    // One session: the same token on autocomplete and place detail.
    final tokens = [
      for (final r in requests.take(2)) r.url.queryParameters['sessiontoken'],
    ];
    expect(tokens.first, hasLength(36));
    expect(tokens.last, tokens.first);
  });
}
