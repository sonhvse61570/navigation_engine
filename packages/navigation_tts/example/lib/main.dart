import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_tts/navigation_tts.dart';

void main() {
  runApp(
    const MaterialApp(
      title: 'navigation_tts example',
      debugShowCheckedModeBanner: false,
      home: VoiceDemo(),
    ),
  );
}

/// A simulated drive on the sample route whose prompts are spoken, with a
/// switch that mutes the voice.
class VoiceDemo extends StatefulWidget {
  /// [engine] is for tests; by default the demo speaks through
  /// [FlutterTtsEngine]. The demo disposes the engine it is given.
  const VoiceDemo({super.key, this.engine});

  final TtsEngine? engine;

  @override
  State<VoiceDemo> createState() => _VoiceDemoState();
}

class _VoiceDemoState extends State<VoiceDemo> {
  late final _source = SimulatedFixSource(
    GpsSimulator(sampleRoute, stops: sampleRouteRedLights),
  );
  late final _session = NavigationSession(fixes: _source)
    ..start(route: sampleRoute);
  final _audio = ValueNotifier(AudioGuidance.sound);
  late final TtsEngine _engine = widget.engine ?? FlutterTtsEngine();
  late final NavigationVoice _voice;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Created now, so that the first prompt is heard.
    _voice = NavigationVoice.forSession(
      _session,
      formatter: const EnglishGuidanceFormatter(),
      engine: _engine,
      audioGuidance: _audio,
      onError: (error) {
        if (mounted) setState(() => _error = '$error');
      },
    );
  }

  @override
  void dispose() {
    // The voice first, then the engine that it speaks through.
    _voice.dispose().whenComplete(_engine.dispose);
    _audio.dispose();
    _session.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          NavigationMapFrame(
            session: _session,
            mapBuilder: (context, padding) => ColoredBox(
              color: const Color(0xFFE8EAED),
              child: Center(child: Text(_error ?? 'Listen for the prompts.')),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: NavigationBanner(session: _session),
          ),
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            left: 12,
            right: 12,
            child: Card(
              child: ValueListenableBuilder<AudioGuidance>(
                valueListenable: _audio,
                builder: (context, mode, _) => SwitchListTile(
                  title: const Text('Voice'),
                  value: mode == AudioGuidance.sound,
                  onChanged: (on) => _audio.value = on
                      ? AudioGuidance.sound
                      : AudioGuidance.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
