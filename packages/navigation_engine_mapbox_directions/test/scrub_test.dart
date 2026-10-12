// The access token must never reach an exception's text. Runs on the VM,
// and on node with `dart test -p node -t js` (see dart_test.yaml): the
// scrub's regular expressions and percent-encoding run under dart2js too.
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_mapbox_directions/navigation_engine_mapbox_directions.dart';
import 'package:test/test.dart';

/// A token whose percent-encoded form differs from the raw one.
const secret = 'pk.k3y/with+chars=';
const encoded = 'pk.k3y%2Fwith%2Bchars%3D';

/// True under dart2js (the `node` platform), where ints are doubles.
final bool compiledToJs = identical(0, 0.0);

const suggestion = PlaceSuggestion(id: 'REDACTED-mapbox-id-1', title: 'x');

const a = GeoPoint(21.028772, 105.852379);
const b = GeoPoint(21.04, 105.844);

MockClient answering(String body, int status, {String? reasonPhrase}) =>
    MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(body),
        status,
        reasonPhrase: reasonPhrase,
      ),
    );

/// The text of the error a route request answered with [body] throws.
Future<String> routeError(
  String body,
  int status, {
  String? reasonPhrase,
}) async {
  final p = MapboxDirectionsRouteProvider(
    accessToken: secret,
    client: answering(body, status, reasonPhrase: reasonPhrase),
  );
  try {
    await p.route(a, b);
  } on MapboxDirectionsException catch (e) {
    return e.toString();
  }
  fail('expected a MapboxDirectionsException');
}

