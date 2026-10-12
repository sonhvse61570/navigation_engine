// The API key must never reach an exception's text. Runs on the VM, and on
// node with `dart test -p node -t js` (see dart_test.yaml): the scrub's
// regular expressions and percent-encoding run under dart2js too.
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_google_routes/navigation_engine_google_routes.dart';
import 'package:test/test.dart';

/// A key whose percent-encoded form differs from the raw one.
const secret = 'AIza/k3y+chars=';
const encoded = 'AIza%2Fk3y%2Bchars%3D';

const suggestion = PlaceSuggestion(id: 'REDACTED-place-id-1', title: 'x');

const a = GeoPoint(10.77243, 106.69805);
const b = GeoPoint(10.77978, 106.69902);

MockClient answering(String body, int status, {String? reasonPhrase}) =>
    MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(body),
        status,
        reasonPhrase: reasonPhrase,
      ),
    );

/// A Google RPC error body.
String rpc(int code, String status, String message) => jsonEncode({
  'error': {'code': code, 'message': message, 'status': status},
});

/// The text of the error a route request answered with [body] throws.
Future<String> routeError(
  String body,
  int status, {
  String? reasonPhrase,
}) async {
  final p = GoogleRoutesRouteProvider(
    apiKey: secret,
    client: answering(body, status, reasonPhrase: reasonPhrase),
  );
  try {
    await p.route(a, b);
  } on GoogleRoutesException catch (e) {
    return e.toString();
  }
  fail('expected a GoogleRoutesException');
}

void expectNoKey(Iterable<String> texts) {
  for (final text in texts) {
    expect(text.contains(secret), isFalse, reason: text);
    expect(
      text.toLowerCase().contains(encoded.toLowerCase()),
      isFalse,
      reason: text,
    );
  }
}

