import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  testWidgets('a map tap is delivered after one turn of the event loop', (
    tester,
  ) async {
    final guard = MapTapGuard();
    var delivered = 0;
    guard.dispatch(() => delivered++);
    expect(delivered, 0);
    await tester.pump(Duration.zero);
    expect(delivered, 1);
  });

  testWidgets('a feature tap drops the next map tap of the same frame only', (
    tester,
  ) async {
    final guard = MapTapGuard();
    var delivered = 0;
    guard
      ..featureTapped()
      ..dispatch(() => delivered++)
      ..dispatch(() => delivered++);
    await tester.pump(Duration.zero);
    expect(delivered, 1, reason: 'the token is one-shot');
  });

  testWidgets('the token lapses at the end of the frame', (tester) async {
    final guard = MapTapGuard();
    var delivered = 0;
    guard.featureTapped();
    await tester.pump();
    guard.dispatch(() => delivered++);
    await tester.pump(Duration.zero);
    expect(delivered, 1);
  });

  testWidgets('a feature tap in the same turn drops a held map tap and '
      'leaves no token', (tester) async {
    final guard = MapTapGuard();
    var delivered = 0;
    guard
      ..dispatch(() => delivered++)
      ..featureTapped();
    await tester.pump(Duration.zero);
    expect(delivered, 0);
    guard.dispatch(() => delivered++);
    await tester.pump(Duration.zero);
    expect(delivered, 1);
  });

  testWidgets('dispose drops a held tap and later taps', (tester) async {
    final guard = MapTapGuard();
    var delivered = 0;
    guard
      ..dispatch(() => delivered++)
      ..dispose()
      ..dispatch(() => delivered++)
      ..featureTapped();
    await tester.pump(Duration.zero);
    expect(delivered, 0);
  });
}
