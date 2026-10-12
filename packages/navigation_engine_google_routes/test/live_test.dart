// A live smoke check against Google's real APIs. Skipped unless a key is in
// the environment; each run makes six requests billed to it (two Compute
// Routes requests, a Places autocomplete session of one autocomplete and
// one place details request, and one Geocoding request):
//
//     GOOGLE_ROUTES_KEY=... dart test -t live
//
// The key must allow the Routes API, the Places API (New) and the
// Geocoding API. It checks the assumptions the fixtures are built on:
// every `maneuver` Google sends is one the package maps (the values seen,
// and the instructions, are printed), durations read, and the place search
// answers read. Record any difference in the README.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';
import 'package:navigation_engine_google_routes/src/maneuvers.dart';
import 'package:test/test.dart';

final String? key = Platform.environment['GOOGLE_ROUTES_KEY'];

const benThanh = GeoPoint(10.772431, 106.698048); // Ben Thanh Market
const tanDinh = GeoPoint(10.788530, 106.690530); // Tan Dinh Church

Map<String, Object?> latLng(GeoPoint p) => {
  'location': {
    'latLng': {'latitude': p.lat, 'longitude': p.lng},
  },
};

void main() {
  final skip = key == null || key!.isEmpty
      ? 'set GOOGLE_ROUTES_KEY to run the live check'
      : null;

  test('Routes v2: every maneuver Google sends is mapped', () async {
    // The raw answer, as the provider asks for it: the provider itself
    // would turn an unknown value into a turn without a direction.
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': key!,
          'X-Goog-FieldMask': GoogleRoutesRouteProvider.fieldMask,
        },
        body: jsonEncode({
          'origin': latLng(benThanh),
          'destination': latLng(tanDinh),
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
          'computeAlternativeRoutes': true,
          'languageCode': 'vi',
          'polylineQuality': 'HIGH_QUALITY',
          'polylineEncoding': 'ENCODED_POLYLINE',
        }),
      );
    } on http.ClientException catch (e) {
      // Not rethrown as it is: test logs are shared.
      fail('the request failed: ${e.message.replaceAll(key!, 'REDACTED')}');
    }
    expect(response.statusCode, 200, reason: 'HTTP status');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final values = <String?>{};
    final instructions = <String>[];
    final labels = <Object?>[];
    for (final route in json['routes'] as List) {
      labels.add((route as Map)['routeLabels']);
      for (final leg in route['legs'] as List) {
        for (final step in (leg as Map)['steps'] as List) {
          final nav = (step as Map)['navigationInstruction'] as Map?;
          values.add(nav?['maneuver'] as String?);
          instructions.add('${nav?['instructions']}');
        }
      }
    }
    // For the README: the values Google really sends.
    print('maneuvers seen: $values');
    print('route labels seen: $labels');
    print('instructions seen: $instructions');
    expect(values, isNotEmpty);
    final unknown = [
      for (final v in values)
        if (v != null && googleManeuver(v) == null) v,
    ];
    expect(unknown, isEmpty, reason: 'map these and record them in the README');
  }, skip: skip);

  test('Routes v2: routes with steps, durations and road names', () async {
    final router = GoogleRoutesRouteProvider(apiKey: key, languageCode: 'vi');
    addTearDown(router.close);
    final routes = await router.routes(benThanh, tanDinh, heading: 0);
    expect(routes, isNotEmpty);
    for (final r in routes) {
      expect(r.length, greaterThan(1000));
      expect(r.hasProviderDurations, isTrue);
      expect(r.name, startsWith('Google '));
      print(
        '${r.name}, ${r.duration.round()} s; road names: '
        '${[for (final s in r.steps) s.roadName]}',
      );
      expect(
        r.steps.where((s) => !s.isArrival && s.roadName.isNotEmpty),
        isNotEmpty,
      );
    }
  }, skip: skip);

  test(
    'Places (New) and Geocoding: autocomplete, details and reverse',
    () async {
      final search = GooglePlacesSearch(
        apiKey: key,
        languageCode: 'vi',
        regionCodes: const ['vn'],
      );
      addTearDown(search.close);
      final session = PlaceSearchSession();
      final suggestions = await search.autocomplete(
        'Chợ Bến Thành',
        near: benThanh,
        session: session,
      );
      expect(suggestions, isNotEmpty);
      final place = await search.resolve(suggestions.first, session: session);
      expect(distanceBetween(place.position, benThanh), lessThan(5000));
      final here = await search.reverse(benThanh);
      expect(here, isNotNull);
      expect(here!.name, isNotEmpty);
      print('resolved: $place; reverse: $here');
    },
    skip: skip,
  );
}
