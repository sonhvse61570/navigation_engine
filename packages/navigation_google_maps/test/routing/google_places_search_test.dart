import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_google_maps/navigation_google_maps.dart';

// Fixtures (test/routing/fixtures), hand-written in the shape of the Places API
// (New) and Geocoding API documentation; none was recorded, and the ids
// are redacted:
// - autocomplete.json: places:autocomplete, with a place prediction, a
//   query prediction (skipped), a place with a secondary text and one
//   without a structured format.
// - place_details.json: places/{id} with the field mask
//   id,displayName,formattedAddress,location.
// - geocode.json, geocode_zero_results.json, geocode_request_denied.json:
//   the Geocoding API's reverse answers (status OK, ZERO_RESULTS,
//   REQUEST_DENIED).

String fixture(String name) =>
    File('test/routing/fixtures/$name').readAsStringSync();

/// A fake key: requests must carry it, messages must not.
const key = 'test-key';

/// A search whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({GooglePlacesSearch search, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? apiKey = key,
  Uri? placesBaseUrl,
  Uri? geocodingBaseUrl,
  Map<String, String> headers = const {},
  String? userAgent = GooglePlacesSearch.defaultUserAgent,
  GeoPoint? proximity,
  double biasRadius = GooglePlacesSearch.defaultBiasRadius,
  List<String>? regionCodes,
  String? languageCode,
  bool fetchDisplayName = false,
}) {
  final requests = <http.Request>[];
  final search = GooglePlacesSearch(
    fetchDisplayName: fetchDisplayName,
    apiKey: apiKey,
    placesBaseUrl: placesBaseUrl,
    geocodingBaseUrl: geocodingBaseUrl,
    headers: headers,
    userAgent: userAgent,
    proximity: proximity,
    biasRadius: biasRadius,
    regionCodes: regionCodes,
    languageCode: languageCode,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=UTF-8'},
      );
    }),
  );
  return (search: search, requests: requests);
}

/// The JSON body of [request].
Map<String, Object?> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

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
  id: 'REDACTED-place-id-1',
  title: 'Chợ Bến Thành',
  subtitle: 'Lê Lợi, Bến Thành, Quận 1, Hồ Chí Minh, Việt Nam',
);

const benThanh = GeoPoint(10.77243, 106.69805);

