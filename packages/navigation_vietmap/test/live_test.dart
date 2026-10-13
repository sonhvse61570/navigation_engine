// A live smoke check against Vietmap's real APIs. Skipped unless a services
// key is in the environment; each run makes five requests billed to it:
//
//     VIETMAP_SERVICES_KEY=... dart test -t live
//
// It checks the assumptions the fixtures are built on: every `sign` code
// route v4 sends is one the package maps (the codes seen are printed), the
// road names, and place v4 for positions. Record any difference in the
// README.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:navigation_vietmap/src/signs.dart';
import 'package:test/test.dart';

final String? key = Platform.environment['VIETMAP_SERVICES_KEY'];

const benThanh = GeoPoint(10.771897, 106.698226);
const landmark81 = GeoPoint(10.795172, 106.721646);

String latLng(GeoPoint p) => '${p.lat},${p.lng}';

void main() {
  final skip = key == null || key!.isEmpty
      ? 'set VIETMAP_SERVICES_KEY to run the live check'
      : null;

  test('route v4: every sign code Vietmap sends is mapped', () async {
    // The raw answer, as the provider asks for it: the provider itself
    // would turn an unknown code into a turn without a direction.
    final uri = Uri.parse(
      'https://maps.vietmap.vn/api/route/v4'
      '?apikey=${Uri.encodeQueryComponent(key!)}'
      '&point=${latLng(benThanh)}&point=${latLng(landmark81)}'
      '&vehicle=car&alternative=true&heading=90&points_encoded=true',
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
    final signs = <num>{};
    for (final path in json['paths'] as List) {
      for (final instruction in (path as Map)['instructions'] as List) {
        signs.add((instruction as Map)['sign'] as num);
      }
    }
    // For the README: the codes Vietmap really sends.
    print('sign codes seen: $signs');
    expect(signs, isNotEmpty);
    final unknown = [
      for (final s in signs)
        if (s != s.roundToDouble() || vietmapSign(s.toInt()) == null) s,
    ];
    expect(unknown, isEmpty, reason: 'map these and record them in the README');
  }, skip: skip);

  test('route v4: routes with known manoeuvres and road names', () async {
    final router = VietmapRouteProvider(apiKey: key);
    addTearDown(router.close);
    final routes = await router.routes(benThanh, landmark81, heading: 90);
    expect(routes, isNotEmpty);
    for (final r in routes) {
      expect(r.length, greaterThan(1000));
      expect(r.hasProviderDurations, isTrue);
      // (turn, none) is the fallback for a code the package does not know.
      expect([
        for (final s in r.steps)
          if (s.type == ManeuverType.turn &&
              s.modifier == ManeuverModifier.none)
            s,
      ], isEmpty);
      print('road names: ${[for (final s in r.steps) s.roadName]}');
      expect(
        r.steps.where((s) => !s.isArrival && s.roadName.isNotEmpty),
        isNotEmpty,
      );
    }
  }, skip: skip);

  test('autocomplete, place and reverse v4', () async {
    final search = VietmapPlaceSearch(apiKey: key);
    addTearDown(search.close);
    final suggestions = await search.autocomplete(
      'Chợ Bến Thành',
      near: benThanh,
    );
    expect(suggestions, isNotEmpty);
    expect(suggestions.first.position, isNull);
    final place = await search.resolve(suggestions.first);
    expect(distanceBetween(place.position, benThanh), lessThan(5000));
    final here = await search.reverse(benThanh);
    expect(here, isNotNull);
    expect(here!.name, isNotEmpty);
  }, skip: skip);
}
