import 'dart:async';

import 'package:navigation_tts/navigation_tts.dart';

/// Records calls; each speak waits until the test completes it.
class FakeTtsEngine implements TtsEngine {
  // 'speak:<lang>:<text>', 'stop', 'available:<lang>', 'dispose'.
  final log = <String>[];
  final pending = <Completer<void>>[];
  bool available = true;
  Object? availableError;
  Object? speakError;

  /// Whether [stop] ends the utterances in progress at once. When false, a
  /// stopped utterance ends only when the test calls [finish], as on an
  /// engine whose stop reply arrives late.
  bool stopEndsSpeech = true;

  /// When set, [stop] ends the utterances in progress with this error
  /// instead of normally, as on an engine that reports a stopped speech as
  /// a failure.
  Object? stopError;

  /// When set, [isLanguageAvailable] stays pending until the test completes
  /// this gate, and returns its value.
  Completer<bool>? availableGate;

  @override
  Future<void> speak(String text, {required String language}) {
    log.add('speak:$language:$text');
    if (speakError != null) return Future.error(speakError!);
    final c = Completer<void>();
    pending.add(c);
    return c.future;
  }

  /// Ends the oldest utterance in progress; a no-op when none is.
  void finish() {
    if (pending.isNotEmpty) pending.removeAt(0).complete();
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    if (!stopEndsSpeech) return;
    for (final c in pending) {
      if (c.isCompleted) continue;
      if (stopError != null) {
        c.completeError(stopError!);
      } else {
        c.complete();
      }
    }
    pending.clear();
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    log.add('available:$language');
    if (availableError != null) throw availableError!;
    final gate = availableGate;
    if (gate != null) return gate.future;
    return available;
  }

  @override
  Future<void> dispose() async => log.add('dispose');
}
