// A live smoke check against Mapbox's real APIs. Skipped unless a token is
// in the environment; each run makes six requests billed to it (two
// Directions requests, one Search Box session and one reverse request):
//
//     MAPBOX_TOKEN=pk.... dart test -t live
//
// It checks the assumptions the fixtures are built on: every manoeuvre
// type and modifier Mapbox sends is one the OSRM parser maps (the values
// seen are printed), `maxspeed` arrives as documented, and the Search Box
// answers read. Record any difference in the README.
@TestOn('vm')
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_mapbox_directions/navigation_engine_mapbox_directions.dart';
import 'package:test/test.dart';

final String? token = Platform.environment['MAPBOX_TOKEN'];

const hoanKiem = GeoPoint(21.028772, 105.852379);
const westLake = GeoPoint(21.054255, 105.825394);

/// The `maneuver.type` values `OsrmResponseParser` maps (any other is read
/// as a turn, as OSRM asks).
const knownTypes = {
  'depart',
  'arrive',
  'turn',
  'new name',
  'continue',
  'notification',
  'use lane',
  'merge',
  'on ramp',
  'off ramp',
  'fork',
  'end of road',
  'roundabout',
  'rotary',
  'roundabout turn',
  'exit roundabout',
  'exit rotary',
};

/// The `maneuver.modifier` values it maps (null: none sent).
const knownModifiers = {
  null,
  'uturn',
  'sharp right',
  'right',
  'slight right',
  'straight',
  'slight left',
  'left',
  'sharp left',
};

String lonLat(GeoPoint p) => '${p.lng},${p.lat}';

void main() {
  final skip = token == null || token!.isEmpty
      ? 'set MAPBOX_TOKEN to run the live check'
      : null;

  test('Directions v5: every manoeuvre Mapbox sends is mapped', () async {
    // The raw answer, as the provider asks for it: the parser itself would
    // turn an unknown type into a turn.
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
      '${lonLat(hoanKiem)};${lonLat(westLake)}'
      '?alternatives=true&steps=true&geometries=polyline6&overview=full'
      '&annotations=duration,distance,maxspeed'
      '&access_token=${Uri.encodeQueryComponent(token!)}',
    );
    final http.Response response;
    try {
      response = await http.get(uri);
    } on http.ClientException catch (e) {
      // Not rethrown: its URL holds the token, and test logs are shared.
      fail('the request failed: ${e.message.replaceAll(token!, 'REDACTED')}');
    }
    expect(response.statusCode, 200, reason: 'HTTP status');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    expect(json['code'], 'Ok');
    final types = <String?>{};
    final modifiers = <String?>{};
    final maxspeeds = <String>{};
    for (final route in json['routes'] as List) {
      for (final leg in (route as Map)['legs'] as List) {
        for (final step in (leg as Map)['steps'] as List) {
          final maneuver = (step as Map)['maneuver'] as Map;
          types.add(maneuver['type'] as String?);
          modifiers.add(maneuver['modifier'] as String?);
        }
        final annotation = leg['annotation'] as Map?;
        for (final m in (annotation?['maxspeed'] as List?) ?? const []) {
          maxspeeds.add((m as Map).keys.join('+'));
        }
      }
    }
    // For the README: the values Mapbox really sends.
    print('maneuver types seen: $types');
    print('maneuver modifiers seen: $modifiers');
    print('maxspeed shapes seen: $maxspeeds');
    expect(types, isNotEmpty);
    final unknown = [
      for (final t in types)
        if (!knownTypes.contains(t)) 'type $t',
      for (final m in modifiers)
        if (!knownModifiers.contains(m)) 'modifier $m',
    ];
    expect(unknown, isEmpty, reason: 'map these and record them in the README');
  }, skip: skip);

  test('Directions v5: routes with steps, durations and road names', () async {
    final router = MapboxDirectionsRouteProvider(accessToken: token);
    addTearDown(router.close);
    final routes = await router.routes(hoanKiem, westLake, heading: 0);
    expect(routes, isNotEmpty);
    for (final r in routes) {
      expect(r.length, greaterThan(1000));
      expect(r.hasProviderDurations, isTrue);
      expect(r.name, startsWith('Mapbox '));
      print('road names: ${[for (final s in r.steps) s.roadName]}');
      expect(
        r.steps.where((s) => !s.isArrival && s.roadName.isNotEmpty),
        isNotEmpty,
      );
    }
  }, skip: skip);

  test('Search Box: suggest, retrieve and reverse', () async {
    final search = MapboxSearch(accessToken: token, language: 'vi');
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
