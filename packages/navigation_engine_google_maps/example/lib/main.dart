import 'package:flutter/material.dart';

import 'package:navigation_engine/testing.dart';

import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_demo.dart';

void main() {
  // Android: the Maps API key is read from android/local.properties
  // (MAPS_API_KEY); see the README for iOS.
  runApp(
    MaterialApp(
      title: 'navigation_engine_google_maps example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1A73E8)),
      home: const DrivingScreen(),
    ),
  );
}

/// Drives the sample route with simulated GPS on Google Maps (needs your Maps API key).
class DrivingScreen extends StatefulWidget {
  const DrivingScreen({super.key});

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  final _sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights);
  late final _source = SimulatedFixSource(_sim);
  late final _session = NavigationSession(fixes: _source);

  @override
  void dispose() {
    _session.dispose();
    _source.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (!_session.isRunning) {
        _session.start(route: sampleRoute);
      } else if (_sim.finished) {
        _sim.teleport(0);
        _session.resetMotion();
        _session.resume();
      } else if (_session.isPaused) {
        _session.resume();
      } else {
        _session.pause();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final driving = _session.isRunning && !_session.isPaused;
    return Scaffold(
      body: Stack(
        children: [
          GoogleMapsNavigationView(
            session: _session,
            initialCenter: sampleRoute.points.first,
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: NavigationBanner(
              session: _session,
              showLastAnnouncement: true,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 96,
            right: 12,
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GoogleStyleDemoScreen(),
                ),
              ),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Google-style UI'),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggle,
        icon: Icon(driving ? Icons.pause : Icons.play_arrow),
        label: Text(
          !_session.isRunning
              ? 'Drive'
              : _sim.finished
              ? 'Restart'
              : driving
              ? 'Pause'
              : 'Resume',
        ),
      ),
    );
  }
}
