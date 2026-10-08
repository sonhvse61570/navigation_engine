import 'package:flutter/material.dart';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:navigation_engine/testing.dart';

import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  // Mapbox registers platform channels in setAccessToken, so the binding must exist first.
  WidgetsFlutterBinding.ensureInitialized();
  // flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx
  MapboxOptions.setAccessToken(
    const String.fromEnvironment('MAPBOX_ACCESS_TOKEN'),
  );
  runApp(
    MaterialApp(
      title: 'navigation_engine_mapbox example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1A73E8)),
      home: const DrivingScreen(),
    ),
  );
}

/// Drives the sample route with simulated GPS on Mapbox (needs a public access token).
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
          MapboxNavigationView(
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
