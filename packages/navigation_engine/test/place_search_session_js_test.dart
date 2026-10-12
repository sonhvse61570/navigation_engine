// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml): under dart2js on node, `Random.secure()` throws a plain
// JavaScript error rather than an `UnsupportedError`, and a session must
// still get a token.
@Tags(['js'])
library;

import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('a session gets a version-4 UUID token on every platform', () {
    final tokens = [for (var i = 0; i < 100; i++) PlaceSearchSession().token];
    for (final token in tokens) {
      expect(token, matches(uuid));
    }
    expect(tokens.toSet(), hasLength(100));
  });
}
