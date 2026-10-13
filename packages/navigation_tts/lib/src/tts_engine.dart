/// Speaks text. Implementations: `FlutterTtsEngine` (the device's voices);
/// a cloud voice can implement it too (see the README).
abstract class TtsEngine {
  /// Speaks [text] in [language] (BCP-47, such as `vi-VN`); completes when
  /// the speech ends or is stopped. Throws [TtsEngineException] on failure.
  ///
  /// One utterance at a time: starting a new utterance stops the current one,
  /// whose `speak` then completes normally.
  Future<void> speak(String text, {required String language});

  /// Stops the current speech at once; a no-op when silent.
  Future<void> stop();

  /// Whether a voice for [language] is installed.
  Future<bool> isLanguageAvailable(String language);

  /// Releases the engine; later calls are no-ops.
  Future<void> dispose();
}

/// A [TtsEngine] failed.
class TtsEngineException implements Exception {
  /// Creates an exception with a [message] and, optionally, the [cause].
  const TtsEngineException(this.message, {this.cause});

  /// What went wrong.
  final String message;

  /// The error that led to this one, such as a `PlatformException`.
  final Object? cause;

  @override
  String toString() => 'TtsEngineException: $message';
}
