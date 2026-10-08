import 'package:flutter/material.dart';

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';

import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';

/// The drop-in [MapboxStyleNavigation] on the sample route, driven by
/// simulated GPS (needs a public access token).
///
/// Tap "Preview demo trip" to see the route options, pick one and start.
/// The simulated car drives the route that was picked, and goes back to the
/// start after a stop or an arrival.
class MapboxStyleDemoScreen extends StatefulWidget {
  const MapboxStyleDemoScreen({super.key});

  @override
  State<MapboxStyleDemoScreen> createState() => _MapboxStyleDemoScreenState();
}

class _MapboxStyleDemoScreenState extends State<MapboxStyleDemoScreen> {
  final _sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights);
  late final _source = SimulatedFixSource(_sim);
  late final _session = NavigationSession(fixes: _source);
  late final _flow = NavigationFlowController(session: _session);

  /// The route the simulator was last set to by the flow; null after a
  /// reset.
  NavRoute? _simRoute;

  @override
  void initState() {
    super.initState();
    _flow.state.addListener(_onFlowState);
  }

  void _onFlowState() {
    switch (_flow.state.value) {
      case FlowNavigating(:final route):
        // Drive the route that was picked. A resume after the trip overview
        // gives the same route again: setting it would move the car.
        if (!identical(route, _simRoute)) {
          _simRoute = route;
          _sim.setRoute(route);
        }
      case FlowIdle():
        // After a stop or an arrival, back to the start for the next trip.
        if (_simRoute != null) {
          _simRoute = null;
          _sim.teleport(0);
          _session.resetMotion();
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _flow.state.removeListener(_onFlowState);
    _flow.dispose();
    _session.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapboxStyleNavigation(
        session: _session,
        flow: _flow,
        initialCenter: sampleRoute.points.first,
        idleBuilder: (context) => SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: () => _flow.previewRoutes([
                  sampleRoute,
                  ...sampleRouteAlternatives,
                ]),
                child: const Text('Preview demo trip'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
