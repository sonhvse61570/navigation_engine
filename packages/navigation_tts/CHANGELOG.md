## 0.1.0

- Initial release.
- `TtsEngine`, the interface that speaks text, and `TtsEngineException`,
  which it throws on failure.
- `FlutterTtsEngine`, a `TtsEngine` on the device's voices through
  flutter_tts. It sets up once, lazily: `speak` completes when the
  utterance ends; on iOS the audio session is `playback` with
  `duckOthers` and `mixWithOthers`, activated per speak and released after
  `stop` and `dispose`, on Android the navigation-guidance
  audio attributes, with transient audio focus per utterance.
- `NavigationVoice`, which speaks a navigation's guidance announcements
  through a `TtsEngine`, worded by a `GuidanceFormatter`:
  `NavigationVoice.forSession(session, ...)` or the main constructor over an
  announcements stream. One prompt at a time with one waiting; a "now" or
  "arrived" prompt interrupts an "approaching" one.
- It follows an `AudioGuidance` `ValueListenable`: `sound` speaks, `muted`
  and `alertsOnly` (silent until alerts exist) stop the speech.
- `TtsVoiceUnavailable`, reported to `onError` once when the device has no
  voice for the language, and `defaultVoiceLanguage` (`vi-VN` for
  `VietnameseGuidanceFormatter`, else `en-US`).
- An example, and a README on languages, voices, audio, the known
  limitations and writing a cloud engine.
