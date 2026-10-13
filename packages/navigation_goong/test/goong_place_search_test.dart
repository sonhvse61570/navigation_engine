import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_goong/navigation_goong.dart';
import 'package:test/test.dart';

// Fixtures (test/fixtures), hand-written in the shape of Goong's v2
// documentation (help.goong.io, "REST API v2"); none was recorded, and the
// place ids are redacted:
// - autocomplete.json: autocomplete v2 (a place with a secondary text, an
//   address without one, and a ward without structured_formatting).
// - autocomplete_zero_results.json: no prediction, status ZERO_RESULTS.
// - place_detail.json: place detail v2 for the first prediction.
// - geocode.json, geocode_empty.json: geocode v2 by latlng.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A fake key: requests must carry it, messages must not.
const key = 'test-api-key';

/// A search whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({GoongPlaceSearch search, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? apiKey = key,
  Uri? baseUrl,
  Map<String, String> headers = const {},
  String? userAgent = GoongPlaceSearch.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final search = GoongPlaceSearch(
    apiKey: apiKey,
    baseUrl: baseUrl,
    headers: headers,
    userAgent: userAgent,
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

/// A search whose server answers each endpoint (the last path segment:
/// `autocomplete`, `detail`, `geocode`) with its fixture.
({GoongPlaceSearch search, List<http.Request> requests}) serveAll({
  String? apiKey = key,
  Uri? baseUrl,
  Map<String, String> headers = const {},
}) {
  final requests = <http.Request>[];
  final bodies = {
    'autocomplete': fixture('autocomplete.json'),
    'detail': fixture('place_detail.json'),
    'geocode': fixture('geocode.json'),
  };
  final search = GoongPlaceSearch(
    apiKey: apiKey,
    baseUrl: baseUrl,
    headers: headers,
    client: MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(
        utf8.encode(bodies[req.url.pathSegments.last]!),
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
  id: 'REDACTED-place-1',
  title: 'Hồ Hoàn Kiếm',
  subtitle: 'Phường Hoàn Kiếm, Thành phố Hà Nội',
);

const hoanKiem = Place(
  id: 'REDACTED-place-1',
  name: 'Hồ Hoàn Kiếm',
  address: 'Hồ Hoàn Kiếm, Phường Hoàn Kiếm, Thành phố Hà Nội',
  position: GeoPoint(21.028772, 105.852379),
);

void main() {
  group('autocomplete', () {
    test('asks autocomplete v2 with the input encoded', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete('Hồ Hoàn Kiếm');
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.scheme, 'https');
      expect(req.url.host, 'rsapi.goong.io');
      expect(req.url.path, '/v2/place/autocomplete');
      expect(req.url.queryParametersAll, {
        'input': ['Hồ Hoàn Kiếm'],
        'api_key': [key],
      });
      // UTF-8, percent-encoded; a space is %20, not +.
      expect(
        req.url.query,
        'input=H%E1%BB%93%20Ho%C3%A0n%20Ki%E1%BA%BFm&api_key=$key',
      );
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], GoongPlaceSearch.defaultUserAgent);
    });

    test('characters that mean something in a query are encoded', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete('Ngõ 12/3 & Số 5+6 #A=B?');
      final url = s.requests.single.url;
      expect(url.queryParameters['input'], 'Ngõ 12/3 & Số 5+6 #A=B?');
      expect(url.queryParameters.keys, unorderedEquals(['input', 'api_key']));
      expect(url.fragment, isEmpty);
    });

    test('the input is trimmed; an empty one asks nothing', () async {
      final s = serve(fixture('autocomplete.json'));
      expect(await s.search.autocomplete(''), isEmpty);
      expect(await s.search.autocomplete(' \n '), isEmpty);
      expect(s.requests, isEmpty);
      await s.search.autocomplete('  Hà Nội \n');
      expect(s.requests.single.url.queryParameters['input'], 'Hà Nội');
    });

    test('near is sent as location, lat,lng', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete(
        'phở',
        near: const GeoPoint(21.028772, 105.852379),
      );
      final url = s.requests.single.url;
      expect(url.queryParameters['location'], '21.028772,105.852379');
      expect(url.query, contains('&location=21.028772,105.852379&'));
    });

    test('a near that is not finite throws before any request', () async {
      final s = serve(fixture('autocomplete.json'));
      await expectLater(
        s.search.autocomplete('phở', near: const GeoPoint(double.nan, 105.8)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test("the session's token is sent as sessiontoken, the same on every "
        'call of the session', () async {
      final s = serve(fixture('autocomplete.json'));
      final session = PlaceSearchSession();
      await s.search.autocomplete('hồ', session: session);
      await s.search.autocomplete('hồ hoàn', session: session);
      await s.search.autocomplete('hồ hoàn kiếm');
      expect(
        [for (final r in s.requests) r.url.queryParameters['sessiontoken']],
        [session.token, session.token, null],
      );
      expect(
        s.requests.first.url.query,
        'input=h%E1%BB%93&sessiontoken=${session.token}&api_key=$key',
      );
    });

    test('the suggestions: place_id, the main and secondary texts, no '
        'position', () async {
      final s = serve(fixture('autocomplete.json'));
      expect(await s.search.autocomplete('hoàn kiếm'), const [
        suggestion,
        // An empty secondary_text: the rest of the description.
        PlaceSuggestion(
          id: 'REDACTED-place-2',
          title: '19 Hàng Bài',
          subtitle: 'Phường Hoàn Kiếm, Thành phố Hà Nội',
        ),
        // No structured_formatting: the description alone.
        PlaceSuggestion(
          id: 'REDACTED-place-3',
          title: 'Phường Hoàn Kiếm, Thành phố Hà Nội',
        ),
      ]);
    });

    test('a description that does not start with the main text is the '
        'subtitle', () async {
      final s = serve(
        jsonEncode({
          'predictions': [
            {
              'place_id': 'p',
              'description': 'Quận Ba Đình',
              'structured_formatting': {'main_text': 'Lăng Bác'},
            },
          ],
          'status': 'OK',
        }),
      );
      expect(await s.search.autocomplete('lăng'), const [
        PlaceSuggestion(id: 'p', title: 'Lăng Bác', subtitle: 'Quận Ba Đình'),
      ]);
    });

    test('ZERO_RESULTS, or no predictions, is an empty list', () async {
      expect(
        await serve(
          fixture('autocomplete_zero_results.json'),
        ).search.autocomplete('zzzz'),
        isEmpty,
      );
      expect(
        await serve(
          jsonEncode({'predictions': <Object?>[]}),
        ).search.autocomplete('zzzz'),
        isEmpty,
      );
    });
  });

  group('resolve', () {
    test('asks place detail v2 with the place_id', () async {
      final s = serve(fixture('place_detail.json'));
      await s.search.resolve(suggestion);
      final url = s.requests.single.url;
      expect(url.path, '/v2/place/detail');
      expect(url.queryParametersAll, {
        'place_id': ['REDACTED-place-1'],
        'api_key': [key],
      });
    });

    test('the place: its name, formatted address and location', () async {
      final s = serve(fixture('place_detail.json'));
      expect(await s.search.resolve(suggestion), hoanKiem);
    });

    test('a place without a name or address takes the suggestion\'s title '
        'and id', () async {
      final s = serve(
        jsonEncode({
          'result': {
            'geometry': {
              'location': {'lat': 21.0, 'lng': 105.8},
            },
          },
          'status': 'OK',
        }),
      );
      expect(
        await s.search.resolve(suggestion),
        const Place(
          id: 'REDACTED-place-1',
          name: 'Hồ Hoàn Kiếm',
          position: GeoPoint(21.0, 105.8),
        ),
      );
    });

    test('an empty id throws before any request', () async {
      final s = serve(fixture('place_detail.json'));
      await expectLater(
        s.search.resolve(const PlaceSuggestion(id: '', title: 'x')),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('sessions', () {
    test('autocomplete then resolve send the same token, and resolve ends '
        'the session', () async {
      final s = serveAll();
      final session = PlaceSearchSession();
      final suggestions = await s.search.autocomplete(
        'hồ hoàn kiếm',
        session: session,
      );
      expect(
        await s.search.resolve(suggestions.first, session: session),
        hoanKiem,
      );
      // The session is over: Goong would bill a reused token per request,
      // so it is not sent again.
      await s.search.autocomplete('hồ tây', session: session);
      await s.search.resolve(suggestions.first, session: session);
      // A new session has its own token.
      final next = PlaceSearchSession();
      await s.search.autocomplete('hồ tây', session: next);
      expect(
        [
          for (final r in s.requests)
            (r.url.path, r.url.queryParameters['sessiontoken']),
        ],
        [
          ('/v2/place/autocomplete', session.token),
          ('/v2/place/detail', session.token),
          ('/v2/place/autocomplete', null),
          ('/v2/place/detail', null),
          ('/v2/place/autocomplete', next.token),
        ],
      );
      expect(next.token, isNot(session.token));
    });

    test('a resolve that fails does not end the session', () async {
      var failing = true;
      final requests = <http.Request>[];
      final search = GoongPlaceSearch(
        apiKey: key,
        client: MockClient((req) async {
          requests.add(req);
          if (failing) return http.Response('Service Unavailable', 503);
          return http.Response.bytes(
            utf8.encode(fixture('place_detail.json')),
            200,
          );
        }),
      );
      final session = PlaceSearchSession();
      await expectLater(
        search.resolve(suggestion, session: session),
        throwsA(isA<GoongSearchException>()),
      );
      failing = false;
      expect(await search.resolve(suggestion, session: session), hoanKiem);
      expect(
        [for (final r in requests) r.url.queryParameters['sessiontoken']],
        [session.token, session.token],
      );
    });

    test('a session ends only for the search that resolved it', () async {
      final first = serveAll();
      final second = serveAll();
      final session = PlaceSearchSession();
      await first.search.resolve(suggestion, session: session);
      await second.search.autocomplete('hồ', session: session);
      expect(
        second.requests.single.url.queryParameters['sessiontoken'],
        session.token,
      );
    });
  });

  group('reverse', () {
    test('asks geocode v2 with latlng, and no session', () async {
      final s = serve(fixture('geocode.json'));
      await s.search.reverse(const GeoPoint(21.04663, 105.79022));
      final url = s.requests.single.url;
      expect(url.path, '/v2/geocode');
      expect(url.queryParametersAll, {
        'latlng': ['21.046630,105.790220'],
        'api_key': [key],
      });
      expect(url.query, 'latlng=21.046630,105.790220&api_key=$key');
    });

    test(
      'the first place found: its name, formatted address and location',
      () async {
        final s = serve(fixture('geocode.json'));
        expect(
          await s.search.reverse(const GeoPoint(21.04663, 105.79022)),
          const Place(
            id: 'REDACTED-place-4',
            name: '11 Trần Cung',
            address: '11 Trần Cung, Phường Nghĩa Đô, Thành phố Hà Nội',
            position: GeoPoint(21.04663, 105.79022),
          ),
        );
      },
    );

    test('a result without a name is named by its address', () async {
      final s = serve(
        jsonEncode({
          'results': [
            {
              'formatted_address': 'Phường Nghĩa Đô, Thành phố Hà Nội',
              'geometry': {
                'location': {'lat': 21.0, 'lng': 105.8},
              },
              'place_id': 'p',
              'name': '',
            },
          ],
        }),
      );
      expect(
        await s.search.reverse(const GeoPoint(21.0, 105.8)),
        const Place(
          id: 'p',
          name: 'Phường Nghĩa Đô, Thành phố Hà Nội',
          address: 'Phường Nghĩa Đô, Thành phố Hà Nội',
          position: GeoPoint(21.0, 105.8),
        ),
      );
    });

    test('nothing there, or ZERO_RESULTS, is null', () async {
      expect(
        await serve(
          fixture('geocode_empty.json'),
        ).search.reverse(const GeoPoint(0, 0)),
        isNull,
      );
      expect(
        await serve(
          jsonEncode({'results': <Object?>[], 'status': 'ZERO_RESULTS'}),
        ).search.reverse(const GeoPoint(0, 0)),
        isNull,
      );
    });

    test('a point that is not finite throws before any request', () async {
      final s = serve(fixture('geocode.json'));
      await expectLater(
        s.search.reverse(const GeoPoint(double.infinity, 0)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('options', () {
    test('a null apiKey, a baseUrl with a path, and extra headers', () async {
      final s = serveAll(
        apiKey: null,
        baseUrl: Uri.parse('https://proxy.example.test/maps/goong'),
        headers: {'Authorization': 'Bearer app-token'},
      );
      expect(await s.search.autocomplete('hồ'), hasLength(3));
      expect(await s.search.resolve(suggestion), hoanKiem);
      expect(
        (await s.search.reverse(const GeoPoint(21.04663, 105.79022)))!.id,
        'REDACTED-place-4',
      );
      expect(
        [for (final r in s.requests) r.url.path],
        [
          '/maps/goong/v2/place/autocomplete',
          '/maps/goong/v2/place/detail',
          '/maps/goong/v2/geocode',
        ],
      );
      for (final r in s.requests) {
        expect(r.url.host, 'proxy.example.test');
        expect(r.url.queryParameters.containsKey('api_key'), isFalse);
        expect(r.headers['Authorization'], 'Bearer app-token');
      }
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('autocomplete.json'), userAgent: null);
      await s.search.autocomplete('phở');
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final search = GoongPlaceSearch(apiKey: key);
      addTearDown(search.close);
      expect(search.baseUrl, Uri.parse('https://rsapi.goong.io/'));
      expect(search.baseUrl, GoongPlaceSearch.defaultBaseUrl);
      expect(search.headers, isEmpty);
      expect(search.timeout, const Duration(seconds: 12));
      expect(search, isA<PlaceSearchProvider>());
    });
  });

  group('errors', () {
    test('an HTTP error throws a GoongSearchException with the status and '
        'the typed cause', () async {
      final s = serve('Too Many Requests', status: 429);
      final e = await _thrown<GoongSearchException>(
        s.search.autocomplete('phở'),
      );
      expect(e, isA<PlaceSearchException>());
      expect(e.statusCode, 429);
      expect(e.message, 'Goong autocomplete failed');
      expect(
        e.cause,
        isA<GoongHttpException>().having((c) => c.statusCode, 'status', 429),
      );
      expect(
        e.toString(),
        'GoongSearchException: Goong autocomplete failed (429); cause: '
        'GoongHttpException: Goong request failed with HTTP 429 (rate limit '
        'reached): Too Many Requests',
      );
    });

    test('a key the server echoes is scrubbed from the cause and the '
        'exception', () async {
      const secret = 'k3y/with+chars=';
      const encoded = 'k3y%2Fwith%2Bchars%3D';
      final texts = <String>[];
      for (final (body, status) in [
        ('quota exceeded for api_key=$encoded ($secret)', 429),
        (
          jsonEncode({
            'status': 'REQUEST_DENIED',
            'error_message': 'api_key=$encoded; key $secret',
          }),
          200,
        ),
        (jsonEncode({'status': 'BAD_KEY_$encoded'}), 200),
      ]) {
        final search = GoongPlaceSearch(
          apiKey: secret,
          client: MockClient(
            (_) async => http.Response.bytes(utf8.encode(body), status),
          ),
        );
        final e = await _thrown<GoongSearchException>(
          search.autocomplete('phở'),
        );
        texts.add(e.toString());
      }
      expect(texts, [
        'GoongSearchException: Goong autocomplete failed (429); cause: '
            'GoongHttpException: Goong request failed with HTTP 429 (rate '
            'limit reached): quota exceeded for api_key=REDACTED (REDACTED)',
        'GoongSearchException: Goong autocomplete failed (200); cause: '
            'GoongCodeException: Goong REQUEST_DENIED: the request was denied '
            '(check the key and its restrictions) (api_key=REDACTED; key '
            'REDACTED) [HTTP 200]',
        'GoongSearchException: Goong autocomplete failed (200); cause: '
            'GoongCodeException: Goong BAD_KEY_REDACTED: the server reported '
            'an error [HTTP 200]',
      ]);
      for (final text in texts) {
        expect(text.contains(secret), isFalse, reason: text);
        expect(text.contains(encoded), isFalse, reason: text);
      }
    });

    test('a Goong status is a GoongCodeException cause', () async {
      final s = serve(
        jsonEncode({'status': 'NOT_FOUND', 'error_message': 'no such place'}),
      );
      final e = await _thrown<GoongSearchException>(
        s.search.resolve(suggestion),
      );
      expect(e.statusCode, 200);
      expect(e.message, 'Goong place detail failed');
      expect(
        e.cause,
        isA<GoongCodeException>()
            .having((c) => c.code, 'code', 'NOT_FOUND')
            .having((c) => c.serverMessage, 'serverMessage', 'no such place'),
      );
    });

    test(
      'ZERO_RESULTS from place detail is an error: there is no place',
      () async {
        final s = serve(jsonEncode({'status': 'ZERO_RESULTS'}));
        final e = await _thrown<GoongSearchException>(
          s.search.resolve(suggestion),
        );
        expect(
          e.cause,
          isA<GoongCodeException>().having(
            (c) => c.code,
            'code',
            'ZERO_RESULTS',
          ),
        );
      },
    );

    test('the error-object shape on reverse', () async {
      final s = serve(
        jsonEncode({
          'error': {'code': 'API_KEY_MISSING', 'message': 'no key'},
        }),
        status: 403,
      );
      final e = await _thrown<GoongSearchException>(
        s.search.reverse(const GeoPoint(21.0, 105.8)),
      );
      expect(e.statusCode, 403);
      expect(e.message, 'Goong geocode failed');
      expect(
        e.cause,
        isA<GoongCodeException>().having(
          (c) => c.code,
          'code',
          'API_KEY_MISSING',
        ),
      );
    });

    test('an answer of the wrong shape names the field', () async {
      Future<void> expectField(
        Future<Object?> Function(GoongPlaceSearch) call,
        Object body,
        String field,
      ) async {
        final s = serve(body is String ? body : jsonEncode(body));
        final e = await _thrown<GoongSearchException>(call(s.search));
        expect(e.cause, isA<GoongFormatException>(), reason: '$body');
        expect(
          (e.cause! as GoongFormatException).message,
          contains(field),
          reason: '$body',
        );
      }

      Future<Object?> auto(GoongPlaceSearch s) => s.autocomplete('phở');
      Future<Object?> place(GoongPlaceSearch s) => s.resolve(suggestion);
      Future<Object?> rev(GoongPlaceSearch s) =>
          s.reverse(const GeoPoint(21.0, 105.8));

      await expectField(auto, '[{', 'invalid JSON');
      await expectField(auto, [1], 'the answer is not a JSON object');
      await expectField(auto, {
        'status': 'OK',
      }, 'predictions: expected an array');
      await expectField(auto, {
        'predictions': [
          {'place_id': 'a', 'description': 'A'},
          {'description': 'B'},
        ],
      }, 'predictions[1].place_id');
      await expectField(auto, {
        'predictions': [
          {'place_id': 'a', 'description': 5},
        ],
      }, 'predictions[0].description');
      await expectField(auto, {
        'predictions': [
          {'place_id': 'a', 'structured_formatting': 'x'},
        ],
      }, 'predictions[0].structured_formatting');
      await expectField(auto, {
        'predictions': ['x'],
      }, 'predictions[0]');
      await expectField(place, {'status': 'OK'}, 'result: expected an object');
      await expectField(place, {
        'result': {'geometry': <String, Object?>{}},
      }, 'result.geometry.location');
      await expectField(place, {
        'result': {
          'geometry': {
            'location': {'lat': 'x', 'lng': 105.8},
          },
        },
      }, 'result.geometry.location.lat');
      await expectField(place, {
        'result': {
          'geometry': {
            'location': {'lat': 21.0, 'lng': 200.0},
          },
        },
      }, 'result.geometry.location.lng: out of range');
      await expectField(rev, {'status': 'OK'}, 'results: expected an array');
      await expectField(rev, {
        'results': [
          {
            'geometry': {
              'location': {'lng': 105.8},
            },
          },
        ],
      }, 'results[0].geometry.location.lat');
    });

    test('a timeout is a GoongTimeoutException cause, also a '
        'TimeoutException', () async {
      final search = GoongPlaceSearch(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
      );
      final e = await _thrown<GoongSearchException>(search.autocomplete('phở'));
      expect(e.statusCode, isNull);
      expect(
        e.cause,
        isA<GoongTimeoutException>().having(
          (c) => c.timeout,
          'timeout',
          const Duration(milliseconds: 50),
        ),
      );
      expect(e.cause, isA<TimeoutException>());
    });

    test(
      'a transport error is the cause, without the key in its URL',
      () async {
        final search = GoongPlaceSearch(
          apiKey: key,
          client: MockClient(
            (req) async => throw http.ClientException('offline', req.url),
          ),
        );
        final e = await _thrown<GoongSearchException>(
          search.reverse(const GeoPoint(21.0, 105.8)),
        );
        expect(e.cause, isA<http.ClientException>());
        final cause = e.cause! as http.ClientException;
        expect(cause.message, 'offline');
        expect(cause.uri!.queryParameters['api_key'], 'REDACTED');
        expect(cause.uri!.queryParameters['latlng'], '21.000000,105.800000');
        expect(e.toString().contains(key), isFalse, reason: e.toString());
        expect(e.toString(), contains('api_key=REDACTED'));
      },
    );
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient((_) async => http.Response('{"predictions":[]}', 200)),
      );
      final search = GoongPlaceSearch(apiKey: key, client: client);
      await search.autocomplete('phở');
      search.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the search created', () async {
      final created = RecordingClient(
        MockClient((_) async => http.Response('{"predictions":[]}', 200)),
      );
      final search = http.runWithClient(
        () => GoongPlaceSearch(apiKey: key),
        () => created,
      );
      await search.autocomplete('phở');
      search.close();
      expect(created.closed, isTrue);
      search.close();
    });

    test('a closed search throws StateError', () async {
      final s = serve(fixture('autocomplete.json'));
      s.search.close();
      await expectLater(s.search.autocomplete('phở'), throwsStateError);
      await expectLater(s.search.resolve(suggestion), throwsStateError);
      await expectLater(
        s.search.reverse(const GeoPoint(21.0, 105.8)),
        throwsStateError,
      );
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
