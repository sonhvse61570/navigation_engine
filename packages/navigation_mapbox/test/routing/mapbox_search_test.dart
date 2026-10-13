import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_mapbox/navigation_mapbox.dart';

// Fixtures (test/routing/fixtures), hand-written in the shape of the Search
// Box API documentation (https://docs.mapbox.com/api/search/search-box/);
// none was recorded, and the ids are redacted:
// - suggest.json: /suggest, with a POI, a category suggestion (not a
//   place), a locality, a place and a POI with no place_formatted.
// - retrieve.json: /retrieve for the first suggestion.
// - reverse.json, reverse_empty.json: /reverse (an address, then a
//   locality).

String fixture(String name) =>
    File('test/routing/fixtures/$name').readAsStringSync();

/// A fake token: requests must carry it, messages must not.
const token = 'test-token';

/// A search whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({MapboxSearch search, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? accessToken = token,
  Uri? baseUrl,
  Map<String, String> headers = const {},
  String? userAgent = MapboxSearch.defaultUserAgent,
  GeoPoint? proximity,
  String? country,
  String? language,
  int? limit,
}) {
  final requests = <http.Request>[];
  final search = MapboxSearch(
    accessToken: accessToken,
    baseUrl: baseUrl,
    headers: headers,
    userAgent: userAgent,
    proximity: proximity,
    country: country,
    language: language,
    limit: limit,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (search: search, requests: requests);
}

/// A search whose server answers each endpoint (`suggest`, `retrieve`,
/// `reverse`) with its fixture.
({MapboxSearch search, List<http.Request> requests}) serveAll({
  String? language,
}) {
  final requests = <http.Request>[];
  final bodies = {
    'suggest': fixture('suggest.json'),
    'retrieve': fixture('retrieve.json'),
    'reverse': fixture('reverse.json'),
  };
  final search = MapboxSearch(
    accessToken: token,
    language: language,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(bodies[req.url.pathSegments[3]]!),
        200,
      );
    }),
  );
  return (search: search, requests: requests);
}

/// A client that forwards to [inner] and records [close].
class RecordingClient extends http.BaseClient {
  RecordingClient(this.inner);

  final http.Client inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() => closed = true;
}

const suggestion = PlaceSuggestion(
  id: 'REDACTED-mapbox-id-1',
  title: 'Hồ Hoàn Kiếm',
  subtitle: 'Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội, Việt Nam',
);

const hoanKiem = GeoPoint(21.028772, 105.852379);