void expectNoToken(Iterable<String> texts) {
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
  test('a token the server echoes, raw or percent-encoded, is scrubbed from '
      'the body, the code, the server message and the reason phrase', () async {
    final texts = [
      // An HTTP error body.
      await routeError(
        'invalid access_token $secret in GET /directions/v5?access_token='
        '$encoded',
        401,
      ),
      // A code whose message echoes the token, with 200 and 422.
      await routeError(
        jsonEncode({
          'code': 'NoRoute',
          'message': 'access_token=$encoded; token $secret',
        }),
        200,
      ),
      await routeError(
        jsonEncode({
          'code': 'InvalidInput',
          'message': 'bad access_token $secret',
        }),
        422,
      ),
      // Lower-case percent-encoding.
      await routeError('access_token=pk.k3y%2fwith%2bchars%3d', 403),
      // The code itself, with 200 and with an HTTP error.
      await routeError(jsonEncode({'code': 'Bad_$secret'}), 200),
      await routeError(jsonEncode({'code': 'token $encoded'}), 400),
      // The HTTP reason phrase.
      await routeError('', 401, reasonPhrase: 'Bad token $secret'),
    ];
    expect(texts, [
      'MapboxDirectionsHttpException: Mapbox request failed with HTTP 401 '
          '(the access token is missing or not valid): invalid access_token '
          'REDACTED in GET /directions/v5?access_token=REDACTED',
      'MapboxDirectionsCodeException: Mapbox NoRoute: no route between the '
          'points (access_token=REDACTED; token REDACTED) [HTTP 200]',
      'MapboxDirectionsCodeException: Mapbox InvalidInput: the server '
          'rejected the request (bad access_token REDACTED) [HTTP 422]',
      'MapboxDirectionsHttpException: Mapbox request failed with HTTP 403 '
          '(the token is not allowed: check its URL restrictions and the '
          'account): access_token=REDACTED',
      'MapboxDirectionsCodeException: Mapbox Bad_REDACTED: the server '
          'reported an error [HTTP 200]',
      'MapboxDirectionsCodeException: Mapbox token REDACTED: the server '
          'reported an error [HTTP 400]',
      'MapboxDirectionsHttpException: Mapbox request failed with HTTP 401 '
          'Bad token REDACTED (the access token is missing or not valid)',
    ]);
    expectNoToken(texts);
  });

  test('the code and server message fields are scrubbed too', () async {
    final p = MapboxDirectionsRouteProvider(
      accessToken: secret,
      client: answering(
        jsonEncode({'code': 'X$secret', 'message': 'm $encoded'}),
        200,
      ),
    );
    try {
      await p.route(a, b);
      fail('expected a MapboxDirectionsCodeException');
    } on MapboxDirectionsCodeException catch (e) {
      expect(e.code, 'XREDACTED');
      expect(e.serverMessage, 'm REDACTED');
    }
  });

  test('an empty token scrubs nothing', () async {
    final p = MapboxDirectionsRouteProvider(
      accessToken: '',
      client: answering('bad request', 400),
    );
    try {
      await p.route(a, b);
      fail('expected a MapboxDirectionsHttpException');
    } on MapboxDirectionsHttpException catch (e) {
      expect(e.message, 'Mapbox request failed with HTTP 400: bad request');
    }
  });

  test('the search scrubs the cause and the exception, on every '
      'request', () async {
    final texts = <String>[];
    for (final (body, status) in [
      ('quota exceeded for access_token=$encoded ($secret)', 429),
      (jsonEncode({'message': 'Forbidden: token $secret'}), 403),
      (jsonEncode({'code': 'X$secret', 'message': 'bad $encoded'}), 400),
    ]) {
      final search = MapboxSearch(
        accessToken: secret,
        client: answering(body, status),
      );
      for (final call in <Future<Object?> Function()>[
        () => search.autocomplete('phở'),
        () => search.resolve(suggestion),
        () => search.reverse(a),
      ]) {
        try {
          await call();
          fail('expected a MapboxSearchException');
        } on MapboxSearchException catch (e) {
          texts.add(e.toString());
        }
      }
    }
    expect(texts, [
      for (final request in ['suggest', 'retrieve', 'reverse'])
        'MapboxSearchException: Mapbox $request failed (429); cause: '
            'MapboxDirectionsHttpException: Mapbox request failed with HTTP '
            '429 (rate limit reached): quota exceeded for '
            'access_token=REDACTED (REDACTED)',
      for (final request in ['suggest', 'retrieve', 'reverse'])
        'MapboxSearchException: Mapbox $request failed (403); cause: '
            'MapboxDirectionsHttpException: Mapbox request failed with HTTP '
            '403 (the token is not allowed: check its URL restrictions and '
            'the account): {"message":"Forbidden: token REDACTED"}',
      for (final request in ['suggest', 'retrieve', 'reverse'])
        'MapboxSearchException: Mapbox $request failed (400); cause: '
            'MapboxDirectionsCodeException: Mapbox XREDACTED: the server '
            'reported an error (bad REDACTED) [HTTP 400]',
    ]);
    expectNoToken(texts);
  });

  test('a 401 or 403 is the HTTP exception even with a code, its body '
      'scrubbed', () async {
    final texts = [
      await routeError(
        jsonEncode({
          'message': 'Not Authorized - Invalid Token $secret',
          'code': 'InvalidToken',
        }),
        401,
      ),
      await routeError(
        jsonEncode({'message': 'Forbidden', 'code': 'Forbidden_$encoded'}),
        403,
      ),
    ];
    expect(texts, [
      'MapboxDirectionsHttpException: Mapbox request failed with HTTP 401 '
          '(the access token is missing or not valid): {"message":"Not '
          'Authorized - Invalid Token REDACTED","code":"InvalidToken"}',
      'MapboxDirectionsHttpException: Mapbox request failed with HTTP 403 '
          '(the token is not allowed: check its URL restrictions and the '
          'account): {"message":"Forbidden","code":"Forbidden_REDACTED"}',
    ]);
    expectNoToken(texts);
  });

  test('a body that is not JSON leaks no fragment of the token', () async {
    // V8's JSON.parse error (dart2js on node, and the web) quotes the text
    // around the error, which a whole-token scrub would not catch, and its
    // wording differs between node versions. The message is fixed, and the
    // cause keeps no text: neither the token nor any 8 characters of it
    // appear, on the VM or on node.
    const token = 'pk.eyJ1IjoiZXhhbXBsZSIsImEiOiJ0ZXN0In0';
    final fragments = [
      for (var i = 0; i + 8 <= token.length; i++) token.substring(i, i + 8),
    ];
    final bodies = [
      '$token is not JSON',
      '{"token": $token}',
      '{"a": 1, "token": "x" $token}',
      '[1, 2, $token',
    ];
    for (final body in bodies) {
      final errors = <Object>[];
      for (final call in <Future<Object?> Function(http.Client)>[
        (c) => MapboxDirectionsRouteProvider(
          accessToken: token,
          client: c,
        ).route(a, b),
        (c) => MapboxSearch(accessToken: token, client: c).reverse(a),
      ]) {
        try {
          await call(answering(body, 200));
          fail('expected an error');
        } on MapboxDirectionsFormatException catch (e) {
          errors.add(e);
        } on MapboxSearchException catch (e) {
          errors.add(e);
        }
      }
      final format = [
        errors[0] as MapboxDirectionsFormatException,
        (errors[1] as MapboxSearchException).cause!
            as MapboxDirectionsFormatException,
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
    test('pass through, without the token in their URL', () async {
      final p = MapboxDirectionsRouteProvider(
        accessToken: secret,
        client: MockClient(
          (req) async => throw http.ClientException('offline', req.url),
        ),
      );
      try {
        await p.route(a, b);
        fail('expected an http.ClientException');
      } on http.ClientException catch (e) {
        expect(e.message, 'offline');
        expect(e.uri!.queryParameters['access_token'], 'REDACTED');
        expect(e.uri!.queryParameters['steps'], 'true');
        expect(
          e.uri!.path,
          '/directions/v5/mapbox/driving-traffic/'
          '105.852379,21.028772;105.844,21.04',
        );
        expectNoToken([e.toString()]);
        expect(e.toString(), contains('access_token=REDACTED'));
      }
    });

    test('a message that holds the token, raw or encoded, is scrubbed, in '
        'the route provider and in the search', () async {
      MockClient refusing() => MockClient(
        (_) async => throw http.ClientException(
          'refused for access_token=$encoded ($secret)',
        ),
      );
      try {
        await MapboxDirectionsRouteProvider(
          accessToken: secret,
          client: refusing(),
        ).route(a, b);
        fail('expected an http.ClientException');
      } on http.ClientException catch (e) {
        expect(e.message, 'refused for access_token=REDACTED (REDACTED)');
        expect(e.uri, isNull);
      }
      try {
        await MapboxSearch(
          accessToken: secret,
          client: refusing(),
        ).autocomplete('phở');
        fail('expected a MapboxSearchException');
      } on MapboxSearchException catch (e) {
        expect(
          e.toString(),
          'MapboxSearchException: Mapbox suggest failed; cause: '
          'ClientException: refused for access_token=REDACTED (REDACTED)',
        );
      }
    });

    test('one without the token passes through unchanged', () async {
      final error = http.ClientException('offline');
      final p = MapboxDirectionsRouteProvider(
        accessToken: secret,
        client: MockClient((_) async => throw error),
      );
      await expectLater(p.route(a, b), throwsA(same(error)));
    });
  });
}
