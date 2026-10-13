import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_tts/navigation_tts.dart';

import 'fake_tts_engine.dart';

GuidanceAnnouncement ann(AnnouncementKind kind, int step) =>
    GuidanceAnnouncement(
      stepIndex: step,
      step: sampleRoute.steps[step],
      kind: kind,
      threshold: kind == AnnouncementKind.approaching ? 200 : 0,
      distance: kind == AnnouncementKind.approaching ? 200 : 0,
    );

/// A fix source the test feeds by hand, as in the core session tests.
class _FakeFixSource implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  var _running = false;

  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void dispose() {}

  void add(NavFix fix) => _controller.add(fix);
}

void main() {
  const formatter = EnglishGuidanceFormatter();
  late StreamController<GuidanceAnnouncement> prompts;
  late FakeTtsEngine engine;
  late List<Object> errors;
  late ValueNotifier<AudioGuidance> mode;
  late NavigationVoice voice;

  setUp(() {
    prompts = StreamController.broadcast();
    engine = FakeTtsEngine();
    errors = [];
    mode = ValueNotifier(AudioGuidance.sound);
    voice = NavigationVoice(
      announcements: prompts.stream,
      formatter: formatter,
      engine: engine,
      audioGuidance: mode,
      onError: errors.add,
    );
  });
  tearDown(() => voice.dispose());

  String said(GuidanceAnnouncement a) =>
      'speak:en-US:${formatter.announcement(a)}';
  Iterable<String> speaks() => engine.log.where((l) => l.startsWith('speak'));

  test(
    'speaks a prompt with the formatter text, after one language check',
    () async {
      final a = ann(AnnouncementKind.approaching, 1);
      prompts.add(a);
      await pumpEventQueue();
      expect(engine.log, ['available:en-US', said(a)]);
    },
  );

  test('keeps one waiting prompt; the newest wins', () async {
    final first = ann(AnnouncementKind.approaching, 1);
    final second = ann(AnnouncementKind.approaching, 2);
    final third = ann(AnnouncementKind.approaching, 3);
    prompts
      ..add(first)
      ..add(second)
      ..add(third);
    await pumpEventQueue();
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.where((l) => l.startsWith('speak')), [
      said(first),
      said(third),
    ]);
  });

  test('now interrupts approaching', () async {
    final far = ann(AnnouncementKind.approaching, 1);
    final now = ann(AnnouncementKind.now, 1);
    prompts.add(far);
    await pumpEventQueue();
    prompts.add(now);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(now)]);
  });

  for (final lateStop in [false, true]) {
    final how = lateStop ? 'a late stop reply' : 'an immediate stop';
    // With a late stop reply, the stopped utterance is still in progress
    // when the rest of the burst arrives; the test then ends it by hand.
    Future<void> endStopped() async {
      if (!lateStop) return;
      engine.finish();
      await pumpEventQueue();
    }

    test('an interrupting now keeps its place ahead of a later approaching '
        'in the same burst ($how)', () async {
      engine.stopEndsSpeech = !lateStop;
      final far = ann(AnnouncementKind.approaching, 1);
      final now = ann(AnnouncementKind.now, 1);
      final next = ann(AnnouncementKind.approaching, 2);
      prompts.add(far);
      await pumpEventQueue();
      prompts
        ..add(now)
        ..add(next);
      await pumpEventQueue();
      await endStopped();
      expect(engine.log.sublist(1), [said(far), 'stop', said(now)]);
      engine.finish();
      await pumpEventQueue();
      expect(engine.log.sublist(1), [said(far), 'stop', said(now), said(next)]);
    });

    test('behind an interrupting now, the newest approaching wins '
        '($how)', () async {
      engine.stopEndsSpeech = !lateStop;
      final far = ann(AnnouncementKind.approaching, 1);
      final now = ann(AnnouncementKind.now, 1);
      final second = ann(AnnouncementKind.approaching, 2);
      final third = ann(AnnouncementKind.approaching, 3);
      prompts.add(far);
      await pumpEventQueue();
      prompts
        ..add(now)
        ..add(second)
        ..add(third);
      await pumpEventQueue();
      await endStopped();
      expect(engine.log.sublist(1), [said(far), 'stop', said(now)]);
      engine.finish();
      await pumpEventQueue();
      expect(engine.log.sublist(1), [
        said(far),
        'stop',
        said(now),
        said(third),
      ]);
    });
  }

  test('arrived replaces a pending interrupting now', () async {
    engine.stopEndsSpeech = false;
    final last = sampleRoute.steps.length - 1;
    final far = ann(AnnouncementKind.approaching, 1);
    final now = ann(AnnouncementKind.now, 1);
    final arrived = ann(AnnouncementKind.arrived, last);
    prompts.add(far);
    await pumpEventQueue();
    prompts.add(now);
    await pumpEventQueue();
    prompts.add(arrived);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop']);
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(arrived)]);
  });

  test(
    'a mute clears a pending interrupting now and the waiting prompt',
    () async {
      engine.stopEndsSpeech = false;
      prompts.add(ann(AnnouncementKind.approaching, 1));
      await pumpEventQueue();
      prompts
        ..add(ann(AnnouncementKind.now, 1))
        ..add(ann(AnnouncementKind.approaching, 2));
      await pumpEventQueue();
      mode.value = AudioGuidance.muted;
      mode.value = AudioGuidance.sound;
      engine.finish();
      await pumpEventQueue();
      expect(speaks(), hasLength(1));
    },
  );

  test('an interrupt clears the waiting slot', () async {
    final first = ann(AnnouncementKind.approaching, 1);
    final second = ann(AnnouncementKind.approaching, 2);
    final now = ann(AnnouncementKind.now, 1);
    prompts
      ..add(first)
      ..add(second);
    await pumpEventQueue();
    expect(speaks(), [said(first)]);
    prompts.add(now);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(first), 'stop', said(now)]);
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(first), 'stop', said(now)]);
  });

  test('a newer interrupter also clears the waiting slot', () async {
    engine.stopEndsSpeech = false;
    final last = sampleRoute.steps.length - 1;
    final far = ann(AnnouncementKind.approaching, 1);
    final arrived = ann(AnnouncementKind.arrived, last);
    prompts.add(far);
    await pumpEventQueue();
    prompts
      ..add(ann(AnnouncementKind.now, 1))
      ..add(ann(AnnouncementKind.approaching, last))
      ..add(arrived);
    await pumpEventQueue();
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(arrived)]);
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(arrived)]);
  });

  group('during the language check', () {
    late Completer<bool> gate;
    setUp(() => engine.availableGate = gate = Completer<bool>());

    for (final available in [true, false]) {
      test('dispose, then the check resolves $available: no engine call, '
          'no error', () async {
        prompts.add(ann(AnnouncementKind.approaching, 1));
        await pumpEventQueue();
        expect(engine.log, ['available:en-US']);
        await voice.dispose();
        expect(engine.log, ['available:en-US', 'stop']);
        gate.complete(available);
        await pumpEventQueue();
        expect(engine.log, ['available:en-US', 'stop']);
        expect(errors, isEmpty);
      });
    }

    test('a burst follows the queue rules once the check resolves', () async {
      final far = ann(AnnouncementKind.approaching, 1);
      final now = ann(AnnouncementKind.now, 1);
      final next = ann(AnnouncementKind.approaching, 2);
      prompts.add(far);
      await pumpEventQueue();
      prompts
        ..add(now)
        ..add(next);
      await pumpEventQueue();
      gate.complete(true);
      await pumpEventQueue();
      expect(engine.log, ['available:en-US', 'stop', said(now)]);
      engine.finish();
      await pumpEventQueue();
      expect(engine.log, ['available:en-US', 'stop', said(now), said(next)]);
      expect(errors, isEmpty);
    });
  });

  test('arrived interrupts approaching', () async {
    final last = sampleRoute.steps.length - 1;
    final far = ann(AnnouncementKind.approaching, last);
    final arrived = ann(AnnouncementKind.arrived, last);
    prompts.add(far);
    await pumpEventQueue();
    prompts.add(arrived);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(arrived)]);
  });

  test('now does not interrupt now', () async {
    final first = ann(AnnouncementKind.now, 1);
    final second = ann(AnnouncementKind.now, 2);
    prompts.add(first);
    await pumpEventQueue();
    prompts.add(second);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(first)]);
    engine.finish();
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(first), said(second)]);
  });

  test('a burst: now, then approaching in the same microtask', () async {
    final now = ann(AnnouncementKind.now, 1);
    final next = ann(AnnouncementKind.approaching, 2);
    prompts
      ..add(now)
      ..add(next);
    await pumpEventQueue();
    expect(speaks(), [said(now)]);
    engine.finish();
    await pumpEventQueue();
    expect(speaks(), [said(now), said(next)]);
    expect(engine.log, isNot(contains('stop')));
  });

  for (final quiet in [AudioGuidance.alertsOnly, AudioGuidance.muted]) {
    test('${quiet.name} drops prompts', () async {
      mode.value = quiet;
      prompts
        ..add(ann(AnnouncementKind.approaching, 1))
        ..add(ann(AnnouncementKind.now, 1));
      await pumpEventQueue();
      expect(speaks(), isEmpty);
    });
  }

  test('muting mid-speech stops and clears the waiting prompt', () async {
    final first = ann(AnnouncementKind.approaching, 1);
    final second = ann(AnnouncementKind.approaching, 2);
    prompts
      ..add(first)
      ..add(second);
    await pumpEventQueue();
    expect(speaks(), [said(first)]);
    mode.value = AudioGuidance.muted;
    expect(engine.log.last, 'stop');
    engine.finish();
    await pumpEventQueue();
    expect(speaks(), [said(first)]);
  });

  test('the spoken prompt completing after a mute does not play the waiting '
      'one', () async {
    engine.stopEndsSpeech = false;
    final first = ann(AnnouncementKind.approaching, 1);
    final second = ann(AnnouncementKind.approaching, 2);
    prompts
      ..add(first)
      ..add(second);
    await pumpEventQueue();
    mode.value = AudioGuidance.muted;
    await pumpEventQueue();
    engine.finish();
    await pumpEventQueue();
    expect(speaks(), [said(first)]);
    expect(errors, isEmpty);
  });

  test('unmuting before the stopped prompt ends does not bring back the '
      'waiting one', () async {
    engine.stopEndsSpeech = false;
    final first = ann(AnnouncementKind.approaching, 1);
    final second = ann(AnnouncementKind.approaching, 2);
    prompts
      ..add(first)
      ..add(second);
    await pumpEventQueue();
    mode.value = AudioGuidance.muted;
    mode.value = AudioGuidance.sound;
    engine.finish();
    await pumpEventQueue();
    expect(speaks(), [said(first)]);
    final third = ann(AnnouncementKind.approaching, 3);
    prompts.add(third);
    await pumpEventQueue();
    expect(speaks(), [said(first), said(third)]);
  });

  test('language unavailable: one error, nothing spoken', () async {
    engine.available = false;
    prompts.add(ann(AnnouncementKind.approaching, 1));
    await pumpEventQueue();
    prompts.add(ann(AnnouncementKind.now, 1));
    await pumpEventQueue();
    expect(errors, hasLength(1));
    expect(
      errors.single,
      isA<TtsVoiceUnavailable>().having((e) => e.language, 'language', 'en-US'),
    );
    expect(speaks(), isEmpty);
    expect(engine.log.where((l) => l.startsWith('available:')), hasLength(1));
  });

  test('language check throws: reported once, nothing spoken', () async {
    final boom = StateError('boom');
    engine.availableError = boom;
    prompts.add(ann(AnnouncementKind.approaching, 1));
    await pumpEventQueue();
    prompts.add(ann(AnnouncementKind.now, 1));
    await pumpEventQueue();
    expect(errors, [boom]);
    expect(speaks(), isEmpty);
    expect(engine.log.where((l) => l.startsWith('available:')), hasLength(1));
  });

  test('speak throws: reported, and the next prompt still plays', () async {
    const boom = TtsEngineException('boom');
    engine.speakError = boom;
    final first = ann(AnnouncementKind.approaching, 1);
    prompts.add(first);
    await pumpEventQueue();
    expect(errors, [boom]);
    engine.speakError = null;
    final second = ann(AnnouncementKind.now, 1);
    prompts.add(second);
    await pumpEventQueue();
    expect(speaks(), [said(first), said(second)]);
    expect(errors, [boom]);
  });

  test('a speak ended by the voice stopping it is not an error', () async {
    engine.stopError = const TtsEngineException('stopped');
    final far = ann(AnnouncementKind.approaching, 1);
    final now = ann(AnnouncementKind.now, 1);
    prompts.add(far);
    await pumpEventQueue();
    prompts.add(now);
    await pumpEventQueue();
    expect(engine.log.sublist(1), [said(far), 'stop', said(now)]);
    mode.value = AudioGuidance.muted;
    await pumpEventQueue();
    expect(errors, isEmpty);
  });

  test('language from the formatter', () async {
    const vi = VietnameseGuidanceFormatter();
    final viPrompts = StreamController<GuidanceAnnouncement>.broadcast();
    final viVoice = NavigationVoice(
      announcements: viPrompts.stream,
      formatter: vi,
      engine: engine,
    );
    addTearDown(viVoice.dispose);
    expect(viVoice.language, 'vi-VN');
    expect(defaultVoiceLanguage(vi), 'vi-VN');
    expect(defaultVoiceLanguage(formatter), 'en-US');
    final a = ann(AnnouncementKind.approaching, 1);
    viPrompts.add(a);
    await pumpEventQueue();
    expect(engine.log, [
      'available:vi-VN',
      'speak:vi-VN:${vi.announcement(a)}',
    ]);
  });

  test('an explicit language overrides the formatter', () async {
    final gbPrompts = StreamController<GuidanceAnnouncement>.broadcast();
    final gbVoice = NavigationVoice(
      announcements: gbPrompts.stream,
      formatter: formatter,
      engine: engine,
      language: 'en-GB',
    );
    addTearDown(gbVoice.dispose);
    expect(gbVoice.language, 'en-GB');
    final a = ann(AnnouncementKind.approaching, 1);
    gbPrompts.add(a);
    await pumpEventQueue();
    expect(engine.log, [
      'available:en-GB',
      'speak:en-GB:${formatter.announcement(a)}',
    ]);
  });

  test('dispose while speaking stops once, then nothing reaches the '
      'engine', () async {
    prompts
      ..add(ann(AnnouncementKind.approaching, 1))
      ..add(ann(AnnouncementKind.approaching, 2));
    await pumpEventQueue();
    await voice.dispose();
    expect(engine.log.last, 'stop');
    final before = [...engine.log];
    prompts.add(ann(AnnouncementKind.now, 1));
    mode.value = AudioGuidance.muted;
    engine.finish();
    await pumpEventQueue();
    await voice.dispose();
    expect(engine.log, before);
    expect(engine.log.where((l) => l == 'stop'), hasLength(1));
    expect(engine.log, isNot(contains('dispose')));
  });

  test('a waiting prompt is not spoken when its predecessor ends after '
      'dispose', () async {
    engine.stopEndsSpeech = false;
    prompts
      ..add(ann(AnnouncementKind.approaching, 1))
      ..add(ann(AnnouncementKind.approaching, 2));
    await pumpEventQueue();
    await voice.dispose();
    final before = [...engine.log];
    engine.finish();
    await pumpEventQueue();
    expect(engine.log, before);
  });

  test('forSession speaks the session announcements', () async {
    // Setup from the core session test 'arrival emits Arrived once'.
    final route = sampleRoute;
    final source = _FakeFixSource();
    var now = DateTime.utc(2026);
    final session = NavigationSession(fixes: source, clock: () => now);
    addTearDown(session.dispose);
    final sessionVoice = NavigationVoice.forSession(
      session,
      formatter: formatter,
      engine: engine,
      onError: errors.add,
    );
    addTearDown(sessionVoice.dispose);
    session.start(route: route);
    for (var i = 0; i < 8 * 60; i++) {
      if (i % 60 == 0) {
        final s = route.length - 40 + 8.0 * (i ~/ 60);
        source.add(
          NavFix(
            position: route.pointAt(s),
            accuracy: 5,
            speed: 8,
            heading: route.bearingAt(s),
            time: now,
          ),
        );
      }
      now = now.add(const Duration(microseconds: 16667));
      session.tick(1 / 60);
      await pumpEventQueue(times: 1);
    }
    await pumpEventQueue();
    expect(speaks(), isNotEmpty);
    expect(errors, isEmpty);
  });
}
