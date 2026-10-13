import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// A [TtsEngine] on the device's voices, through flutter_tts.
///
/// Setup runs once, lazily, before the first [speak] or
/// [isLanguageAvailable]. [speak] completes when the platform answers its
/// speak call (the utterance has ended), or when [stop], [dispose] or a newer
/// [speak] ends it; it throws a [TtsEngineException] when the platform
/// refuses the utterance or reports an error for it, or says nothing for far
/// longer than the text can take. After [dispose] every call returns at once
/// and touches nothing.
///
/// An utterance ends only by the platform's reply to its own speak call, so a
/// late cancel or completion callback of an earlier, stopped utterance can
/// never end a newer one. The error callback has no reply to ride on, so the
/// engine counts it only for an utterance whose start callback it has seen.
///
/// [isLanguageAvailable] expects a full BCP-47 tag with the region, such as
/// `vi-VN`: on Android it also asks whether that exact locale's voice data is
/// installed (network-only voices do not count), so a bare `vi` reports
/// unavailable.
///
/// [stop] and [dispose] wait for the plugin's stop call to answer; on Android
/// that call waits for the speech engine to initialize, so during a cold
/// start they can take a while to return (a pending [speak] ends at once).
///
/// Known limitations:
/// - A cancel the platform starts on its own, such as an iOS audio
///   interruption, gets no reply to the speak call, so that utterance ends
///   only when the timeout fires.
/// - An error before the start callback (Android rejects text longer than
///   the engine's input limit that way) is not attributed to the utterance,
///   which ends by the timeout as "speech timed out".
/// - A start callback of a stopped utterance that reaches Dart after the
///   next speak was sent makes the next utterance count as started, so a
///   late error of the old one could fail it.
/// - On Android, after a speech error the audio focus (and so the ducking
///   of music) is held until a later utterance ends.
///
/// flutter_tts has no way to change these.
///
/// On iOS the engine manages the shared audio session itself, because the
/// plugin releases it only when an utterance finishes, not when one is
/// stopped. The session is activated (`setSharedInstance(true)`, which ducks
/// other audio) right before each platform speak, and deactivated
/// (`setSharedInstance(false)`) after [stop], [dispose] and a speech timeout, so that music is
/// un-ducked after a mute, an interrupt or a dispose. An utterance that ends
/// by itself is released by the plugin. This is checked against the plugin's
/// source only, not on a device; a refused deactivation (the plugin answers 0
/// while audio is still winding down) is ignored.
///
/// Use one engine per app at a time: the plugin's [FlutterTts] shares one
/// native synthesizer and one method channel, and the newest instance takes
/// over the platform callbacks.
class FlutterTtsEngine implements TtsEngine {
  /// Creates an engine.
  ///
  /// [speechRate] is on flutter_tts's scale, where 0.5 is a normal pace on
  /// iOS and Android; [volume] goes from 0.0 to 1.0. [tts] is for tests, and
  /// so is [speechTimeout], which gives how long to wait for an utterance
  /// before stopping it and failing (by default 5 seconds plus 150
  /// milliseconds per character of text, at most 60 seconds).
  FlutterTtsEngine({
    FlutterTts? tts,
    double speechRate = 0.5,
    double volume = 1.0,
    @visibleForTesting Duration Function(String text)? speechTimeout,
  }) : _tts = tts ?? FlutterTts(),
       _speechRate = speechRate,
       _volume = volume,
       _speechTimeout = speechTimeout ?? _defaultSpeechTimeout;

  static Duration _defaultSpeechTimeout(String text) =>
      Duration(milliseconds: (5000 + 150 * text.length).clamp(0, 60000));

  final FlutterTts _tts;
  final double _speechRate;
  final double _volume;
  final Duration Function(String text) _speechTimeout;

  Future<void>? _setup;
  String? _language;
  int _languageGeneration = 0;
  _Utterance? _current;
  bool _disposed = false;

  @override
  Future<void> speak(String text, {required String language}) async {
    if (_disposed) return;
    final previous = _current;
    final utterance = _current = _Utterance();
    // The timeout runs from the call, so it also covers a setup or a
    // setLanguage that never answers.
    utterance.timer = Timer(_speechTimeout(text), () {
      if (utterance.done) return;
      utterance.fail(const TtsEngineException('speech timed out'));
      unawaited(_stopPlatform().catchError((Object _) {}));
    });
    try {
      if (previous != null) {
        // One utterance at a time: the newer one wins.
        previous.complete();
        await _until(utterance, _guard(_tts.stop));
      }
      await _until(utterance, _guard(() => _prepare(utterance, language)));
      if (!utterance.done) {
        utterance.sent = true;
        _startPlatformSpeech(utterance, text);
      }
      await utterance.future;
    } finally {
      utterance.timer?.cancel();
      if (identical(_current, utterance)) _current = null;
    }
  }

  /// Waits for [work], or for [utterance] to end (stopped, superseded,
  /// disposed or timed out), whichever is first. An end by error throws.
  Future<void> _until(_Utterance utterance, Future<void> work) {
    return Future.any<void>([work, utterance.future]);
  }

