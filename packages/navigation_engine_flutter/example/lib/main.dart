import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  runApp(
    const MaterialApp(
      title: 'navigation_engine_flutter example',
      debugShowCheckedModeBanner: false,
      home: FrameDemo(),
    ),
  );
}

/// The map-independent frame and banner over a placeholder "map": use a
/// map adapter package (navigation_engine_flutter_map, _maplibre,
/// _google_maps, _mapbox) for a real one.
class FrameDemo extends StatefulWidget {
  const FrameDemo({super.key});

  @override
  State<FrameDemo> createState() => _FrameDemoState();
}

class _FrameDemoState extends State<FrameDemo> {
  late final _source = SimulatedFixSource(
    GpsSimulator(sampleRoute, stops: sampleRouteRedLights),
  );
  late final _session = NavigationSession(fixes: _source)
    ..start(route: sampleRoute);

  @override
  void dispose() {
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
            mapBuilder: (context, padding) => StreamBuilder(
              stream: _session.frames,
              builder: (context, snapshot) {
                final f = snapshot.data;
                return ColoredBox(
                  color: const Color(0xFFE8EAED),
                  child: Center(
                    child: Text(
                      f == null
                          ? 'Waiting for GPS…'
                          : '${f.routeDistance?.toStringAsFixed(0)} m · '
                                '${(f.speed * 3.6).toStringAsFixed(0)} km/h · '
                                '${f.bearing.toStringAsFixed(0)}°',
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: NavigationBanner(session: _session),
          ),
        ],
      ),
    );
  }
}
