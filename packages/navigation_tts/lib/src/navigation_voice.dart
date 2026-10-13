import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'tts_engine.dart';

/// The voice for a language has no installed voice on this device.
class TtsVoiceUnavailable implements Exception {
  /// Creates the error for [language].
  const TtsVoiceUnavailable(this.language);

  /// The BCP-47 language without a voice, such as `vi-VN`.
  final String language;

  @override
  String toString() => 'TtsVoiceUnavailable: no voice for $language';
}

/// The BCP-47 language a formatter speaks: `vi-VN` for
/// [VietnameseGuidanceFormatter], else `en-US`.
///
/// A formatter for another language needs its own language: pass it as
/// `NavigationVoice(language: ...)`.
String defaultVoiceLanguage(GuidanceFormatter formatter) =>
    formatter is VietnameseGuidanceFormatter ? 'vi-VN' : 'en-US';

enum _LanguageState { unknown, ok, unavailable }

/// Speaks the guidance announcements of a navigation through a [TtsEngine].
///
/// Each announcement is spoken as `formatter.announcement(a)`, one at a
/// time, with at most one prompt waiting: a newer prompt replaces the
/// waiting one. A `now` or `arrived` prompt interrupts an `approaching`
/// prompt that is being spoken; any other prompt waits for the current one
/// to end. Until the interrupted prompt has stopped, the interrupting one
/// holds its own place ahead of the waiting slot, which only a newer `now`
/// or `arrived` takes: an `approaching` prompt arriving in the same burst
/// waits behind it.
///
/// The [AudioGuidance] mode decides what is spoken:
/// - [AudioGuidance.sound]: every prompt.
/// - [AudioGuidance.alertsOnly]: no turn-by-turn prompts. There are no
///   alerts yet, so this mode is silent for now.
/// - [AudioGuidance.muted]: nothing.
///
/// Switching to `alertsOnly` or `muted` stops the speech at once and drops
/// the waiting prompt.
///
/// Before the first prompt, the voice checks once that the device has a
/// voice for [language]. If it has none, `onError` gets a
/// [TtsVoiceUnavailable] once and nothing is ever spoken: a prompt is never
/// read with another language's voice. Engine errors also go to `onError`
/// (and are dropped when it is null); they never stop later prompts.
class NavigationVoice {
  /// Creates a voice that speaks [announcements], worded by [formatter],
  /// through [engine].
  ///
  /// [audioGuidance] is the mode to follow; when null, every prompt is
  /// spoken. [language] is the BCP-47 language of the voice; when null it
  /// is [defaultVoiceLanguage] of [formatter]. [onError] gets the errors of
  /// the engine and a [TtsVoiceUnavailable].
  NavigationVoice({
    required Stream<GuidanceAnnouncement> announcements,
    required GuidanceFormatter formatter,
    required TtsEngine engine,
    ValueListenable<AudioGuidance>? audioGuidance,
    String? language,
    void Function(Object error)? onError,
  }) : _formatter = formatter,
       _engine = engine,
       _audioGuidance = audioGuidance,
       _onError = onError,
       language = language ?? defaultVoiceLanguage(formatter) {
    _subscription = announcements.listen(_onAnnouncement, onError: _report);
    audioGuidance?.addListener(_onModeChanged);
  }

  /// Creates a voice that speaks the `announcements` of [session]; the
  /// other parameters are those of the default constructor.
  factory NavigationVoice.forSession(
    NavigationSession session, {
    required GuidanceFormatter formatter,
    required TtsEngine engine,
    ValueListenable<AudioGuidance>? audioGuidance,
    String? language,
    void Function(Object error)? onError,
  }) => NavigationVoice(
    announcements: session.announcements,
    formatter: formatter,
    engine: engine,
    audioGuidance: audioGuidance,
    language: language,
    onError: onError,
  );

