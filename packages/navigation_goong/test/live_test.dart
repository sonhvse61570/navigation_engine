// A live smoke check against Goong's real APIs. Skipped unless a REST key
// is in the environment; each run makes five requests billed to it:
//
//     GOONG_API_KEY=... dart test -t live
//
// It checks the assumptions the fixtures are built on: every `maneuver`
// string Goong sends is one the package maps (the values seen are
// printed), the road names read from real instructions, and place detail
// for positions. Record any difference in the README.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_goong/navigation_goong.dart';
import 'package:navigation_goong/src/maneuvers.dart';
import 'package:test/test.dart';

final String? key = Platform.environment['GOONG_API_KEY'];

const hoanKiem = GeoPoint(21.028772, 105.852379);
const westLake = GeoPoint(21.054255, 105.825394);

String latLng(GeoPoint p) => '${p.lat},${p.lng}';

void main() {
  final skip = key == null || key!.isEmpty
      ? 'set GOONG_API_KEY to run the live check'
      : null;

  test('direction v2: every maneuver Goong sends is mapped', () async {
    // The raw answer, as the provider asks for it: the provider itself
    // would turn an unknown value into a turn without a direction.
    final uri = Uri.parse(
      'https://rsapi.goong.io/v2/direction'
      '?origin=${latLng(hoanKiem)}&destination=${latLng(westLake)}'
      '&vehicle=car&alternatives=true'
      '&api_key=${Uri.encodeQueryComponent(key!)}',
    );
    final http.Response response;
    try {
      response = await http.get(uri);
    } on http.ClientException catch (e) {
      // Not rethrown: its URL holds the key, and test logs are shared.
      fail('the request failed: ${e.message}');
    }
    expect(response.statusCode, 200, reason: 'HTTP status');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final values = <String?>{};
    for (final route in json['routes'] as List) {
      for (final leg in (route as Map)['legs'] as List) {
        for (final step in (leg as Map)['steps'] as List) {
          values.add((step as Map)['maneuver'] as String?);
        }
      }
    }
    // For the README: the values Goong really sends.
    print('maneuver values seen: $values');
    expect(values, isNotEmpty);
    final unknown = [
      for (final v in values)
        if (goongManeuver(v) == null) v,
    ];
    expect(unknown, isEmpty, reason: 'map these and record them in the README');
  }, skip: skip);

  test('direction v2: routes with known manoeuvres and road names', () async {
    final router = GoongRouteProvider(apiKey: key);
    addTearDown(router.close);
    final routes = await router.routes(hoanKiem, westLake);
    expect(routes, isNotEmpty);
    for (final r in routes) {
      expect(r.length, greaterThan(1000));
      expect(r.hasProviderDurations, isTrue);
      // (turn, none) is the fallback for a value the package does not know.
      expect([
        for (final s in r.steps)
          if (s.type == ManeuverType.turn &&
              s.modifier == ManeuverModifier.none)
            s,
      ], isEmpty);
      // The road names come from real instructions.
      print('road names: ${[for (final s in r.steps) s.roadName]}');
      expect(
        r.steps.where((s) => !s.isArrival && s.roadName.isNotEmpty),
        isNotEmpty,
      );
    }
  }, skip: skip);

  test('autocomplete, place detail and geocode v2', () async {
    final search = GoongPlaceSearch(apiKey: key);
    addTearDown(search.close);
    final session = PlaceSearchSession();
    final suggestions = await search.autocomplete(
      'Hồ Hoàn Kiếm',
      near: hoanKiem,
      session: session,
    );
    expect(suggestions, isNotEmpty);
    final place = await search.resolve(suggestions.first, session: session);
    expect(distanceBetween(place.position, hoanKiem), lessThan(5000));
    final here = await search.reverse(hoanKiem);
    expect(here, isNotNull);
    expect(here!.name, isNotEmpty);
  }, skip: skip);
}
