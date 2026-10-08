import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:navigation_engine/testing.dart';

import 'package:navigation_engine_maplibre/navigation_engine_maplibre.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'maplibre_style_demo.dart';

void main() {
  // Android: draw the map in a texture so Flutter widgets (the vehicle puck)
  // can be painted over it.
  MapLibreMap.useHybridComposition = true;
  runApp(
    MaterialApp(
      title: 'navigation_engine_maplibre example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1A73E8)),
      home: const DrivingScreen(),
    ),
  );
}

/// Drives the sample route with simulated GPS on MapLibre with a free OpenFreeMap style (no key).
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
          MapLibreNavigationView(
            session: _session,
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
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
                  builder: (_) => const MapLibreStyleDemoScreen(),
                ),
              ),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Mapbox-style UI'),
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