void main() {
  group('autocomplete', () {
    test(
      'POSTs places:autocomplete with the key header and the input',
      () async {
        final s = serve(fixture('autocomplete.json'));
        await s.search.autocomplete('Chợ Bến Thành');
        final req = s.requests.single;
        expect(req.method, 'POST');
        expect(
          req.url.toString(),
          'https://places.googleapis.com/v1/places:autocomplete',
        );
        expect(req.headers['X-Goog-Api-Key'], 'test-key');
        expect(req.headers['Content-Type'], startsWith('application/json'));
        expect(req.headers['Accept'], 'application/json');
        expect(req.headers['User-Agent'], 'navigation_google_maps/0.1.0');
        expect(bodyOf(req), {'input': 'Chợ Bến Thành'});
      },
    );

    test('the session token, language, region codes and a circle bias from '
        'near, in order', () async {
      final s = serve(
        fixture('autocomplete.json'),
        languageCode: 'vi',
        regionCodes: ['vn'],
        biasRadius: 5000,
      );
      final session = PlaceSearchSession();
      await s.search.autocomplete('chợ', near: benThanh, session: session);
      final body = bodyOf(s.requests.single);
      expect(body, {
        'input': 'chợ',
        'sessionToken': session.token,
        'languageCode': 'vi',
        'includedRegionCodes': ['vn'],
        'locationBias': {
          'circle': {
            'center': {'latitude': 10.77243, 'longitude': 106.69805},
            'radius': 5000.0,
          },
        },
      });
      expect(body.keys, [
        'input',
        'sessionToken',
        'languageCode',
        'includedRegionCodes',
        'locationBias',
      ]);
    });

    test('near, else the proximity option, biases the suggestions', () async {
      final s = serve(
        fixture('autocomplete.json'),
        proximity: const GeoPoint(10.5, 106.25),
      );
      await s.search.autocomplete('chợ', near: benThanh);
      await s.search.autocomplete('chợ');
      expect(
        [
          for (final r in s.requests)
            ((bodyOf(r)['locationBias']! as Map)['circle']! as Map)['center'],
        ],
        [
          {'latitude': 10.77243, 'longitude': 106.69805},
          {'latitude': 10.5, 'longitude': 106.25},
        ],
      );
    });

    test('the query is trimmed; an empty one asks nothing', () async {
      final s = serve(fixture('autocomplete.json'));
      expect(await s.search.autocomplete('   '), isEmpty);
      expect(s.requests, isEmpty);
      await s.search.autocomplete('  phở  ');
      expect(bodyOf(s.requests.single)['input'], 'phở');
    });

    test("the session's token is sent on every call; without a session, "
        'none', () async {
      final s = serve(fixture('autocomplete.json'));
      final session = PlaceSearchSession();
      await s.search.autocomplete('c', session: session);
      await s.search.autocomplete('ch', session: session);
      await s.search.autocomplete('chợ');
      expect(
        [for (final r in s.requests) bodyOf(r)['sessionToken']],
        [session.token, session.token, null],
      );
      expect(bodyOf(s.requests.last).containsKey('sessionToken'), isFalse);
    });

    test('place predictions: placeId, mainText and secondaryText (else '
        'text); query predictions are left out', () async {
      final s = serve(fixture('autocomplete.json'));
      expect(await s.search.autocomplete('bến thành'), const [
        suggestion,
        PlaceSuggestion(
          id: 'REDACTED-place-id-2',
          title: 'Bến Thành',
          subtitle: 'Quận 1, Hồ Chí Minh, Việt Nam',
        ),
        PlaceSuggestion(id: 'REDACTED-place-id-3', title: 'Việt Nam'),
      ]);
    });

    test('no suggestion is an empty list', () async {
      expect(await serve('{}').search.autocomplete('zzz'), isEmpty);
      expect(
        await serve('{"suggestions": []}').search.autocomplete('zzz'),
        isEmpty,
      );
    });

    test('a near that is not finite throws before any request', () async {
      final s = serve(fixture('autocomplete.json'));
      await expectLater(
        s.search.autocomplete('chợ', near: const GeoPoint(double.nan, 1)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('constructor', () {
    test('a bad biasRadius, regionCodes or proximity throws', () {
      for (final make in <GooglePlacesSearch Function()>[
        () => GooglePlacesSearch(apiKey: key, biasRadius: 0),
        () => GooglePlacesSearch(apiKey: key, biasRadius: 50000.1),
        () => GooglePlacesSearch(apiKey: key, biasRadius: double.nan),
        () => GooglePlacesSearch(
          apiKey: key,
          regionCodes: [for (var i = 0; i < 16; i++) 'vn'],
        ),
        () => GooglePlacesSearch(
          apiKey: key,
          proximity: const GeoPoint(double.nan, 1),
        ),
      ]) {
        expect(make, throwsArgumentError);
      }
      GooglePlacesSearch(
        apiKey: key,
        biasRadius: 50000,
        regionCodes: [for (var i = 0; i < 15; i++) 'vn'],
      ).close();
    });

    test('a constructor that throws creates no client', () {
      var created = 0;
      for (final make in <GooglePlacesSearch Function()>[
        () => GooglePlacesSearch(apiKey: key, biasRadius: -1),
        () => GooglePlacesSearch(
          apiKey: key,
          regionCodes: [for (var i = 0; i < 16; i++) 'vn'],
        ),
        () => GooglePlacesSearch(
          apiKey: key,
          proximity: const GeoPoint(1, double.infinity),
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
  });

  group('resolve', () {
    test('GETs places/{id} with the field mask, the session token and the '
        'language', () async {
      final s = serve(fixture('place_details.json'), languageCode: 'vi');
      final session = PlaceSearchSession();
      await s.search.resolve(suggestion, session: session);
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'https://places.googleapis.com/v1/places/REDACTED-place-id-1'
        '?sessionToken=${session.token}&languageCode=vi',
      );
      expect(req.headers['X-Goog-Api-Key'], 'test-key');
      // Essentials fields only, by default.
      expect(req.headers['X-Goog-FieldMask'], 'id,formattedAddress,location');
      expect(
        GooglePlacesSearch.detailsFieldMask,
        'id,formattedAddress,location',
      );
    });

    test('fetchDisplayName adds displayName to the field mask', () async {
      final s = serve(fixture('place_details.json'), fetchDisplayName: true);
      await s.search.resolve(suggestion);
      expect(
        s.requests.single.headers['X-Goog-FieldMask'],
        'id,displayName,formattedAddress,location',
      );
      expect(
        GooglePlacesSearch.detailsFieldMaskWithDisplayName,
        'id,displayName,formattedAddress,location',
      );
      expect(s.search.fetchDisplayName, isTrue);
    });

    test('without a session or a language, no query', () async {
      final s = serve(fixture('place_details.json'));
      await s.search.resolve(suggestion);
      expect(s.requests.single.url.hasQuery, isFalse);
    });

    test('an id with reserved characters is one path segment', () async {
      final s = serve(fixture('place_details.json'));
      await s.search.resolve(const PlaceSuggestion(id: 'a/b?c', title: 'x'));
      expect(s.requests.single.url.pathSegments.last, 'a/b?c');
      expect(s.requests.single.url.path, '/v1/places/a%2Fb%3Fc');
    });

    test("the place: its id, address and location, named by the "
        "suggestion's title", () async {
      final s = serve(fixture('place_details.json'));
      const titled = PlaceSuggestion(
        id: 'REDACTED-place-id-1',
        title: 'Ben Thanh Market',
      );
      expect(
        await s.search.resolve(titled),
        const Place(
          id: 'REDACTED-place-id-1',
          name: 'Ben Thanh Market',
          address:
              'Lê Lợi, Phường Bến Thành, Quận 1, Hồ Chí Minh 700000, Việt Nam',
          position: GeoPoint(10.7724297, 106.6980484),
        ),
      );
    });

    test(
      'with fetchDisplayName, the place is named by its displayName',
      () async {
        final s = serve(fixture('place_details.json'), fetchDisplayName: true);
        const titled = PlaceSuggestion(
          id: 'REDACTED-place-id-1',
          title: 'Ben Thanh Market',
        );
        expect((await s.search.resolve(titled)).name, 'Chợ Bến Thành');
        // Without a displayName in the answer: the suggestion's title.
        final none = serve(
          jsonEncode({
            'location': {'latitude': 10.7, 'longitude': 106.6},
          }),
          fetchDisplayName: true,
        );
        expect((await none.search.resolve(titled)).name, 'Ben Thanh Market');
      },
    );

    test('a suggestion without a title is named by the address', () async {
      final s = serve(fixture('place_details.json'));
      expect(
        (await s.search.resolve(
          const PlaceSuggestion(id: 'REDACTED-place-id-1', title: ''),
        )).name,
        'Lê Lợi, Phường Bến Thành, Quận 1, Hồ Chí Minh 700000, Việt Nam',
      );
    });

    test("a place without an id, a name or an address takes the "
        "suggestion's", () async {
      final s = serve(
        jsonEncode({
          'location': {'latitude': 10.7, 'longitude': 106.6},
        }),
      );
      expect(
        await s.search.resolve(suggestion),
        const Place(
          id: 'REDACTED-place-id-1',
          name: 'Chợ Bến Thành',
          position: GeoPoint(10.7, 106.6),
        ),
      );
    });

    test('an empty id throws before any request', () async {
      final s = serve(fixture('place_details.json'));
      await expectLater(
        s.search.resolve(const PlaceSuggestion(id: '', title: 'x')),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('sessions', () {
    test('autocomplete then resolve send the same token', () async {
      final requests = <http.Request>[];
      final search = GooglePlacesSearch(
        apiKey: key,
        client: MockClient((req) async {
          requests.add(req);
          final body = req.method == 'POST'
              ? fixture('autocomplete.json')
              : fixture('place_details.json');
          return http.Response.bytes(utf8.encode(body), 200);
        }),
      );
      final session = PlaceSearchSession();
      final found = await search.autocomplete('chợ', session: session);
      await search.resolve(found.first, session: session);
      expect(bodyOf(requests[0])['sessionToken'], session.token);
      expect(requests[1].url.queryParameters['sessionToken'], session.token);
    });
  });

  group('reverse', () {
    test(
      'GETs the Geocoding API with latlng, the key and the language',
      () async {
        final s = serve(fixture('geocode.json'), languageCode: 'vi');
        await s.search.reverse(benThanh);
        final req = s.requests.single;
        expect(req.method, 'GET');
        expect(
          req.url.toString(),
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=10.77243,106.69805&key=test-key&language=vi',
        );
        expect(req.headers.containsKey('X-Goog-Api-Key'), isFalse);
      },
    );

    test('the key is encoded; a null key sends none', () async {
      final s = serve(fixture('geocode.json'), apiKey: 'k/y+z=');
      await s.search.reverse(benThanh);
      expect(s.requests.single.url.query, endsWith('&key=k%2Fy%2Bz%3D'));
      expect(s.requests.single.url.queryParameters['key'], 'k/y+z=');
      final none = serve(fixture('geocode.json'), apiKey: null);
      await none.search.reverse(benThanh);
      expect(none.requests.single.url.query, 'latlng=10.77243,106.69805');
    });

    test(
      'the first result: its formatted address, place id and location',
      () async {
        final s = serve(fixture('geocode.json'));
        expect(
          await s.search.reverse(benThanh),
          const Place(
            id: 'REDACTED-place-id-4',
            name: 'Lê Lợi, Bến Thành, Quận 1, Hồ Chí Minh, Việt Nam',
            address: 'Lê Lợi, Bến Thành, Quận 1, Hồ Chí Minh, Việt Nam',
            position: GeoPoint(10.7724541, 106.6981025),
          ),
        );
      },
    );

    test('ZERO_RESULTS is null', () async {
      final s = serve(fixture('geocode_zero_results.json'));
      expect(await s.search.reverse(benThanh), isNull);
    });

    test('an error status is a GoogleRoutesStatusException cause', () async {
      final cases = {
        fixture('geocode_request_denied.json'): (
          'REQUEST_DENIED',
          'Google REQUEST_DENIED: the request was denied: check the key and '
              'its restrictions (The provided API key is invalid.) [HTTP 200]',
        ),
        '{"status": "OVER_QUERY_LIMIT", "results": []}': (
          'OVER_QUERY_LIMIT',
          'Google OVER_QUERY_LIMIT: quota or rate limit reached [HTTP 200]',
        ),
        '{"status": "INVALID_REQUEST", "results": []}': (
          'INVALID_REQUEST',
          'Google INVALID_REQUEST: the server rejected the request [HTTP 200]',
        ),
        '{"status": "UNKNOWN_ERROR", "results": []}': (
          'UNKNOWN_ERROR',
          'Google UNKNOWN_ERROR: a server error; retrying may succeed '
              '[HTTP 200]',
        ),
      };
      for (final MapEntry(key: body, value: (status, message))
          in cases.entries) {
        final e = await _thrown<GooglePlacesSearchException>(
          serve(body).search.reverse(benThanh),
        );
        expect(e.message, 'Google reverse geocoding failed');
        expect(e.statusCode, 200);
        expect(
          e.cause,
          isA<GoogleRoutesStatusException>()
              .having((c) => c.status, 'status', status)
              .having((c) => c.message, 'message', message),
        );
      }
    });

    test('a point that is not finite throws before any request', () async {
      final s = serve(fixture('geocode.json'));
      await expectLater(
        s.search.reverse(const GeoPoint(1, double.infinity)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('options', () {
    test('a null apiKey, base URLs with a path, and extra headers', () async {
      final s = serve(
        fixture('autocomplete.json'),
        apiKey: null,
        placesBaseUrl: Uri.parse('https://proxy.example.com/places/?t=a'),
        headers: {'X-Proxy-Token': 'p'},
      );
      await s.search.autocomplete('chợ');
      final req = s.requests.single;
      expect(
        req.url.toString(),
        'https://proxy.example.com/places/v1/places:autocomplete?t=a',
      );
      expect(req.headers.containsKey('X-Goog-Api-Key'), isFalse);
      expect(req.headers['X-Proxy-Token'], 'p');
      final g = serve(
        fixture('geocode.json'),
        apiKey: null,
        geocodingBaseUrl: Uri.parse('https://proxy.example.com/geo?t=b'),
      );
      await g.search.reverse(benThanh);
      expect(
        g.requests.single.url.toString(),
        'https://proxy.example.com/geo/maps/api/geocode/json'
        '?t=b&latlng=10.77243,106.69805',
      );
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('autocomplete.json'), userAgent: null);
      await s.search.autocomplete('chợ');
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final search = GooglePlacesSearch(apiKey: key);
      expect(search.placesBaseUrl, Uri.parse('https://places.googleapis.com'));
      expect(search.geocodingBaseUrl, Uri.parse('https://maps.googleapis.com'));
      expect(GooglePlacesSearch.defaultPlacesBaseUrl, search.placesBaseUrl);
      expect(
        GooglePlacesSearch.defaultGeocodingBaseUrl,
        search.geocodingBaseUrl,
      );
      expect(search.headers, isEmpty);
      expect(search.timeout, const Duration(seconds: 12));
      expect(search.userAgent, 'navigation_google_maps/0.1.0');
      expect(search.proximity, isNull);
      expect(search.biasRadius, 20000);
      expect(GooglePlacesSearch.defaultBiasRadius, 20000);
      expect(search.regionCodes, isNull);
      expect(search.languageCode, isNull);
      expect(search.fetchDisplayName, isFalse);
      search.close();
    });
  });

  group('errors', () {
    test('an RPC error throws a GooglePlacesSearchException with the status '
        'and the typed cause', () async {
      final s = serve(
        jsonEncode({
          'error': {
            'code': 400,
            'message': 'API key not valid. Please pass a valid API key.',
            'status': 'INVALID_ARGUMENT',
          },
        }),
        status: 400,
      );
      final e = await _thrown<GooglePlacesSearchException>(
        s.search.autocomplete('chợ'),
      );
      expect(e, isA<PlaceSearchException>());
      expect(e.statusCode, 400);
      expect(e.message, 'Google autocomplete failed');
      expect(
        e.toString(),
        'GooglePlacesSearchException: Google autocomplete failed (400); '
        'cause: GoogleRoutesStatusException: Google INVALID_ARGUMENT: the '
        'server rejected the request (API key not valid. Please pass a valid '
        'API key.) [HTTP 400]',
      );
    });

    test('each request names itself', () async {
      final s = serve('Too Many Requests', status: 429);
      final messages = <String>[];
      for (final call in <Future<Object?> Function()>[
        () => s.search.autocomplete('chợ'),
        () => s.search.resolve(suggestion),
        () => s.search.reverse(benThanh),
      ]) {
        final e = await _thrown<GooglePlacesSearchException>(call());
        expect(e.statusCode, 429);
        expect(e.cause, isA<GoogleRoutesHttpException>());
        messages.add(e.message);
      }
      expect(messages, [
        'Google autocomplete failed',
        'Google place details failed',
        'Google reverse geocoding failed',
      ]);
    });

    test('an answer of the wrong shape names the field', () async {
      final cases =
          <(String, Future<Object?> Function(GooglePlacesSearch)), String>{
            ('[]', (m) => m.autocomplete('a')):
                'the answer is not a JSON object: got an array',
            ('{"suggestions": {}}', (m) => m.autocomplete('a')):
                'suggestions: expected an array, got an object',
            (
              '{"suggestions": [{"placePrediction": {"text": {"text": "x"}}}]}',
              (m) => m.autocomplete('a'),
            ): 'suggestions[0].placePrediction.placeId: expected a string, '
                'got null',
            (
              '{"suggestions": [{"placePrediction": {"placeId": "x"}}]}',
              (m) => m.autocomplete('a'),
            ): 'suggestions[0].placePrediction.text: expected an object, got '
                'null',
            ('{}', (m) => m.resolve(suggestion)):
                'location: expected an object, got null',
            (
              '{"location": {"latitude": 91, "longitude": 1}}',
              (m) => m.resolve(suggestion),
            ): 'location.latitude: out of range (91.0)',
            (
              '{"location": {"latitude": 1, "longitude": 1}, '
                  '"formattedAddress": 3}',
              (m) => m.resolve(suggestion),
            ): 'formattedAddress: expected a string, got a number',
            ('{"results": []}', (m) => m.reverse(benThanh)):
                'status: expected a string, got null',
            ('{"status": "OK", "results": []}', (m) => m.reverse(benThanh)):
                'results: an OK answer with no results',
            (
              '{"status": "OK", "results": [{"geometry": {"location": '
                  '{"lat": 1, "lng": 200}}}]}',
              (m) => m.reverse(benThanh),
            ): 'results[0].geometry.location.lng: out of range (200.0)',
            ('not json', (m) => m.reverse(benThanh)):
                'the answer is not a JSON object: invalid JSON',
          };
      for (final MapEntry(key: (body, call), value: message) in cases.entries) {
        final e = await _thrown<GooglePlacesSearchException>(
          call(serve(body).search),
        );
        expect(
          e.cause,
          isA<GoogleRoutesFormatException>().having(
            (c) => c.message,
            'message',
            startsWith(message),
          ),
          reason: body,
        );
        expect(e.statusCode, isNull);
      }
    });

    test('a timeout is a GoogleRoutesTimeoutException cause, also a '
        'TimeoutException', () async {
      final search = GooglePlacesSearch(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
      );
      final e = await _thrown<GooglePlacesSearchException>(
        search.autocomplete('chợ'),
      );
      expect(e.cause, isA<GoogleRoutesTimeoutException>());
      expect(e.cause, isA<TimeoutException>());
      expect(e.statusCode, isNull);
    });

    test('a transport error is the cause', () async {
      final error = http.ClientException('offline');
      final search = GooglePlacesSearch(
        apiKey: key,
        client: MockClient((_) async => throw error),
      );
      final e = await _thrown<GooglePlacesSearchException>(
        search.autocomplete('chợ'),
      );
      expect(e.cause, same(error));
    });
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('autocomplete.json')),
            200,
          ),
        ),
      );
      final search = GooglePlacesSearch(apiKey: key, client: client);
      await search.autocomplete('chợ');
      search.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the search created', () async {
      final created = RecordingClient(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('autocomplete.json')),
            200,
          ),
        ),
      );
      final search = http.runWithClient(
        () => GooglePlacesSearch(apiKey: key),
        () => created,
      );
      await search.autocomplete('chợ');
      search.close();
      expect(created.closed, isTrue);
      search.close();
    });

    test('a closed search throws StateError', () async {
      final s = serve(fixture('autocomplete.json'));
      s.search.close();
      await expectLater(s.search.autocomplete('a'), throwsStateError);
      await expectLater(s.search.resolve(suggestion), throwsStateError);
      await expectLater(s.search.reverse(benThanh), throwsStateError);
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
