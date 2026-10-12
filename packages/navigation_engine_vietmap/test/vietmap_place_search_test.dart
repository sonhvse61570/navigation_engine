import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_vietmap/navigation_engine_vietmap.dart';
import 'package:test/test.dart';

// Fixtures (test/fixtures), hand-written in the shape of Vietmap's v4
// documentation; none was recorded, and the reference ids are redacted:
// - autocomplete.json: autocomplete v4 (a named place, an address without a
//   name, and a ward without either), with `ref_id` and no coordinates.
// - place.json, place_named.json: place v4 for an address and a named place.
// - reverse.json, reverse_empty.json: reverse v4, an array of places.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A fake key: requests must carry it, messages must not.
const key = 'test-services-key';

/// A search whose server answers every request with [body] and [status],
/// and records the requests in [requests].
({VietmapPlaceSearch search, List<http.Request> requests}) serve(
  String body, {
  int status = 200,
  String? apiKey = key,
  Uri? baseUrl,
  Map<String, String> headers = const {},
  String? userAgent = VietmapPlaceSearch.defaultUserAgent,
}) {
  final requests = <http.Request>[];
  final search = VietmapPlaceSearch(
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
  id: 'auto:REDACTED-ref-2',
  title: '197 Trần Phú',
  subtitle: 'Phường Chợ Quán, Thành Phố Hồ Chí Minh',
);

void main() {
  group('autocomplete', () {
    test('asks autocomplete v4 with the text encoded', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete('Chợ Bến Thành');
      final req = s.requests.single;
      expect(req.method, 'GET');
      expect(req.url.host, 'maps.vietmap.vn');
      expect(req.url.path, '/api/autocomplete/v4');
      expect(req.url.queryParametersAll, {
        'apikey': [key],
        'text': ['Chợ Bến Thành'],
      });
      // UTF-8, percent-encoded; a space is %20, not +.
      expect(
        req.url.query,
        contains('text=Ch%E1%BB%A3%20B%E1%BA%BFn%20Th%C3%A0nh'),
      );
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['User-Agent'], VietmapPlaceSearch.defaultUserAgent);
    });

    test('characters that mean something in a query are encoded', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete('Hẻm 12/3 & Số 5+6 #A=B?');
      final url = s.requests.single.url;
      expect(url.queryParameters['text'], 'Hẻm 12/3 & Số 5+6 #A=B?');
      expect(url.queryParameters.keys, unorderedEquals(['apikey', 'text']));
      expect(url.fragment, isEmpty);
    });

    test('the text is trimmed', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete('  Hà Nội \n');
      expect(s.requests.single.url.queryParameters['text'], 'Hà Nội');
    });

    test('a text shorter than 2 characters asks nothing', () async {
      final s = serve(fixture('autocomplete.json'));
      expect(await s.search.autocomplete(''), isEmpty);
      expect(await s.search.autocomplete('  '), isEmpty);
      expect(await s.search.autocomplete(' ẩ '), isEmpty);
      expect(s.requests, isEmpty);
      await s.search.autocomplete('Hà');
      expect(s.requests, hasLength(1));
    });

    test('near is sent as focus, lat,lng', () async {
      final s = serve(fixture('autocomplete.json'));
      await s.search.autocomplete(
        'phở',
        near: const GeoPoint(10.758867, 106.675566),
      );
      final url = s.requests.single.url;
      expect(url.queryParameters['focus'], '10.758867,106.675566');
      expect(url.query, contains('focus=10.758867,106.675566'));
    });

    test('a near that is not finite throws before any request', () async {
      final s = serve(fixture('autocomplete.json'));
      await expectLater(
        s.search.autocomplete('phở', near: const GeoPoint(double.nan, 106.6)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test(
      'the session is not sent: Vietmap does not bill per session',
      () async {
        final s = serve(fixture('autocomplete.json'));
        final session = PlaceSearchSession();
        await s.search.autocomplete('phở', session: session);
        expect(
          s.requests.single.url.toString(),
          isNot(contains(session.token)),
        );
      },
    );

    test(
      'the suggestions: ref_id, a title and a subtitle, no position',
      () async {
        final s = serve(fixture('autocomplete.json'));
        expect(await s.search.autocomplete('ben thanh'), const [
          PlaceSuggestion(
            id: 'auto:REDACTED-ref-1',
            title: 'Chợ Bến Thành',
            subtitle: 'Lê Lợi, Phường Bến Thành, Thành Phố Hồ Chí Minh',
          ),
          PlaceSuggestion(
            id: 'auto:REDACTED-ref-2',
            title: '197 Trần Phú',
            subtitle: 'Phường Chợ Quán, Thành Phố Hồ Chí Minh',
          ),
          PlaceSuggestion(
            id: 'auto:REDACTED-ref-3',
            title: 'Phường Sài Gòn, Thành Phố Hồ Chí Minh',
          ),
        ]);
      },
    );

    test(
      'a subtitle that does not repeat the title is the whole display',
      () async {
        final s = serve(
          jsonEncode([
            {'ref_id': 'r', 'name': 'Landmark 81', 'display': 'Bình Thạnh'},
          ]),
        );
        expect(await s.search.autocomplete('landmark'), const [
          PlaceSuggestion(
            id: 'r',
            title: 'Landmark 81',
            subtitle: 'Bình Thạnh',
          ),
        ]);
      },
    );

    test('no match is an empty list', () async {
      final s = serve('[]');
      expect(await s.search.autocomplete('zzzz'), isEmpty);
    });
  });

  group('resolve', () {
    test('asks place v4 with the ref_id as it is', () async {
      final s = serve(fixture('place.json'));
      await s.search.resolve(suggestion);
      final url = s.requests.single.url;
      expect(url.path, '/api/place/v4');
      expect(url.queryParametersAll, {
        'apikey': [key],
        'refid': ['auto:REDACTED-ref-2'],
      });
    });

    test(
      'an address: its address is the name, its display the address',
      () async {
        final s = serve(fixture('place.json'));
        expect(
          await s.search.resolve(suggestion, session: PlaceSearchSession()),
          const Place(
            id: 'auto:REDACTED-ref-2',
            name: '197 Đường Trần Phú',
            address: '197 Đường Trần Phú,Phường Chợ Quán,Thành Phố Hồ Chí Minh',
            position: GeoPoint(10.759222947000069, 106.67590269100003),
          ),
        );
      },
    );

    test('a named place keeps its name', () async {
      final s = serve(fixture('place_named.json'));
      final place = await s.search.resolve(
        const PlaceSuggestion(id: 'auto:REDACTED-ref-1', title: 'Chợ'),
      );
      expect(place.name, 'Chợ Bến Thành');
      expect(
        place.address,
        'Chợ Bến Thành, Lê Lợi, Phường Bến Thành, Thành Phố Hồ Chí Minh',
      );
      expect(place.position, const GeoPoint(10.772542, 106.698021));
    });

    test('a place with no name, address or display takes the suggestion\'s '
        'title', () async {
      final s = serve(jsonEncode({'lat': 10.7, 'lng': 106.6}));
      final place = await s.search.resolve(suggestion);
      expect(place.name, '197 Trần Phú');
      expect(place.address, isNull);
    });

    test('an empty id throws before any request', () async {
      final s = serve(fixture('place.json'));
      await expectLater(
        s.search.resolve(const PlaceSuggestion(id: '', title: 'x')),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('reverse', () {
    test('asks reverse v4 with lat and lng', () async {
      final s = serve(fixture('reverse.json'));
      await s.search.reverse(const GeoPoint(10.759221, 106.675901));
      final url = s.requests.single.url;
      expect(url.path, '/api/reverse/v4');
      expect(url.queryParametersAll, {
        'apikey': [key],
        'lat': ['10.759221'],
        'lng': ['106.675901'],
      });
    });

    test('the first place found', () async {
      final s = serve(fixture('reverse.json'));
      expect(
        await s.search.reverse(const GeoPoint(10.759221, 106.675901)),
        const Place(
          id: 'geocode:REDACTED-ref-4',
          name: '197 Trần Phú, Phường Chợ Quán, Thành Phố Hồ Chí Minh',
          address: '197 Trần Phú, Phường Chợ Quán, Thành Phố Hồ Chí Minh',
          position: GeoPoint(10.759221, 106.675901),
        ),
      );
    });

    test('nothing there is null', () async {
      final s = serve(fixture('reverse_empty.json'));
      expect(await s.search.reverse(const GeoPoint(0, 0)), isNull);
    });

    test('a point that is not finite throws before any request', () async {
      final s = serve(fixture('reverse.json'));
      await expectLater(
        s.search.reverse(const GeoPoint(double.infinity, 0)),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  group('options', () {
    test('a null apiKey, a baseUrl with a path, and extra headers', () async {
      final requests = <http.Request>[];
      final bodies = {
        'autocomplete': fixture('autocomplete.json'),
        'place': fixture('place.json'),
        'reverse': fixture('reverse.json'),
      };
      final search = VietmapPlaceSearch(
        apiKey: null,
        baseUrl: Uri.parse('https://proxy.example.test/maps/vietmap'),
        headers: {'Authorization': 'Bearer app-token'},
        client: MockClient((req) async {
          requests.add(req);
          final body = bodies[req.url.pathSegments[2]]!;
          return http.Response.bytes(utf8.encode(body), 200);
        }),
      );
      expect(await search.autocomplete('phở'), hasLength(3));
      expect(
        (await search.resolve(suggestion)).position,
        const GeoPoint(10.759222947000069, 106.67590269100003),
      );
      expect(await search.reverse(const GeoPoint(10.7, 106.6)), isNotNull);
      final s = (requests: requests);
      expect(
        [for (final r in s.requests) r.url.path],
        [
          '/maps/vietmap/autocomplete/v4',
          '/maps/vietmap/place/v4',
          '/maps/vietmap/reverse/v4',
        ],
      );
      for (final r in s.requests) {
        expect(r.url.host, 'proxy.example.test');
        expect(r.url.queryParameters.containsKey('apikey'), isFalse);
        expect(r.headers['Authorization'], 'Bearer app-token');
      }
    });

    test('userAgent null sends none', () async {
      final s = serve(fixture('autocomplete.json'), userAgent: null);
      await s.search.autocomplete('phở');
      expect(s.requests.single.headers.containsKey('User-Agent'), isFalse);
    });

    test('the defaults', () {
      final search = VietmapPlaceSearch(apiKey: key);
      addTearDown(search.close);
      expect(search.baseUrl, Uri.parse('https://maps.vietmap.vn/api/'));
      expect(search.headers, isEmpty);
      expect(search.timeout, const Duration(seconds: 12));
      expect(search, isA<PlaceSearchProvider>());
    });
  });

  group('errors', () {
    test('an HTTP error throws a VietmapSearchException with the status and '
        'the typed cause', () async {
      final s = serve('Too Many Requests', status: 429);
      final e = await _thrown<VietmapSearchException>(
        s.search.autocomplete('phở'),
      );
      expect(e, isA<PlaceSearchException>());
      expect(e.statusCode, 429);
      expect(e.message, contains('autocomplete'));
      expect(
        e.cause,
        isA<VietmapHttpException>().having((c) => c.statusCode, 'status', 429),
      );
      expect(e.toString(), contains('rate limit'));
      expect(e.toString(), isNot(contains(key)));
    });

    test('a key the server echoes is scrubbed from the cause and the '
        'exception', () async {
      const secret = 'k3y/with+chars=';
      const encoded = 'k3y%2Fwith%2Bchars%3D';
      for (final (body, status) in [
        ('quota exceeded for apikey=$encoded ($secret)', 429),
        (
          jsonEncode({
            'code': 'OVER_DAILY_LIMIT',
            'messages': 'apikey=$encoded; key $secret',
          }),
          200,
        ),
        (jsonEncode({'code': 'BAD_KEY_$encoded'}), 200),
      ]) {
        final search = VietmapPlaceSearch(
          apiKey: secret,
          client: MockClient(
            (_) async => http.Response.bytes(utf8.encode(body), status),
          ),
        );
        final e = await _thrown<VietmapSearchException>(
          search.autocomplete('phở'),
        );
        final text = e.toString();
        expect(text.contains(secret), isFalse, reason: text);
        expect(text.contains(encoded), isFalse, reason: text);
        expect(text, contains('REDACTED'));
      }
    });

    test('toString names the concrete type', () async {
      final s = serve('Too Many Requests', status: 429);
      final e = await _thrown<VietmapSearchException>(
        s.search.autocomplete('phở'),
      );
      expect(
        e.toString(),
        startsWith(
          'VietmapSearchException: Vietmap autocomplete failed (429); '
          'cause: VietmapHttpException: ',
        ),
      );
    });

    test('a Vietmap code is a VietmapCodeException cause', () async {
      final s = serve(
        jsonEncode({'code': 'OVER_DAILY_LIMIT', 'messages': 'quota'}),
        status: 403,
      );
      final e = await _thrown<VietmapSearchException>(
        s.search.resolve(suggestion),
      );
      expect(e.statusCode, 403);
      expect(e.message, contains('place'));
      expect(
        e.cause,
        isA<VietmapCodeException>()
            .having((c) => c.code, 'code', 'OVER_DAILY_LIMIT')
            .having((c) => c.serverMessage, 'serverMessage', 'quota'),
      );
    });

    test('a code in an HTTP 200 answer is an error too', () async {
      final s = serve(jsonEncode({'code': 'INVALID_REQUEST'}));
      final e = await _thrown<VietmapSearchException>(
        s.search.reverse(const GeoPoint(10.7, 106.6)),
      );
      expect(e.message, contains('reverse'));
      expect(e.cause, isA<VietmapCodeException>());
    });

    test('an answer of the wrong shape names the field', () async {
      Future<void> expectField(
        Future<Object?> Function(VietmapPlaceSearch) call,
        Object body,
        String field,
      ) async {
        final s = serve(body is String ? body : jsonEncode(body));
        final e = await _thrown<VietmapSearchException>(call(s.search));
        expect(e.cause, isA<VietmapFormatException>());
        expect(
          (e.cause! as VietmapFormatException).message,
          contains(field),
          reason: '$body',
        );
      }

      Future<Object?> auto(VietmapPlaceSearch s) => s.autocomplete('phở');
      Future<Object?> place(VietmapPlaceSearch s) => s.resolve(suggestion);
      Future<Object?> rev(VietmapPlaceSearch s) =>
          s.reverse(const GeoPoint(10.7, 106.6));

      await expectField(auto, '[{', 'invalid JSON');
      await expectField(auto, {'ref_id': 'x'}, 'not a JSON array');
      await expectField(auto, [
        {'ref_id': 'a', 'display': 'A'},
        {'display': 'B'},
      ], 'autocomplete[1].ref_id');
      await expectField(auto, [
        {'ref_id': 'a', 'name': 5},
      ], 'autocomplete[0].name');
      await expectField(auto, ['x'], 'autocomplete[0]');
      await expectField(place, [1], 'not a JSON object');
      await expectField(place, {'lat': 10.7}, 'place.lng');
      await expectField(place, {'lat': 'x', 'lng': 106.6}, 'place.lat');
      await expectField(place, {
        'lat': double.maxFinite,
        'lng': 1,
      }, 'place.lat');
      await expectField(rev, {'lat': 1}, 'not a JSON array');
      await expectField(rev, [
        {'lng': 106.6},
      ], 'reverse[0].lat');
    });

    test('a timeout is a VietmapTimeoutException cause, also a '
        'TimeoutException', () async {
      final search = VietmapPlaceSearch(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
      );
      final e = await _thrown<VietmapSearchException>(
        search.autocomplete('phở'),
      );
      expect(e.statusCode, isNull);
      expect(
        e.cause,
        isA<VietmapTimeoutException>().having(
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
        final search = VietmapPlaceSearch(
          apiKey: key,
          client: MockClient(
            (req) async => throw http.ClientException('offline', req.url),
          ),
        );
        final e = await _thrown<VietmapSearchException>(
          search.reverse(const GeoPoint(10.7, 106.6)),
        );
        expect(e.cause, isA<http.ClientException>());
        final cause = e.cause! as http.ClientException;
        expect(cause.message, 'offline');
        expect(cause.uri!.queryParameters['apikey'], 'REDACTED');
        expect(cause.uri!.queryParameters['lat'], '10.700000');
        expect(e.toString(), isNot(contains(key)));
      },
    );
  });

  group('close', () {
    test('close() leaves an injected client open', () async {
      final client = RecordingClient(
        MockClient((_) async => http.Response('[]', 200)),
      );
      final search = VietmapPlaceSearch(apiKey: key, client: client);
      await search.autocomplete('phở');
      search.close();
      expect(client.closed, isFalse);
    });

    test('close() closes the client the search created', () async {
      final created = RecordingClient(
        MockClient((_) async => http.Response('[]', 200)),
      );
      final search = http.runWithClient(
        () => VietmapPlaceSearch(apiKey: key),
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
        s.search.reverse(const GeoPoint(10.7, 106.6)),
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
