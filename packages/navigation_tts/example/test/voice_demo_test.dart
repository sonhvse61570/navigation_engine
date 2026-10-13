import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_tts/navigation_tts.dart';
import 'package:navigation_tts_example/main.dart';

/// Records calls; never touches the flutter_tts channel.
class _FakeEngine implements TtsEngine {
  final spoken = <String>[];
  var stops = 0;
  var disposed = false;

  @override
  Future<void> speak(String text, {required String language}) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets('the Voice switch renders and toggles the voice', (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(MaterialApp(home: VoiceDemo(engine: engine)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final switchFinder = find.byType(Switch);
    expect(find.text('Voice'), findsOneWidget);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pump();
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(tester.takeException(), isNull);

    // Leave the tree: the demo disposes the voice, then the engine.
    await tester.pumpWidget(const SizedBox());
    // Cancelling the voice's subscription takes a real event-loop turn.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(engine.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