  final GuidanceFormatter _formatter;
  final TtsEngine _engine;
  final ValueListenable<AudioGuidance>? _audioGuidance;
  final void Function(Object error)? _onError;
  late final StreamSubscription<GuidanceAnnouncement> _subscription;

  /// The language spoken (BCP-47, such as `vi-VN`).
  final String language;

  /// The prompt being spoken, or about to be while the language is checked.
  GuidanceAnnouncement? _speaking;

  /// Whether the voice stopped [_speaking] (an interrupt, a mute, dispose).
  bool _stopped = false;

  /// A `now` or `arrived` prompt that interrupted [_speaking] and waits for
  /// it to end; spoken before [_waiting]. Only another `now` or `arrived`
  /// replaces it.
  GuidanceAnnouncement? _interrupter;

  /// The prompt in the waiting slot.
  GuidanceAnnouncement? _waiting;

  _LanguageState _languageState = _LanguageState.unknown;
  bool _pumping = false;
  bool _disposed = false;

  bool get _sound =>
      (_audioGuidance?.value ?? AudioGuidance.sound) == AudioGuidance.sound;

  void _onAnnouncement(GuidanceAnnouncement a) {
    if (_disposed || !_sound || _languageState == _LanguageState.unavailable) {
      return;
    }
    final current = _speaking;
    final interrupts = a.kind != AnnouncementKind.approaching;
    if (interrupts && _interrupter != null) {
      _interrupter = a;
      _waiting = null;
    } else if (interrupts &&
        current != null &&
        !_stopped &&
        current.kind == AnnouncementKind.approaching) {
      _interrupter = a;
      _waiting = null;
      _stopCurrent();
    } else {
      _waiting = a;
    }
    unawaited(_pump());
  }

  void _onModeChanged() {
    if (_disposed || _sound) return;
    _interrupter = null;
    _waiting = null;
    _stopCurrent();
  }

  /// Stops the current speech; its `speak` ending is not an error.
  void _stopCurrent() {
    _stopped = true;
    unawaited(Future.sync(_engine.stop).catchError(_report));
  }

  /// Speaks the waiting prompts, one at a time, until none is left.
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_disposed && _sound) {
        final a = _interrupter ?? _waiting;
        if (a == null) break;
        if (identical(a, _interrupter)) {
          _interrupter = null;
        } else {
          _waiting = null;
        }
        _speaking = a;
        _stopped = false;
        await _speak(a);
        _speaking = null;
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _speak(GuidanceAnnouncement a) async {
    if (!await _languageReady() || _disposed || _stopped) return;
    try {
      await _engine.speak(_formatter.announcement(a), language: language);
    } on Object catch (e) {
      if (!_disposed && !_stopped) _report(e);
    }
  }

  /// Whether a voice for [language] is installed; checked once.
  Future<bool> _languageReady() async {
    switch (_languageState) {
      case _LanguageState.ok:
        return true;
      case _LanguageState.unavailable:
        return false;
      case _LanguageState.unknown:
    }
    bool available;
    Object? error;
    try {
      available = await _engine.isLanguageAvailable(language);
    } on Object catch (e) {
      available = false;
      error = e;
    }
    if (_disposed) return false;
    if (available) {
      _languageState = _LanguageState.ok;
      return true;
    }
    _languageState = _LanguageState.unavailable;
    _interrupter = null;
    _waiting = null;
    _report(error ?? TtsVoiceUnavailable(language));
    return false;
  }

  void _report(Object error) => _onError?.call(error);

  /// Stops listening and speaking: cancels the subscription to the
  /// announcements, removes the `audioGuidance` listener and stops the
  /// speech. Later prompts, mode changes and the end of the current `speak`
  /// reach no engine.
  ///
  /// It does not dispose the engine: the caller owns it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _interrupter = null;
    _waiting = null;
    _stopped = true;
    _audioGuidance?.removeListener(_onModeChanged);
    final cancelled = _subscription.cancel();
    try {
      await _engine.stop();
    } on Object catch (e) {
      _report(e);
    }
    await cancelled;
  }
}
