import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:navigation_tts/navigation_tts.dart';

/// flutter_tts sends `setIosAudioCategory` (and the `focus` flag of `speak`)
/// only when `dart:io` says the host is iOS (Android), so on the test host
/// they are recorded here instead. [log] gets every method name in order,
/// shared with the channel mock.
class _RecordingTts extends FlutterTts {
  _RecordingTts(this.log);

  final List<String> log;
  final List<List<Object?>> iosAudioCategoryCalls = [];
  final List<({String text, bool focus})> spoken = [];

  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) async {
    log.add('setIosAudioCategory');
    iosAudioCategoryCalls.add([category, options, mode]);
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add((text: text, focus: focus));
    return super.speak(text, focus: focus);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late List<MethodCall> calls;
  late Map<String, Object?> results; // method -> result
  Completer<void>? speaking;
  Completer<void>? languageGate; // holds the next setLanguage reply
  Completer<void>? setupGate; // holds every awaitSpeakCompletion reply
  Completer<void>? stopGate; // holds the next stop reply
  late bool holdReplies; // each speak reply waits for its own gate
  late List<Completer<void>> replyGates; // one per speak call, in order
  late Set<Completer<void>> heldOnce; // the gates that held a reply already
  late List<String> log; // channel methods and recorded plugin calls, in order
  late Map<String, Object> failures; // method -> what the mock throws

  setUp(() {
    calls = [];
    results = {'speak': 1, 'setLanguage': 1, 'isLanguageAvailable': true};
    speaking = null;
    languageGate = null;
    setupGate = null;
    stopGate = null;
    heldOnce = {};
    holdReplies = false;
    replyGates = [];
    log = [];
    failures = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          log.add(call.method);
          final failure = failures[call.method];
          if (failure != null) throw failure;
          if (call.method == 'speak' && holdReplies) {
            final gate = Completer<void>();
            replyGates.add(gate);
            await gate.future;
          }
          if (call.method == 'speak' && speaking != null) {
            await speaking!.future;
          }
          final languageHold = languageGate;
          if (call.method == 'setLanguage' &&
              languageHold != null &&
              heldOnce.add(languageHold)) {
            await languageHold.future;
          }
          if (call.method == 'awaitSpeakCompletion' && setupGate != null) {
            await setupGate!.future;
          }
          final stopHold = stopGate;
          if (call.method == 'stop' &&
              stopHold != null &&
              heldOnce.add(stopHold)) {
            await stopHold.future;
          }
          return results[call.method] ?? 1;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methods() => calls.map((c) => c.method).toList();

  /// A call from the platform to Dart, such as `speak.onComplete`.
  Future<void> fromPlatform(String method, [Object? arguments]) async {
    final codec = channel.codec;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  test(
    'speak sets up once, sets the language, then speaks and waits',
    () async {
      final engine = FlutterTtsEngine();
      speaking = Completer<void>();
      var done = false;
      final f = engine
          .speak('Turn left', language: 'en-US')
          .then((_) => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      speaking!.complete();
      await f;
      expect(
        calls.map((c) => c.method),
        containsAllInOrder(['awaitSpeakCompletion', 'setLanguage', 'speak']),
      );
      expect(
        calls.where((c) => c.method == 'setLanguage').single.arguments,
        'en-US',
      );
    },
  );

  test('setup passes the rate and volume and runs only once', () async {
    final engine = FlutterTtsEngine(speechRate: 0.4, volume: 0.8);
    await engine.speak('One', language: 'en-US');
    await engine.speak('Two', language: 'en-US');
    expect(methods().where((m) => m == 'awaitSpeakCompletion'), hasLength(1));
    expect(
      calls.singleWhere((c) => c.method == 'awaitSpeakCompletion').arguments,
      true,
    );
    expect(
      calls.singleWhere((c) => c.method == 'setSpeechRate').arguments,
      0.4,
    );
    expect(calls.singleWhere((c) => c.method == 'setVolume').arguments, 0.8);
  });

  test('setup is shared by calls made while it runs', () async {
    final engine = FlutterTtsEngine();
    await Future.wait([
      engine.speak('One', language: 'en-US'),
      engine.isLanguageAvailable('en-US'),
    ]);
    expect(methods().where((m) => m == 'awaitSpeakCompletion'), hasLength(1));
  });

  test('setLanguage is called only when the language changes', () async {
    final engine = FlutterTtsEngine();
    await engine.speak('One', language: 'en-US');
    await engine.speak('Two', language: 'en-US');
    expect(methods().where((m) => m == 'setLanguage'), hasLength(1));
    await engine.speak('Ba', language: 'vi-VN');
    final languages = calls
        .where((c) => c.method == 'setLanguage')
        .map((c) => c.arguments)
        .toList();
    expect(languages, ['en-US', 'vi-VN']);
    expect(methods().where((m) => m == 'speak'), hasLength(3));
  });

  /// The `setSharedInstance` calls so far, as the argument of each.
  List<Object?> sessionCalls() => calls
      .where((c) => c.method == 'setSharedInstance')
      .map((c) => c.arguments)
      .toList();

  test('iOS setup sets the ducking category but does not activate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final tts = _RecordingTts(log);
    final engine = FlutterTtsEngine(tts: tts);
    // A language check runs the setup without any speech.
    expect(await engine.isLanguageAvailable('en-US'), isTrue);
    expect(log, contains('setIosAudioCategory'));
    expect(sessionCalls(), isEmpty);
    expect(tts.iosAudioCategoryCalls, [
      [
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      ],
    ]);
    expect(methods(), isNot(contains('setAudioAttributesForNavigation')));
  });

  group('iOS audio session', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('is activated right before each platform speak', () async {
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      await engine.speak('Turn left', language: 'en-US');
      expect(sessionCalls(), [true]);
      expect(log, containsAllInOrder(['setIosAudioCategory', 'setLanguage']));
      expect(log.sublist(log.length - 2), ['setSharedInstance', 'speak']);
      await engine.speak('Turn right', language: 'en-US');
      expect(sessionCalls(), [true, true]);
      expect(log.sublist(log.length - 2), ['setSharedInstance', 'speak']);
    });

    test('is deactivated after stop', () async {
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      await engine.speak('Turn left', language: 'en-US');
      calls.clear();
      log.clear();
      await engine.stop();
      expect(log, ['stop', 'setSharedInstance']);
      expect(sessionCalls(), [false]);
    });

    test('is deactivated after stop even before any speech', () async {
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      await engine.stop();
      expect(log, ['stop', 'setSharedInstance']);
      expect(sessionCalls(), [false]);
    });

    test('is deactivated after dispose', () async {
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      await engine.dispose();
      expect(log, ['stop', 'setSharedInstance']);
      expect(sessionCalls(), [false]);
      calls.clear();
      await engine.stop();
      await engine.dispose();
      expect(calls, isEmpty);
    });

    test(
      'a stop that ends a pending speak is followed by deactivation',
      () async {
        final engine = FlutterTtsEngine(tts: _RecordingTts(log));
        holdReplies = true; // no reply, as on iOS
        final f = engine.speak('Turn left', language: 'en-US');
        await pumpEventQueue();
        await engine.stop();
        await f;
        expect(sessionCalls(), [true, false]);
        expect(log.last, 'setSharedInstance');
      },
    );

    test('a timed-out utterance is followed by deactivation', () async {
      final engine = FlutterTtsEngine(
        tts: _RecordingTts(log),
        speechTimeout: (_) => const Duration(milliseconds: 20),
      );
      holdReplies = true; // no reply, as on iOS after a platform cancel
      await expectLater(
        engine.speak('Turn left', language: 'en-US'),
        throwsA(isA<TtsEngineException>()),
      );
      await pumpEventQueue();
      expect(sessionCalls(), [true, false]);
      expect(log.sublist(log.length - 2), ['stop', 'setSharedInstance']);
    });

    test('a timeout whose stop fails still ends the speak', () async {
      final engine = FlutterTtsEngine(
        tts: _RecordingTts(log),
        speechTimeout: (_) => const Duration(milliseconds: 20),
      );
      holdReplies = true;
      failures['setSharedInstance'] = PlatformException(code: 'busy');
      await expectLater(
        engine.speak('Turn left', language: 'en-US'),
        throwsA(isA<TtsEngineException>()),
      );
      await pumpEventQueue();
    });

    test('a failing or refused deactivation is ignored', () async {
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      results['setSharedInstance'] = 0; // the plugin could not deactivate
      await engine.stop();
      failures['setSharedInstance'] = PlatformException(code: 'busy');
      await engine.stop();
      await engine.dispose();
      expect(sessionCalls(), [false, false, false]);
    });
  });

  test('off iOS the audio session is never touched', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      calls.clear();
      final engine = FlutterTtsEngine();
      await engine.speak('Turn left', language: 'en-US');
      await engine.stop();
      await engine.dispose();
      expect(
        methods(),
        isNot(contains('setSharedInstance')),
        reason: '$platform',
      );
    }
  });

  test('Android setup asks for the navigation audio attributes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final engine = FlutterTtsEngine();
    await engine.speak('Turn left', language: 'en-US');
    expect(methods(), contains('setAudioAttributesForNavigation'));
    expect(methods(), isNot(contains('setSharedInstance')));
  });

  test('other platforms need no audio setup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final engine = FlutterTtsEngine();
    await engine.speak('Turn left', language: 'en-US');
    expect(methods(), isNot(contains('setAudioAttributesForNavigation')));
    expect(methods(), isNot(contains('setSharedInstance')));
  });

  test('a speak result of 0 throws a TtsEngineException', () async {
    results['speak'] = 0;
    final engine = FlutterTtsEngine();
    await expectLater(
      engine.speak('Turn left', language: 'en-US'),
      throwsA(isA<TtsEngineException>()),
    );
  });

  test('a setLanguage result of 0 throws and does not speak', () async {
    results['setLanguage'] = 0;
    final engine = FlutterTtsEngine();
    await expectLater(
      engine.speak('Turn left', language: 'xx-XX'),
      throwsA(isA<TtsEngineException>()),
    );
    expect(methods(), isNot(contains('speak')));
    // The language did not take, so the next call sets it again.
    results['setLanguage'] = 1;
    await engine.speak('Turn left', language: 'xx-XX');
    expect(methods().where((m) => m == 'setLanguage'), hasLength(2));
  });

  test('a PlatformException becomes a TtsEngineException with cause', () async {
    failures['speak'] = PlatformException(code: 'tts', message: 'engine died');
    final engine = FlutterTtsEngine();
    await expectLater(
      engine.speak('Turn left', language: 'en-US'),
      throwsA(
        isA<TtsEngineException>()
            // The channel re-creates the exception, so match it by content.
            .having(
              (e) => e.cause,
              'cause',
              isA<PlatformException>()
                  .having((c) => c.code, 'code', 'tts')
                  .having((c) => c.message, 'message', 'engine died'),
            )
            .having((e) => e.toString(), 'toString', contains('engine died')),
      ),
    );
  });

  test(
    'isLanguageAvailable maps true and 1 to true, false and 0 to false',
    () async {
      final engine = FlutterTtsEngine();
      for (final entry in <Object?, bool>{
        true: true,
        1: true,
        false: false,
        0: false,
      }.entries) {
        results['isLanguageAvailable'] = entry.key;
        expect(await engine.isLanguageAvailable('vi-VN'), entry.value);
      }
      expect(
        calls.where((c) => c.method == 'isLanguageAvailable').first.arguments,
        'vi-VN',
      );
    },
  );

  test('speak asks for audio focus', () async {
    final tts = _RecordingTts(log);
    final engine = FlutterTtsEngine(tts: tts);
    await engine.speak('Turn left', language: 'en-US');
    expect(tts.spoken, [(text: 'Turn left', focus: true)]);
  });

  group('one completion per utterance', () {
    test("the plugin's reply ends speak, with or without a start", () async {
      final engine = FlutterTtsEngine();
      holdReplies = true;
      var done = false;
      final f = engine.speak('Turn left', language: 'en-US').then((_) {
        done = true;
      });
      await pumpEventQueue();
      expect(done, isFalse);
      replyGates.single.complete();
      await f;
      expect(done, isTrue);
    });

    test('completion and cancel callbacks do not end a speak', () async {
      final engine = FlutterTtsEngine();
      holdReplies = true;
      var done = false;
      final f = engine.speak('Turn left', language: 'en-US').then((_) {
        done = true;
      });
      await pumpEventQueue();
      await fromPlatform('speak.onStart');
      await fromPlatform('speak.onComplete');
      await fromPlatform('speak.onCancel');
      await pumpEventQueue();
      expect(done, isFalse);
      replyGates.single.complete();
      await f;
    });

    test(
      'a cancel the platform starts itself ends it only by timeout',
      () async {
        // Known limitation: such a cancel (an iOS audio interruption, say)
        // gets no reply to the speak call.
        final engine = FlutterTtsEngine(
          speechTimeout: (_) => const Duration(milliseconds: 40),
        );
        holdReplies = true;
        final f = engine.speak('Turn left', language: 'en-US');
        final check = expectLater(f, throwsA(isA<TtsEngineException>()));
        await pumpEventQueue();
        await fromPlatform('speak.onStart');
        await fromPlatform('speak.onCancel');
        await check;
      },
    );

    test('stop ends a pending speak normally (iOS: no reply ever)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final engine = FlutterTtsEngine(tts: _RecordingTts(log));
      speaking = Completer<void>(); // never completed
      final f = engine.speak('Turn left', language: 'en-US');
      await pumpEventQueue();
      await fromPlatform('speak.onStart');
      await engine.stop();
      await f; // ended by the stop itself, before any callback
      await fromPlatform('speak.onCancel'); // what iOS sends, late
      expect(methods(), contains('stop'));
    });

    test('stop ends a pending speak normally (Android: reply 0)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final engine = FlutterTtsEngine();
      speaking = Completer<void>();
      results['speak'] = 0; // what Android replies once stopped
      final f = engine.speak('Turn left', language: 'en-US');
      await pumpEventQueue();
      await engine.stop();
      await f;
      speaking!.complete(); // the 0 arrives after the stop: ignored
      await pumpEventQueue();
    });

    test('an error callback fails speak with a TtsEngineException', () async {
      final engine = FlutterTtsEngine();
      speaking = Completer<void>();
      final f = engine.speak('Turn left', language: 'en-US');
      final check = expectLater(
        f,
        throwsA(
          isA<TtsEngineException>().having(
            (e) => e.message,
            'message',
            contains('synth failed'),
          ),
        ),
      );
      await pumpEventQueue();
      await fromPlatform('speak.onStart');
      await fromPlatform('speak.onError', 'synth failed');
      await check;
    });

    test('dispose ends a pending speak normally', () async {
      final engine = FlutterTtsEngine();
      speaking = Completer<void>();
      final f = engine.speak('Turn left', language: 'en-US');
      await pumpEventQueue();
      await engine.dispose();
      await f;
    });

    test('a speak that outlasts the timeout is stopped and fails', () async {
      final engine = FlutterTtsEngine(
        speechTimeout: (_) => const Duration(milliseconds: 20),
      );
      speaking = Completer<void>();
      await expectLater(
        engine.speak('Turn left', language: 'en-US'),
        throwsA(
          isA<TtsEngineException>().having(
            (e) => e.message,
            'message',
            'speech timed out',
          ),
        ),
      );
      expect(methods(), contains('stop'));
    });

    test('a finished speak leaves no timer behind', () async {
      final engine = FlutterTtsEngine(
        speechTimeout: (_) => const Duration(milliseconds: 20),
      );
      await engine.speak('Turn left', language: 'en-US');
      calls.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(methods(), isEmpty);
    });
  });

  group('an utterance ends only by its own reply', () {
    /// Whether [future] has finished, after the queue drains.
    Future<bool> finished(Future<void> future) async {
      var done = false;
      unawaited(
        future.then((_) => done = true, onError: (Object _) => done = true),
      );
      await pumpEventQueue();
      return done;
    }

    test('stop, then a new speak: the old cancel does not end it', () async {
      final engine = FlutterTtsEngine();
      holdReplies = true; // no reply, as on iOS
      final a = engine.speak('A', language: 'en-US');
      await pumpEventQueue();
      await fromPlatform('speak.onStart');
      await engine.stop();
      await a;
      final b = engine.speak('B', language: 'en-US');
      await pumpEventQueue();
      await fromPlatform('speak.onCancel'); // A's, arriving late
      expect(await finished(b), isFalse);
      replyGates[1].complete();
      await b;
    });

    test("a cancel during the new speak's own stop does not drop it", () async {
      final engine = FlutterTtsEngine();
      holdReplies = true;
      final a = engine.speak('A', language: 'en-US');
      await pumpEventQueue();
      await fromPlatform('speak.onStart');
      stopGate = Completer<void>();
      final b = engine.speak('B', language: 'en-US');
      await pumpEventQueue(); // B is waiting for its stop to answer
      await fromPlatform('speak.onCancel'); // A's
      stopGate!.complete();
      await a;
      expect(await finished(b), isFalse);
      expect(calls.where((c) => c.method == 'speak').map((c) => c.arguments), [
        'A',
        'B',
      ], reason: 'B is still spoken');
      replyGates[1].complete();
      await b;
    });

    test(
      'an old cancel after the new speak was sent does not end it',
      () async {
        final engine = FlutterTtsEngine();
        holdReplies = true;
        final a = engine.speak('A', language: 'en-US');
        await pumpEventQueue();
        await fromPlatform('speak.onStart');
        final b = engine.speak('B', language: 'en-US');
        await a;
        await pumpEventQueue(); // B's platform speak is out
        await fromPlatform('speak.onCancel'); // A's
        await fromPlatform('speak.onComplete'); // A's, if it had one
        expect(await finished(b), isFalse);
        replyGates[1].complete();
        await b;
      },
    );

    test(
      'an old start and cancel after the new speak was sent do not end it',
      () async {
        // The start of the stopped utterance reaches Dart late, after the
        // new speak went out, and so marks the new one started.
        final engine = FlutterTtsEngine();
        holdReplies = true;
        final a = engine.speak('A', language: 'en-US');
        await pumpEventQueue();
        final b = engine.speak('B', language: 'en-US');
        await a;
        await pumpEventQueue(); // B's platform speak is out
        await fromPlatform('speak.onStart'); // A's, late
        await fromPlatform('speak.onCancel'); // A's
        expect(await finished(b), isFalse);
        replyGates[1].complete();
        await b;
      },
    );

    test(
      'an old error before the new utterance started does not fail it',
      () async {
        final engine = FlutterTtsEngine();
        holdReplies = true;
        final a = engine.speak('A', language: 'en-US');
        await pumpEventQueue();
        await fromPlatform('speak.onStart');
        await engine.stop();
        await a;
        final b = engine.speak('B', language: 'en-US');
        await pumpEventQueue();
        await fromPlatform('speak.onError', 'A broke'); // late
        expect(await finished(b), isFalse);
        replyGates[1].complete();
        await b; // completes normally
      },
    );

    test(
      'a start that lands before the new speak was sent is not its own',
      () async {
        final engine = FlutterTtsEngine();
        holdReplies = true;
        final a = engine.speak('A', language: 'en-US');
        await pumpEventQueue();
        stopGate = Completer<void>();
        final b = engine.speak('B', language: 'en-US');
        await pumpEventQueue(); // B is waiting for its stop to answer
        await fromPlatform('speak.onStart'); // A's, late
        await fromPlatform('speak.onError', 'A broke'); // A's
        stopGate!.complete();
        await a;
        expect(await finished(b), isFalse);
        replyGates[1].complete();
        await b;
      },
    );

    test(
      'an error before the start is ignored; the timeout covers it',
      () async {
        // Known limitation: Android never replies to the speak call on an
        // error, and an error without a start is not attributed.
        final engine = FlutterTtsEngine(
          speechTimeout: (_) => const Duration(milliseconds: 40),
        );
        holdReplies = true;
        final f = engine.speak('A', language: 'en-US');
        final check = expectLater(
          f,
          throwsA(
            isA<TtsEngineException>().having(
              (e) => e.message,
              'message',
              'speech timed out',
            ),
          ),
        );
        await pumpEventQueue();
        await fromPlatform('speak.onError', 'too long');
        await check;
      },
    );
  });

  group('setup and setLanguage do not block an interruption', () {
    for (final gate in ['setup', 'setLanguage']) {
      void hold() {
        if (gate == 'setup') {
          setupGate = Completer<void>();
        } else {
          languageGate = Completer<void>();
        }
      }

      void release() {
        if (gate == 'setup') {
          setupGate!.complete();
        } else {
          languageGate!.complete();
        }
      }

      test(
        'stop ends a speak held in $gate, which then does not speak',
        () async {
          final engine = FlutterTtsEngine();
          hold();
          final f = engine.speak('Turn left', language: 'en-US');
          await pumpEventQueue();
          await engine.stop();
          await f;
          release();
          await pumpEventQueue();
          expect(methods(), isNot(contains('speak')));
        },
      );

      test(
        'dispose ends a speak held in $gate, which then does not speak',
        () async {
          final engine = FlutterTtsEngine();
          hold();
          final f = engine.speak('Turn left', language: 'en-US');
          await pumpEventQueue();
          await engine.dispose();
          await f;
          release();
          await pumpEventQueue();
          expect(methods(), isNot(contains('speak')));
        },
      );

      test('the timeout ends a speak held in $gate', () async {
        final engine = FlutterTtsEngine(
          speechTimeout: (_) => const Duration(milliseconds: 20),
        );
        hold();
        await expectLater(
          engine.speak('Turn left', language: 'en-US'),
          throwsA(
            isA<TtsEngineException>().having(
              (e) => e.message,
              'message',
              'speech timed out',
            ),
          ),
        );
        release();
        await pumpEventQueue();
        expect(methods(), isNot(contains('speak')));
      });
    }

    group('a newer speak held on the plugin\'s stop reply', () {
      late FlutterTtsEngine engine;
      late Future<void> older;
      late Future<void> newer;

      Future<void> newerHeldOnStop(FlutterTtsEngine e) async {
        speaking = Completer<void>();
        older = e.speak('A', language: 'en-US');
        await pumpEventQueue();
        stopGate = Completer<void>();
        newer = e.speak('B', language: 'en-US');
        await pumpEventQueue(); // B waits for the stop reply
      }

      test('stop ends it, and it does not speak after', () async {
        engine = FlutterTtsEngine();
        await newerHeldOnStop(engine);
        await engine.stop();
        await newer;
        stopGate!.complete();
        await older;
        await pumpEventQueue();
        expect(
          calls.where((c) => c.method == 'speak').map((c) => c.arguments),
          ['A'],
        );
      });

      test('dispose ends it', () async {
        engine = FlutterTtsEngine();
        await newerHeldOnStop(engine);
        await engine.dispose();
        await newer;
        stopGate!.complete();
        await pumpEventQueue();
        expect(
          calls.where((c) => c.method == 'speak').map((c) => c.arguments),
          ['A'],
        );
      });

      test('the timeout ends it', () async {
        engine = FlutterTtsEngine(
          speechTimeout: (text) => text == 'A'
              ? const Duration(seconds: 30)
              : const Duration(milliseconds: 20),
        );
        await newerHeldOnStop(engine);
        await expectLater(
          newer,
          throwsA(
            isA<TtsEngineException>().having(
              (e) => e.message,
              'message',
              'speech timed out',
            ),
          ),
        );
        stopGate!.complete();
        await older;
      });
    });

    test(
      'setup already in flight makes no more plugin calls after dispose',
      () async {
        final engine = FlutterTtsEngine();
        setupGate = Completer<void>();
        final f = engine.speak('Turn left', language: 'en-US');
        await pumpEventQueue();
        await engine.dispose();
        await f;
        calls.clear();
        setupGate!.complete();
        await pumpEventQueue();
        expect(calls, isEmpty);
      },
    );

    test('a newer speak supersedes one held in setup', () async {
      final engine = FlutterTtsEngine();
      setupGate = Completer<void>();
      final a = engine.speak('A', language: 'en-US');
      await pumpEventQueue();
      final b = engine.speak('B', language: 'vi-VN');
      await a; // ended normally, while the setup is still held
      setupGate!.complete();
      await b;
      expect(calls.where((c) => c.method == 'speak').map((c) => c.arguments), [
        'B',
      ]);
    });

    test(
      'a late setLanguage reply of a superseded speak is not remembered',
      () async {
        final engine = FlutterTtsEngine();
        await engine.speak('Zero', language: 'vi-VN');
        languageGate = Completer<void>(); // holds A's setLanguage(en-US)
        final a = engine.speak('A', language: 'en-US');
        await pumpEventQueue();
        final b = engine.speak('B', language: 'vi-VN'); // its reply is not held
        await a;
        await b;
        languageGate!.complete(); // A's reply lands last
        await pumpEventQueue();
        calls.clear();
        await engine.speak('C', language: 'en-US');
        expect(
          calls.where((c) => c.method == 'setLanguage').map((c) => c.arguments),
          ['en-US'],
          reason: 'the platform was left on vi-VN',
        );
      },
    );
  });

  group('one utterance at a time', () {
    test('a new speak stops the one in flight', () async {
      final engine = FlutterTtsEngine();
      speaking = Completer<void>();
      final first = engine.speak('First', language: 'en-US');
      await pumpEventQueue();
      speaking = null; // the second reply is immediate
      final second = engine.speak('Second', language: 'vi-VN');
      await first; // ended normally
      await second;
      expect(methods().where((m) => m == 'stop'), hasLength(1));
      expect(
        log.indexOf('stop'),
        lessThan(log.lastIndexOf('setLanguage')),
        reason: 'stop comes before the second utterance is set up',
      );
      expect(
        calls.where((c) => c.method == 'setLanguage').last.arguments,
        'vi-VN',
      );
    });

    test(
      'concurrent speaks: the older ends, the newer has its language',
      () async {
        final engine = FlutterTtsEngine();
        final first = engine.speak('First', language: 'en-US');
        final second = engine.speak('Second', language: 'vi-VN');
        await first;
        await second;
        final languages = calls
            .where((c) => c.method == 'setLanguage')
            .map((c) => c.arguments)
            .toList();
        expect(languages.last, 'vi-VN');
        // The older one never speaks: the newer superseded it before setup.
        final speaks = calls.where((c) => c.method == 'speak').toList();
        expect(speaks, hasLength(1));
        expect(speaks.single.arguments, 'Second');
      },
    );

    test('a language change landing mid-setLanguage is not skipped', () async {
      final engine = FlutterTtsEngine();
      await engine.speak('Zero', language: 'vi-VN');
      languageGate = Completer<void>();
      final first = engine.speak('First', language: 'en-US');
      await pumpEventQueue(); // setLanguage(en-US) is out, unanswered
      final second = engine.speak('Second', language: 'vi-VN');
      await pumpEventQueue();
      languageGate!.complete();
      languageGate = null;
      await first;
      await second;
      final languages = calls
          .where((c) => c.method == 'setLanguage')
          .map((c) => c.arguments)
          .toList();
      expect(languages, ['vi-VN', 'en-US', 'vi-VN']);
    });

    test('dispose while setLanguage is pending does not speak', () async {
      final engine = FlutterTtsEngine();
      languageGate = Completer<void>();
      final f = engine.speak('Turn left', language: 'en-US');
      await pumpEventQueue();
      await engine.dispose();
      languageGate!.complete();
      await f;
      expect(methods(), isNot(contains('speak')));
    });
  });

  test('a failed setup is retried by the next call', () async {
    failures['awaitSpeakCompletion'] = PlatformException(code: 'setup');
    final engine = FlutterTtsEngine();
    await expectLater(
      engine.speak('Turn left', language: 'en-US'),
      throwsA(isA<TtsEngineException>()),
    );
    failures.clear();
    await engine.speak('Turn left', language: 'en-US');
    expect(methods().where((m) => m == 'awaitSpeakCompletion'), hasLength(2));
    expect(methods(), contains('speak'));
  });

  test('stop and isLanguageAvailable wrap a PlatformException', () async {
    final engine = FlutterTtsEngine();
    failures['stop'] = PlatformException(code: 'tts');
    await expectLater(engine.stop(), throwsA(isA<TtsEngineException>()));
    failures['isLanguageAvailable'] = PlatformException(code: 'tts');
    await expectLater(
      engine.isLanguageAvailable('en-US'),
      throwsA(isA<TtsEngineException>()),
    );
  });

  test('dispose swallows a PlatformException from stop', () async {
    failures['stop'] = PlatformException(code: 'tts');
    await FlutterTtsEngine().dispose();
  });

  test('on Android a language without installed data is unavailable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final engine = FlutterTtsEngine();
    results['isLanguageInstalled'] = false;
    expect(await engine.isLanguageAvailable('vi-VN'), isFalse);
    expect(
      calls.singleWhere((c) => c.method == 'isLanguageInstalled').arguments,
      'vi-VN',
    );
    results['isLanguageInstalled'] = true;
    expect(await engine.isLanguageAvailable('vi-VN'), isTrue);
    results['isLanguageAvailable'] = false;
    calls.clear();
    expect(await engine.isLanguageAvailable('vi-VN'), isFalse);
    expect(methods(), isNot(contains('isLanguageInstalled')));
  });

  test('off Android isLanguageInstalled is not asked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final engine = FlutterTtsEngine(tts: _RecordingTts(log));
    expect(await engine.isLanguageAvailable('vi-VN'), isTrue);
    expect(methods(), isNot(contains('isLanguageInstalled')));
  });

  test('stop calls stop', () async {
    final engine = FlutterTtsEngine();
    await engine.stop();
    expect(methods(), ['stop']);
  });

  test('dispose stops once; later calls touch nothing', () async {
    final engine = FlutterTtsEngine();
    await engine.dispose();
    expect(methods(), ['stop']);
    calls.clear();
    await engine.speak('Turn left', language: 'en-US');
    await engine.stop();
    expect(await engine.isLanguageAvailable('en-US'), isFalse);
    await engine.dispose();
    expect(calls, isEmpty);
  });
}
