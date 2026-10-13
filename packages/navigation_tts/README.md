# navigation_tts

A [navigation_engine](https://pub.dev/packages/navigation_engine) voice
module: speaks turn-by-turn prompts through the device's text-to-speech,
using [flutter_tts](https://pub.dev/packages/flutter_tts).

```yaml
dependencies:
  navigation_tts: ^0.1.0
```

## Quick start

```dart
import 'package:flutter/foundation.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_tts/navigation_tts.dart';

final audio = ValueNotifier(AudioGuidance.sound);
final engine = FlutterTtsEngine();
final voice = NavigationVoice.forSession(
  session,
  formatter: VietnameseGuidanceFormatter(),
  engine: engine,
  audioGuidance: audio,
  onError: (error) => debugPrint('voice: $error'),
);

// Later: the voice first, then the engine it speaks through.
await voice.dispose();
await engine.dispose();
```

`NavigationVoice` listens to the session's `announcements`, words each one
with the formatter and speaks it. To follow another stream, use the main
constructor, `NavigationVoice(announcements: ..., formatter: ..., engine:
...)`.

`audioGuidance` is optional (without it every prompt is spoken). Any
`ValueListenable<AudioGuidance>` works: the sound button of the
`navigation_engine_flutter` Google-style screen drives one through its
`audioGuidance` / `onAudioGuidanceChanged` parameters; other UIs can use a
`ValueNotifier` of their own.

`FlutterTtsEngine` takes `speechRate` (flutter_tts's scale: 0.5 is a normal
pace) and `volume` (0.0 to 1.0).

## Modes

The `AudioGuidance` value decides what is spoken:

| Mode | Spoken |
|---|---|
| `sound` | Every prompt. |
| `alertsOnly` | No turn-by-turn prompts. There are no alerts yet, so this mode is silent for now. |
| `muted` | Nothing. |

Switching to `alertsOnly` or `muted` stops the speech at once and drops the
waiting prompt.

## Interruptions and the queue

Prompts are spoken one at a time, with at most one prompt waiting: a newer
prompt replaces the waiting one. A "now" or "arrived" prompt interrupts an
"approaching" prompt that is being spoken; any other prompt waits for the
current one to end. Nothing is ever spoken over another prompt.

## Android setup

Apps that target Android 11 or later must declare the text-to-speech service
in `android/app/src/main/AndroidManifest.xml`, or the engine cannot find the
device's voices:

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE"/>
  </intent>
</queries>
```

## Language and installing voices

The language is taken from the formatter: `vi-VN` for
`VietnameseGuidanceFormatter`, `en-US` for the others
(`defaultVoiceLanguage`). A formatter for another language needs its own:
pass `language: 'fr-FR'`, for example.

Before the first prompt the voice checks once that the device has a voice
for the language. If it has none, `onError` gets a `TtsVoiceUnavailable`
once and nothing is spoken: a prompt is never read with another language's
voice. Ask the user to install the voice:

- **Android:** Settings, then System, then Languages, then Text-to-speech
  output, with Google's speech engine and its Vietnamese voice data
  installed. Network-only voices do not count. The voices come from the
  selected speech engine, so make Google's the preferred engine (same page,
  Preferred engine): it is the one recommended for Vietnamese, and a device
  whose preferred engine has no `vi-VN` voice reports `TtsVoiceUnavailable`
  even when Google's data is installed. The path varies by manufacturer.
- **iOS:** Settings, then Accessibility, then Spoken Content, then Voices.

Other errors of the engine also go to `onError` (and are dropped when it is
null). They never stop later prompts.

## Audio

While a prompt plays, other audio (music, a podcast) is lowered, then restored
when the prompt ends: on iOS the audio session is `playback` with
`duckOthers` and `mixWithOthers`; on Android the engine uses the
navigation-guidance audio attributes and transient audio focus.

To keep speaking with the screen locked, an iOS app also needs the `audio`
background mode in `ios/Runner/Info.plist`, next to the `location` mode that
continued location updates need:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>audio</string>
</array>
```

The voice only speaks the prompts the session produces, so the location
updates must keep running too.

## Cloud voices (TODO)

No cloud engine ships yet. To add one, implement `TtsEngine`:

1. Fetch the audio for the text in the language.
2. Cache it by text and language: prompts repeat.
3. Play it, and complete `speak` when playback ends.
4. Make `stop` cut the playback off at once.
5. If latency matters, pre-fetch the prompt of the upcoming step.

Then pass it as `engine:`. `speak` should complete normally when it is
stopped or replaced by a newer call, and throw a `TtsEngineException` when
it fails.

## Known limitations

Use one `FlutterTtsEngine` per app at a time, and share it between voices.
flutter_tts's `FlutterTts` talks to one static method channel and one native
synthesizer: a second instance takes over the first one's platform callbacks
(start and error), and either one's `stop` or `speak` cuts the other's
speech.

On iOS the plugin releases the audio session (and so un-ducks music) only
when an utterance finishes, not when it is stopped. The engine therefore
activates the session right before each speak and deactivates it after
`stop`, `dispose` and a speech timeout, so that music returns after a mute, an interrupt or a
dispose. This is verified against the plugin's source only, not on a device.

The rest come from flutter_tts, which cannot change them (see
`FlutterTtsEngine`'s docs for the full list):

- A cancel the platform starts on its own, such as an iOS audio
  interruption (a phone call), and an error before the utterance starts
  (Android rejects text longer than the engine's input limit that way) both
  end by the timeout: 5 seconds plus 150 milliseconds per character, at most
  60 seconds, and `onError` gets a "speech timed out" error.
- On Android, after a speech error the audio focus (and so the ducking of
  music) is held until a later utterance ends.
- `isLanguageAvailable` needs a full tag with the region, such as `vi-VN`.