void main() {
  test('a key the server echoes, raw or percent-encoded, is scrubbed from '
      'the body, the status, the server message and the reason '
      'phrase', () async {
    final texts = [
      // An HTTP error body without a Google error.
      await routeError('bad key $secret in GET /x?key=$encoded', 502),
      // An RPC error whose message echoes the key, with 400 and 403.
      await routeError(
        rpc(400, 'INVALID_ARGUMENT', 'API key $secret (key=$encoded)'),
        400,
      ),
      await routeError(
        rpc(403, 'PERMISSION_DENIED', 'key $secret is blocked'),
        403,
      ),
      // Lower-case percent-encoding.
      await routeError('key=aiza%2fk3y%2bchars%3d', 401),
      // The status itself.
      await routeError(rpc(429, 'X_$secret', 'm'), 429),
      // The HTTP reason phrase.
      await routeError('', 401, reasonPhrase: 'Bad key $secret'),
    ];
    expect(texts, [
      'GoogleRoutesHttpException: Google request failed with HTTP 502: bad '
          'key REDACTED in GET /x?key=REDACTED',
      'GoogleRoutesStatusException: Google INVALID_ARGUMENT: the server '
          'rejected the request (API key REDACTED (key=REDACTED)) [HTTP 400]',
      'GoogleRoutesHttpException: Google request failed with HTTP 403 (the '
          "key is missing or not allowed: check that the API is enabled for "
          "the key's project, the key's API and application restrictions, "
          'and billing): PERMISSION_DENIED: key REDACTED is blocked',
      'GoogleRoutesHttpException: Google request failed with HTTP 401 (the '
          'request is not authenticated): key=REDACTED',
      'GoogleRoutesStatusException: Google X_REDACTED: the server reported '
          'an error (m) [HTTP 429]',
      'GoogleRoutesHttpException: Google request failed with HTTP 401 Bad '
          'key REDACTED (the request is not authenticated)',
    ]);
    expectNoKey(texts);
  });

  test('the status and server message fields are scrubbed too', () async {
    final p = GoogleRoutesRouteProvider(
      apiKey: secret,
      client: answering(rpc(400, 'S$secret', 'm $encoded'), 400),
    );
    try {
      await p.route(a, b);
      fail('expected a GoogleRoutesStatusException');
    } on GoogleRoutesStatusException catch (e) {
      expect(e.status, 'SREDACTED');
      expect(e.serverMessage, 'm REDACTED');
    }
    final forbidden = GoogleRoutesRouteProvider(
      apiKey: secret,
      client: answering(rpc(403, 'S$secret', 'm $encoded'), 403),
    );
    try {
      await forbidden.route(a, b);
      fail('expected a GoogleRoutesHttpException');
    } on GoogleRoutesHttpException catch (e) {
      expect(e.status, 'SREDACTED');
      expect(e.serverMessage, 'm REDACTED');
    }
  });

  test('an empty key scrubs nothing', () async {
    final p = GoogleRoutesRouteProvider(
      apiKey: '',
      client: answering('bad request', 400),
    );
    try {
      await p.route(a, b);
      fail('expected a GoogleRoutesHttpException');
    } on GoogleRoutesHttpException catch (e) {
      expect(
        e.message,
        'Google request failed with HTTP 400 (the request is not valid): bad '
        'request',
      );
    }
  });

  test('the search scrubs the cause and the exception, on every '
      'request', () async {
    final texts = <String>[];
    for (final (body, status) in [
      ('quota exceeded for key=$encoded ($secret)', 429),
      (rpc(403, 'PERMISSION_DENIED', 'Forbidden: key $secret'), 403),
      (rpc(400, 'X$secret', 'bad $encoded'), 400),
    ]) {
      final search = GooglePlacesSearch(
        apiKey: secret,
        client: answering(body, status),
      );
      for (final call in <Future<Object?> Function()>[
        () => search.autocomplete('phở', session: PlaceSearchSession()),
        () => search.resolve(suggestion, session: PlaceSearchSession()),
        () => search.reverse(a),
      ]) {
        try {
          await call();
          fail('expected a GooglePlacesSearchException');
        } on GooglePlacesSearchException catch (e) {
          texts.add(e.toString());
        }
      }
    }
    const requests = ['autocomplete', 'place details', 'reverse geocoding'];
    expect(texts, [
      for (final request in requests)
        'GooglePlacesSearchException: Google $request failed (429); cause: '
            'GoogleRoutesHttpException: Google request failed with HTTP 429 '
            '(quota or rate limit reached): quota exceeded for key=REDACTED '
            '(REDACTED)',
      for (final request in requests)
        'GooglePlacesSearchException: Google $request failed (403); cause: '
            'GoogleRoutesHttpException: Google request failed with HTTP 403 '
            "(the key is missing or not allowed: check that the API is "
            "enabled for the key's project, the key's API and application "
            'restrictions, and billing): PERMISSION_DENIED: Forbidden: key '
            'REDACTED',
      for (final request in requests)
        'GooglePlacesSearchException: Google $request failed (400); cause: '
            'GoogleRoutesStatusException: Google XREDACTED: the server '
            'reported an error (bad REDACTED) [HTTP 400]',
    ]);
    expectNoKey(texts);
  });

  test('a Geocoding error_message that echoes the key is scrubbed', () async {
    final search = GooglePlacesSearch(
      apiKey: secret,
      client: answering(
        jsonEncode({
          'status': 'REQUEST_DENIED',
          'error_message':
              'The provided API key $secret ($encoded) is invalid.',
          'results': <Object?>[],
        }),
        200,
      ),
    );
    try {
      await search.reverse(a);
      fail('expected a GooglePlacesSearchException');
    } on GooglePlacesSearchException catch (e) {
      expect(
        e.toString(),
        'GooglePlacesSearchException: Google reverse geocoding failed (200); '
        'cause: GoogleRoutesStatusException: Google REQUEST_DENIED: the '
        'request was denied: check the key and its restrictions (The '
        'provided API key REDACTED (REDACTED) is invalid.) [HTTP 200]',
      );
    }
  });

  test('a malformed duration that holds the key is scrubbed from the '
      'format message', () async {
    final body = jsonEncode({
      'routes': [
        {
          'duration': '${secret}s',
          'polyline': {'encodedPolyline': '_p~iF~ps|U_ulLnnqC'},
        },
      ],
    });
    final texts = [
      await routeError(body, 200),
      await routeError(
        jsonEncode({
          'routes': [
            {'duration': encoded},
          ],
        }),
        200,
      ),
    ];
    expect(texts, [
      'GoogleRoutesFormatException: routes[0].duration: expected a duration '
          'such as "12.5s", got "REDACTEDs"',
      'GoogleRoutesFormatException: routes[0].duration: expected a duration '
          'such as "12.5s", got "REDACTED"',
    ]);
    expectNoKey(texts);
  });

  test('a Geocoding status that holds the key is scrubbed', () async {
    final search = GooglePlacesSearch(
      apiKey: secret,
      client: answering(
        jsonEncode({'status': 'X_$secret', 'results': <Object?>[]}),
        200,
      ),
    );
    try {
      await search.reverse(a);
      fail('expected a GooglePlacesSearchException');
    } on GooglePlacesSearchException catch (e) {
      expect(
        e.toString(),
        'GooglePlacesSearchException: Google reverse geocoding failed (200); '
        'cause: GoogleRoutesStatusException: Google X_REDACTED: the server '
        'reported an error [HTTP 200]',
      );
      expect((e.cause! as GoogleRoutesStatusException).status, 'X_REDACTED');
    }
  });

  test('a 400 INVALID_ARGUMENT for a bad key is a status exception, '
      'scrubbed', () async {
    final p = GoogleRoutesRouteProvider(
      apiKey: secret,
      client: answering(
        jsonEncode({
          'error': {
            'code': 400,
            'message':
                'API key not valid. Please pass a valid API key. '
                '($secret)',
            'status': 'INVALID_ARGUMENT',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                'reason': 'API_KEY_INVALID',
                'domain': 'googleapis.com',
              },
            ],
          },
        }),
        400,
      ),
    );
    try {
      await p.route(a, b);
      fail('expected a GoogleRoutesStatusException');
    } on GoogleRoutesStatusException catch (e) {
      expect(e.statusCode, 400);
      expect(e.status, 'INVALID_ARGUMENT');
      expect(
        e.toString(),
        'GoogleRoutesStatusException: Google INVALID_ARGUMENT: the server '
        'rejected the request (API key not valid. Please pass a valid API '
        'key. (REDACTED)) [HTTP 400]',
      );
    }
  });

  test('a body that is not JSON leaks no fragment of the key', () async {
    // V8's JSON.parse error (dart2js on node, and the web) quotes the text
    // around the error, which a whole-key scrub would not catch. The
    // message is fixed, and the cause keeps no text: neither the key nor
    // any 8 characters of it appear, on the VM or on node.
    const key = 'AIzaSyA1234567890abcdefghijklmnopqrs';
    final fragments = [
      for (var i = 0; i + 8 <= key.length; i++) key.substring(i, i + 8),
    ];
    final bodies = [
      '$key is not JSON',
      '{"key": $key}',
      '{"a": 1, "key": "x" $key}',
      '[1, 2, $key',
    ];
    for (final body in bodies) {
      final errors = <Object>[];
      for (final call in <Future<Object?> Function(http.Client)>[
        (c) => GoogleRoutesRouteProvider(apiKey: key, client: c).route(a, b),
        (c) => GooglePlacesSearch(apiKey: key, client: c).reverse(a),
        (c) => GooglePlacesSearch(apiKey: key, client: c).autocomplete('x'),
      ]) {
        try {
          await call(answering(body, 200));
          fail('expected an error');
        } on GoogleRoutesFormatException catch (e) {
          errors.add(e);
        } on GooglePlacesSearchException catch (e) {
          errors.add(e);
        }
      }
      final format = [
        errors[0] as GoogleRoutesFormatException,
        for (final e in errors.skip(1))
          (e as GooglePlacesSearchException).cause!
              as GoogleRoutesFormatException,
      ];
      for (final e in format) {
        expect(e.message, 'the answer is not a JSON object: invalid JSON');
      }
      final texts = [
        for (final e in errors) e.toString(),
        for (final e in format) '${e.cause}',
      ];
      for (final text in texts) {
        for (final fragment in fragments) {
          expect(text.contains(fragment), isFalse, reason: '$body: $text');
        }
      }
    }
  });

  group('transport errors', () {
    test('pass through, without the key in their URL', () async {
      final search = GooglePlacesSearch(
        apiKey: secret,
        client: MockClient(
          (req) async => throw http.ClientException('offline', req.url),
        ),
      );
      try {
        await search.reverse(a);
        fail('expected a GooglePlacesSearchException');
      } on GooglePlacesSearchException catch (e) {
        final cause = e.cause! as http.ClientException;
        expect(cause.message, 'offline');
        expect(cause.uri!.queryParameters['key'], 'REDACTED');
        expect(cause.uri!.queryParameters['latlng'], '10.77243,106.69805');
        expect(cause.uri!.path, '/maps/api/geocode/json');
        expectNoKey([e.toString(), cause.toString()]);
        expect(cause.toString(), contains('key=REDACTED'));
      }
    });

    test('a message that holds the key, raw or encoded, is scrubbed, in the '
        'route provider and in the search', () async {
      MockClient refusing() => MockClient(
        (_) async =>
            throw http.ClientException('refused for key=$encoded ($secret)'),
      );
      try {
        await GoogleRoutesRouteProvider(
          apiKey: secret,
          client: refusing(),
        ).route(a, b);
        fail('expected an http.ClientException');
      } on http.ClientException catch (e) {
        expect(e.message, 'refused for key=REDACTED (REDACTED)');
        expect(e.uri, isNull);
      }
      try {
        await GooglePlacesSearch(
          apiKey: secret,
          client: refusing(),
        ).autocomplete('phở');
        fail('expected a GooglePlacesSearchException');
      } on GooglePlacesSearchException catch (e) {
        expect(
          e.toString(),
          'GooglePlacesSearchException: Google autocomplete failed; cause: '
          'ClientException: refused for key=REDACTED (REDACTED)',
        );
      }
    });

    test('one without the key passes through unchanged', () async {
      final error = http.ClientException('offline');
      final p = GoogleRoutesRouteProvider(
        apiKey: secret,
        client: MockClient((_) async => throw error),
      );
      await expectLater(p.route(a, b), throwsA(same(error)));
    });
  });
}