  /// Setup and the language; does nothing more once [utterance] has ended.
  Future<void> _prepare(_Utterance utterance, String language) async {
    await _ensureSetup();
    if (utterance.done) return;
    if (language != _language) {
      // Unknown until the platform confirms, so a speak that comes in
      // meanwhile sets its own language.
      _language = null;
      final generation = ++_languageGeneration;
      _checked(await _tts.setLanguage(language), 'setLanguage($language)');
      // A later setLanguage decides what the platform has; this reply is old.
      if (generation == _languageGeneration) _language = language;
    }
    if (utterance.done) return;
    // Right before the speak, so that other audio is ducked only while
    // something is said (an earlier stop released the session).
    await _setIosSession(true);
  }

  // Not awaited: the utterance ends by whichever comes first of the
  // platform's reply to this call (1 when the speech ended, 0 when it was
  // refused or stopped), an error callback, a stop or the timeout. The
  // plugin's reply never comes on iOS after a stop.
  void _startPlatformSpeech(_Utterance utterance, String text) {
    // `focus` asks Android for transient audio focus with ducking; the
    // other platforms ignore it.
    _tts
        .speak(text, focus: true)
        .then<void>((result) {
          if (utterance.done) return; // a 0 after a stop means "stopped"
          if (result == 0) {
            utterance.fail(
              const TtsEngineException(
                'The text-to-speech engine refused speak.',
              ),
            );
          } else {
            utterance.complete();
          }
        })
        .catchError((Object error) {
          if (utterance.done) return;
          utterance.fail(_wrap(error));
        });
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _current?.complete();
    await _stopPlatform();
  }

  /// The plugin's stop, then the release of the iOS audio session; the end
  /// of [stop] and of a timed-out utterance.
  Future<void> _stopPlatform() async {
    await _guard(_tts.stop);
    await _setIosSession(false);
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    if (_disposed) return false;
    return _guard(() async {
      await _ensureSetup();
      final result = await _tts.isLanguageAvailable(language);
      if (!_isTrue(result)) return false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android reports a language as available when its voice data is
        // missing too; this asks whether the data is installed.
        return _isTrue(await _tts.isLanguageInstalled(language));
      }
      return true;
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _current?.complete();
    try {
      await _tts.stop();
    } on PlatformException {
      // Nothing left to release; the engine is gone either way.
    }
    await _setIosSession(false);
  }

  /// Activates ([active]) or deactivates the shared iOS audio session; does
  /// nothing elsewhere. The plugin answers 0 when it cannot (deactivating
  /// while audio is winding down), and a platform error is no reason to fail
  /// or lose a prompt: both are ignored.
  Future<void> _setIosSession(bool active) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _tts.setSharedInstance(active);
    } on PlatformException {
      // The session keeps its state; speaking works either way.
    }
  }

  _Utterance? get _started {
    final current = _current;
    return current != null && current.started ? current : null;
  }

  static bool _isTrue(Object? result) => result == true || result == 1;

  Future<void> _ensureSetup() {
    return _setup ??= _runSetup().catchError((Object error) {
      _setup = null; // let the next call try again
      throw error;
    });
  }

  Future<void> _runSetup() async {
    // Only the error callback is used: an utterance otherwise ends by the
    // reply to its own speak call, and cancel/completion callbacks may belong
    // to an earlier utterance. An error has no reply, so it is counted for an
    // utterance that has started (the platform sends a stopped utterance's
    // callbacks before the next one's start).
    _tts.setStartHandler(() {
      final current = _current;
      if (current != null && current.sent) current.started = true;
    });
    _tts.setErrorHandler((Object? message) {
      _started?.fail(
        TtsEngineException('Text-to-speech failed: $message', cause: message),
      );
    });
    // Once disposed, a setup in flight makes no further plugin calls.
    await _tts.awaitSpeakCompletion(true);
    if (_disposed) return;
    await _tts.setSpeechRate(_speechRate);
    if (_disposed) return;
    await _tts.setVolume(_volume);
    if (_disposed) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        // The session is activated per speak, not here: a language check
        // must not duck music.
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ], IosTextToSpeechAudioMode.voicePrompt);
      case TargetPlatform.android:
        await _tts.setAudioAttributesForNavigation();
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        break;
    }
  }

  void _checked(Object? result, String call) {
    if (result == 0) {
      throw TtsEngineException('The text-to-speech engine refused $call.');
    }
  }

  TtsEngineException _wrap(Object error) {
    if (error is TtsEngineException) return error;
    final message = error is PlatformException
        ? (error.message ?? error.code)
        : '$error';
    return TtsEngineException('Text-to-speech failed: $message', cause: error);
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (error) {
      throw _wrap(error);
    }
  }
}

/// One call of [FlutterTtsEngine.speak]: ends once, normally or with an error.
class _Utterance {
  _Utterance() {
    // Whoever awaits it gets the error; this keeps an error that lands while
    // nobody listens yet from being reported as unhandled.
    _completer.future.ignore();
  }

  final Completer<void> _completer = Completer<void>();
  Timer? timer;
  bool done = false;

  /// The platform speak call has been sent.
  bool sent = false;

  /// The platform reported this utterance's start.
  bool started = false;

  Future<void> get future => _completer.future;

  void complete() {
    if (done) return;
    done = true;
    timer?.cancel();
    _completer.complete();
  }

  void fail(TtsEngineException error) {
    if (done) return;
    done = true;
    timer?.cancel();
    _completer.completeError(error);
  }
}
