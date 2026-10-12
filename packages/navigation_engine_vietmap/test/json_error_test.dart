// A body that is not JSON must not leak any of the API key. V8's JSON.parse
// error (dart2js on node, and the web) quotes the text around the error, and
// its wording differs between node versions, so the message is fixed and the
// cause keeps only the parser's offset. Runs on the VM, and on node with
// `dart test -p node -t js` (see dart_test.yaml).
@Tags(['js'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_vietmap/navigation_engine_vietmap.dart';
import 'package:test/test.dart';

MockClient answering(String body) =>
    MockClient((_) async => http.Response.bytes(utf8.encode(body), 200));

void main() {
  test('a body that is not JSON leaks no fragment of the key', () async {
    const key = 'Zq7Xk29LmPv4RtYb8NsWc3HdJf6GaUe1';
    final fragments = [
      for (var i = 0; i + 8 <= key.length; i++) key.substring(i, i + 8),
    ];
    final bodies = [
      '$key is not JSON',
      '{"key": $key}',
      '{"a": 1, "key": "x" $key}',
      '[1, 2, $key',
    ];
    const from = GeoPoint(10.8, 106.7);
    const to = GeoPoint(10.81, 106.7);
    for (final body in bodies) {
      final errors = <Object>[];
      for (final call in <Future<Object?> Function(http.Client)>[
        (c) => VietmapRouteProvider(apiKey: key, client: c).route(from, to),
        (c) => VietmapPlaceSearch(apiKey: key, client: c).reverse(from),
      ]) {
        try {
          await call(answering(body));
          fail('expected an error');
        } on VietmapFormatException catch (e) {
          errors.add(e);
        } on VietmapSearchException catch (e) {
          errors.add(e);
        }
      }
      final format = [
        errors[0] as VietmapFormatException,
        (errors[1] as VietmapSearchException).cause! as VietmapFormatException,
      ];
      for (final e in format) {
        expect(e.message, 'invalid JSON');
        expect(e.cause, isA<FormatException>());
        expect((e.cause! as FormatException).message, 'invalid JSON');
        expect((e.cause! as FormatException).source, isNull);
      }
      final texts = [
        for (final e in errors) e.toString(),
        for (final e in format) '${e.cause}',
        for (final e in format) e.message,
      ];
      for (final text in texts) {
        for (final fragment in fragments) {
          expect(text.contains(fragment), isFalse, reason: '$body: $text');
        }
      }
    }
  });
}