void main() {
  group('autocomplete', () {
    test('asks /suggest with the query encoded, the session token and the '
        'token last', () async {
      final s = serve(fixture('suggest.json'));
      final session = PlaceSearchSession();
      await s.search.autocomplete('Hồ Hoàn Kiếm & co', session: session);
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.host, 'api.mapbox.com');
      expect(req.url.path, '/search/searchbox/v1/suggest');
      expect(
        req.url.query,
        'q=H%E1%BB%93%20Ho%C3%A0n%20Ki%E1%BA%BFm%20%26%20co'
        '&session_token=${session.token}&access_token=test-token',
      );
      expect(req.url.queryParameters['q'], 'Hồ Hoàn Kiếm & co');
      expect(req.headers['Accept'], 'application/json');
    });

    test('the query is trimmed; an empty one asks nothing', () async {
      final s = serve(fixture('suggest.json'));
      expect(await s.search.autocomplete('   '), isEmpty);
      expect(s.requests, isEmpty);
      await s.search.autocomplete('  phở  ');
      expect(s.requests.single.url.queryParameters['q'], 'phở');
    });

    test(
      'near is sent as proximity, lon,lat; else the proximity option',
      () async {
        final s = serve(
          fixture('suggest.json'),
          proximity: const GeoPoint(10.5, 106.25),
        );
        await s.search.autocomplete('phở', near: hoanKiem);
        await s.search.autocomplete('phở');
        expect(
          [for (final r in s.requests) r.url.queryParameters['proximity']],
          ['105.852379,21.028772', '106.25,10.5'],
        );
        expect(s.requests.first.url.query, contains('&proximity=105.852379,'));
      },
    );

    test('country, language and limit are sent, in order', () async {
      final s = serve(
        fixture('suggest.json'),
        country: 'vn,la',
        language: 'vi',
        limit: 5,
      );
      final session = PlaceSearchSession();
      await s.search.autocomplete('phở', near: hoanKiem, session: session);
      expect(
        s.requests.single.url.query,
        'q=ph%E1%BB%9F&session_token=${session.token}'
        '&proximity=105.852379,21.028772&country=vn,la&language=vi&limit=5'
        '&access_token=test-token',
      );
    });

    test('a limit outside 1..10 throws', () {
      for (final limit in [0, 11, -1]) {
        expect(
          () => MapboxSearch(accessToken: token, limit: limit),
          throwsArgumentError,
          reason: '$limit',
        );
      }
      MapboxSearch(accessToken: token, limit: 10).close();
    });

    test('a constructor that throws creates no client', () {
      var created = 0;
      for (final make in <MapboxSearch Function()>[
        () => MapboxSearch(accessToken: token, limit: 0),
        () => MapboxSearch(
          accessToken: token,
          proximity: const GeoPoint(double.nan, 1),
        ),
      ]) {
        expect(
          () => http.runWithClient(make, () {
            created++;
            return MockClient((_) async => http.Response('', 200));
          }),
          throwsArgumentError,
        );
      }
      expect(created, 0);
    });

    test('a near that is not finite throws before any request', () async {
      final s = serve(fixture('suggest.json'));
      await expectLater(
        s.search.autocomplete('phở', near: const GeoPoint(double.nan, 1)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test("the session's token is sent on every call; without a session each "
        'call has its own token', () async {
      final s = serve(fixture('suggest.json'));
      final session = PlaceSearchSession();
      await s.search.autocomplete('p', session: session);
      await s.search.autocomplete('ph', session: session);
      await s.search.autocomplete('phở');
      await s.search.autocomplete('phở');
      final tokens = [
        for (final r in s.requests) r.url.queryParameters['session_token'],
      ];
      expect(tokens[0], session.token);
      expect(tokens[1], session.token);
      expect(tokens[2], hasLength(36));
      expect(tokens[3], hasLength(36));
      expect(tokens[2], isNot(tokens[3]));
      expect(tokens[2], isNot(session.token));
    });

    test('the suggestions: mapbox_id, name and place_formatted, no position; '
        'categories are left out', () async {
      final s = serve(fixture('suggest.json'));
      expect(await s.search.autocomplete('ho'), const [
        suggestion,
        PlaceSuggestion(
          id: 'REDACTED-mapbox-id-2',
          title: 'Hoàn Kiếm',
          subtitle: 'Hà Nội, Việt Nam',
        ),
        PlaceSuggestion(
          id: 'REDACTED-mapbox-id-6',
          title: 'Hà Nội',
          subtitle: 'Việt Nam',
        ),
        PlaceSuggestion(id: 'REDACTED-mapbox-id-3', title: 'Hồ Tây'),
      ]);
    });

    test('no suggestion is an empty list', () async {
      final s = serve('{"suggestions": [], "attribution": ""}');
      expect(await s.search.autocomplete('zzz'), isEmpty);
    });
  });

  group('resolve', () {
    test('asks /retrieve/{mapbox_id} with the session token', () async {
      final s = serve(fixture('retrieve.json'), language: 'vi');
      final session = PlaceSearchSession();
      await s.search.resolve(suggestion, session: session);
      final req = s.requests.single;
      expect(
        req.url.path,
        '/search/searchbox/v1/retrieve/REDACTED-mapbox-id-1',
      );
      expect(
        req.url.query,
        'session_token=${session.token}&language=vi&access_token=test-token',
      );
    });

    test('an id with reserved characters is one path segment', () async {
      final s = serve(fixture('retrieve.json'));
      await s.search.resolve(
        const PlaceSuggestion(id: 'a/b?c', title: 'x'),
        session: PlaceSearchSession(),
      );
      expect(s.requests.single.url.pathSegments.last, 'a/b?c');
      expect(
        s.requests.single.url.path,
        '/search/searchbox/v1/retrieve/a%2Fb%3Fc',
      );
    });

    test('the place: its name, full address and coordinates', () async {
      final s = serve(fixture('retrieve.json'));
      expect(
        await s.search.resolve(suggestion),
        const Place(
          id: 'REDACTED-mapbox-id-1',
          name: 'Hồ Hoàn Kiếm',
          address: 'Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội, Việt Nam',
          position: hoanKiem,
        ),
      );
      expect(
        s.requests.single.url.queryParameters['session_token'],
        hasLength(36),
      );
    });

    test("a feature without a name, a full address or an id takes the "
        "suggestion's title, place_formatted and id", () async {
      final s = serve(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [105.8, 21.0],
              },
              'properties': {'place_formatted': 'Hà Nội, Việt Nam'},
            },
          ],
        }),
      );
      expect(
        await s.search.resolve(suggestion),
        const Place(
          id: 'REDACTED-mapbox-id-1',
          name: 'Hồ Hoàn Kiếm',
          address: 'Hà Nội, Việt Nam',
          position: GeoPoint(21.0, 105.8),
        ),
      );
    });

    test('an empty id throws before any request', () async {
      final s = serve(fixture('retrieve.json'));
      await expectLater(
        s.search.resolve(const PlaceSuggestion(id: '', title: 'x')),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('no feature is a MapboxSearchException', () async {
      final s = serve(fixture('reverse_empty.json'));
      final e = await _thrown<MapboxSearchException>(
        s.search.resolve(suggestion),
      );
      expect(e.message, 'Mapbox retrieve failed');
      expect(
        e.cause,
        isA<MapboxDirectionsFormatException>().having(
          (c) => c.message,
          'message',
          'features: no feature for the id',
        ),
      );
    });
  });

  group('sessions', () {
    test('autocomplete then resolve send the same token', () async {
      final s = serveAll();
      final session = PlaceSearchSession();
      final found = await s.search.autocomplete('ho', session: session);
      await s.search.resolve(found.first, session: session);
      expect(
        [for (final r in s.requests) r.url.queryParameters['session_token']],
        [session.token, session.token],
      );
    });
  });

  group('reverse', () {
    test('asks /reverse with longitude and latitude, one result, and no '
        'session', () async {
      final s = serve(
        fixture('reverse.json'),
        country: 'vn',
        language: 'vi',
        limit: 5,
      );
      await s.search.reverse(hoanKiem);
      final req = s.requests.single;
      expect(req.url.path, '/search/searchbox/v1/reverse');
      expect(
        req.url.query,
        'longitude=105.852379&latitude=21.028772&country=vn&language=vi'
        '&limit=1&access_token=test-token',
      );
    });

    test('the first feature: its name, full address and coordinates', () async {
      final s = serve(fixture('reverse.json'));
      expect(
        await s.search.reverse(hoanKiem),
        const Place(
          id: 'REDACTED-mapbox-id-4',
          name: '12 Đinh Tiên Hoàng',
          address: '12 Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội, Việt Nam',
          position: GeoPoint(21.02879, 105.85241),
        ),
      );
    });

    test('a feature without a name is named by its address', () async {
      final s = serve(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [105.8, 21.0],
              },
              'properties': {
                'mapbox_id': 'x',
                'full_address': 'Hà Nội, Việt Nam',
              },
            },
          ],
        }),
      );
      expect(
        await s.search.reverse(hoanKiem),
        const Place(
          id: 'x',
          name: 'Hà Nội, Việt Nam',
          address: 'Hà Nội, Việt Nam',
          position: GeoPoint(21.0, 105.8),
        ),
      );
    });

    test('nothing there is null', () async {
      final s = serve(fixture('reverse_empty.json'));
      expect(await s.search.reverse(hoanKiem), isNull);
    });

    test('a point that is not finite throws before any request', () async {
      final s = serve(fixture('reverse.json'));
      await expectLater(
        s.search.reverse(const GeoPoint(1, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('options', () {
    test(
      'a null accessToken, a baseUrl with a path, and extra headers',
      () async {
        final s = serve(
          fixture('suggest.json'),
          accessToken: null,
          baseUrl: Uri.parse('https://proxy.example.com/mapbox/?tenant=a'),
          headers: {'X-Proxy-Token': 'p'},
        );
        final session = PlaceSearchSession();
        await s.search.autocomplete('phở', session: session);
        final req = s.requests.single;
        expect(req.url.host, 'proxy.example.com');
        expect(req.url.path, '/mapbox/search/searchbox/v1/suggest');
        expect(
          req.url.query,
          'tenant=a&q=ph%E1%BB%9F&session_token=${session.token}',
        );
        expect(req.headers['X-Proxy-Token'], 'p');
      },
    );

    test('userAgent null sends none', () async {
      final s = serve(fixture('suggest.json'), userAgent: null);
      await s.search.autocomplete('phở');
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final search = MapboxSearch(accessToken: token);
      expect(search.baseUrl, Uri.parse('https://api.mapbox.com'));
      expect(MapboxSearch.defaultBaseUrl, search.baseUrl);
      expect(search.headers, isEmpty);
      expect(search.timeout, const Duration(seconds: 12));
      expect(search.userAgent, 'navigation_mapbox/0.1.0');
      expect(search.proximity, isNull);
      expect(search.country, isNull);
      expect(search.language, isNull);
      expect(search.limit, isNull);
      search.close();
    });
  });

  group('errors', () {
    test('an HTTP error throws a MapboxSearchException with the status and '
        'the typed cause', () async {
      final s = serve(
        '{"message":"Not Authorized - Invalid Token"}',
        status: 401,
      );
      final e = await _thrown<MapboxSearchException>(
        s.search.autocomplete('phở'),
      );
      expect(e, isA<PlaceSearchException>());
      expect(e.statusCode, 401);
      expect(e.message, 'Mapbox suggest failed');
      expect(
        e.cause,
        isA<MapboxDirectionsHttpException>().having(
          (c) => c.statusCode,
          'status',
          401,
        ),
      );
      expect(
        e.toString(),
        'MapboxSearchException: Mapbox suggest failed (401); cause: '
        'MapboxDirectionsHttpException: Mapbox request failed with HTTP 401 '
        '(the access token is missing or not valid): {"message":"Not '
        'Authorized - Invalid Token"}',
      );
    });

    test('each request names itself', () async {
      final s = serve('Too Many Requests', status: 429);
      final messages = <String>[];
      for (final call in <Future<Object?> Function()>[
        () => s.search.autocomplete('phở'),
        () => s.search.resolve(suggestion),
        () => s.search.reverse(hoanKiem),
      ]) {
        final e = await _thrown<MapboxSearchException>(call());
        expect(e.statusCode, 429);
        messages.add(e.message);
      }
      expect(messages, [
        'Mapbox suggest failed',
        'Mapbox retrieve failed',
        'Mapbox reverse failed',
      ]);
    });

    test('an answer of the wrong shape names the field', () async {
      final cases = <(String, Future<Object?> Function(MapboxSearch)), String>{
        ('[]', (m) => m.autocomplete('a')):
            'the answer is not a JSON object: got an array',
        ('{}', (m) => m.autocomplete('a')):
            'suggestions: expected an array, got null',
        ('{"suggestions": [{"name": "x"}]}', (m) => m.autocomplete('a')):
            'suggestions[0].mapbox_id: expected a string, got null',
        (
          '{"suggestions": [{"mapbox_id": "x", "name": 3}]}',
          (m) => m.autocomplete('a'),
        ): 'suggestions[0].name: expected a string, got a number',
        ('{"features": {}}', (m) => m.reverse(hoanKiem)):
            'features: expected an array, got an object',
        (
          '{"features": [{"geometry": {"coordinates": [1]}}]}',
          (m) => m.reverse(hoanKiem),
        ): 'features[0].geometry.coordinates: expected [longitude, latitude]',
        (
          '{"features": [{"geometry": {"coordinates": [200, 1]}}]}',
          (m) => m.reverse(hoanKiem),
        ): 'features[0].geometry.coordinates[0]: out of range (200.0)',
        (
          '{"features": [{"geometry": {"coordinates": [1, 91]}}]}',
          (m) => m.resolve(suggestion),
        ): 'features[0].geometry.coordinates[1]: out of range (91.0)',
        (
          '{"features": [{"geometry": {"coordinates": [1, 2]}, '
              '"properties": []}]}',
          (m) => m.resolve(suggestion),
        ): 'features[0].properties: expected an object, got an array',
        ('not json', (m) => m.reverse(hoanKiem)):
            'the answer is not a JSON object: invalid JSON',
      };
      for (final MapEntry(key: (body, call), value: message) in cases.entries) {
        final e = await _thrown<MapboxSearchException>(
          call(serve(body).search),
        );
        expect(
          e.cause,
          isA<MapboxDirectionsFormatException>().having(
            (c) => c.message,
            'message',
            startsWith(message),
          ),
          reason: body,
        );
        expect(e.statusCode, isNull);
      }
    });

    test('a timeout is a MapboxDirectionsTimeoutException cause, also a '
        'TimeoutException', () async {
      final search = MapboxSearch(
        accessToken: token,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
      );
      final e = await _thrown<MapboxSearchException>(
        search.autocomplete('phở'),
      );
      expect(e.cause, isA<MapboxDirectionsTimeoutException>());
      expect(e.cause, isA<TimeoutException>());
      expect(e.statusCode, isNull);
    });

    test('a transport error is the cause', () async {
      final error = http.ClientException('offline');
      final search = MapboxSearch(
        accessToken: token,
        client: MockClient((_) async => throw error),
      );
      final e = await _thrown<MapboxSearchException>(search.reverse(hoanKiem));
      expect(e.cause, same(error));
    });
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(fixture('suggest.json')), 200),
        ),
      );
      final search = MapboxSearch(accessToken: token, client: client);
      await search.autocomplete('ho');
      search.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the search created', () async {
      final created = RecordingClient(
        MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(fixture('suggest.json')), 200),
        ),
      );
      final search = http.runWithClient(
        () => MapboxSearch(accessToken: token),
        () => created,
      );
      await search.autocomplete('ho');
      search.close();
      expect(created.closed, isTrue);
      search.close();
    });

    test('a closed search throws StateError', () async {
      final s = serve(fixture('suggest.json'));
      s.search.close();
      await expectLater(s.search.autocomplete('a'), throwsStateError);
      await expectLater(s.search.resolve(suggestion), throwsStateError);
      await expectLater(s.search.reverse(hoanKiem), throwsStateError);
      expect(s.requests, isEmpty);
    });
  });
}

/// The error [future] fails with, which must be a [T].
Future<T> _thrown<T extends Object>(Future<Object?> future) async {
  try {
    await future;
  } on T catch (e) {
    return e;
  }
  fail('expected a $T');
}
