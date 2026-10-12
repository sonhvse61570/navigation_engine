import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';
import 'package:navigation_engine_google_routes_example/trip_report.dart';
import 'package:test/test.dart';

void main() {
  test('searches, resolves and describes the route a server sends', () async {
    final bodies = {
      'places:autocomplete': {
        'suggestions': [
          {
            'placePrediction': {
              'placeId': 'REDACTED-id',
              'text': {'text': 'Nhà thờ Đức Bà, Công xã Paris, Quận 1'},
              'structuredFormat': {
                'mainText': {'text': 'Nhà thờ Đức Bà'},
                'secondaryText': {'text': 'Công xã Paris, Quận 1'},
              },
            },
          },
        ],
      },
      'REDACTED-id': {
        'id': 'REDACTED-id',
        'displayName': {'text': 'Nhà thờ Đức Bà', 'languageCode': 'vi'},
        'formattedAddress': 'Công xã Paris, Bến Nghé, Quận 1',
        'location': {'latitude': 10.779, 'longitude': 106.699},
      },
      'v2:computeRoutes': {
        'routes': [
          {
            'distanceMeters': 1001,
            'duration': '120s',
            'staticDuration': '100s',
            'routeLabels': ['DEFAULT_ROUTE'],
            'legs': [
              {
                'steps': [
                  {
                    'distanceMeters': 1001,
                    'staticDuration': '100s',
                    // (10.77, 106.699) -> (10.779, 106.699), precision 5.
                    'polyline': {'encodedPolyline': 'oov`AwsfjSgw@?'},
                    'navigationInstruction': {
                      'maneuver': 'DEPART',
                      'instructions': 'Đi về hướng bắc trên Công xã Paris',
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
      return http.Response.bytes(
        utf8.encode(jsonEncode(bodies[req.url.pathSegments.last])),
        200,
      );
    });
    final lines = await tripReport(
      GooglePlacesSearch(apiKey: 'test-key', client: client),
      GoogleRoutesRouteProvider(apiKey: 'test-key', client: client),
      const GeoPoint(10.77, 106.699),
      'nha tho duc ba',
    );
    expect(lines, [
      'To Nhà thờ Đức Bà (Công xã Paris, Bến Nghé, Quận 1)',
      'Best: 1.0 km, 2 min, via Công xã Paris',
      '       0 m  depart none onto Công xã Paris',
      '     995 m  arrive none',
    ]);
    // One session: the same token on autocomplete and place details.
    final token =
        (jsonDecode(requests[0].body) as Map<String, Object?>)['sessionToken'];
    expect(token, hasLength(36));
    expect(requests[1].url.queryParameters['sessionToken'], token);
  });
}
