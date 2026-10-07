// ignore_for_file: avoid_print

import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';

/// Drives the sample route with simulated GPS on a virtual clock (no map,
/// no waiting) and prints every prompt a driver would hear.
///
///     dart run bin/console.dart
void main() {
  const formatter = EnglishGuidanceFormatter();
  final sim = GpsSimulator(sampleRoute, stops: sampleRouteRedLights);
  final filter = FixFilter();
  final engine = RouteMotionEngine(sampleRoute);
  final guidance = NavGuidance(sampleRoute);
  final t0 = DateTime.utc(2026);
  const dt = 1 / 60;
  var nextFix = 1.0;

  print(
    'Driving "${sampleRoute.name}" '
    '(${formatter.distance(sampleRoute.length)})',
  );
  for (var t = 0.0; !sim.finished && t < 1200; t += dt) {
    sim.advance(dt);
    final now = t0.add(Duration(microseconds: (t * 1e6).round()));
    if (t >= nextFix) {
      nextFix += 1;
      final fix = sim.sample(now);
      if (filter.accept(fix)) engine.onFix(fix, now);
    }
    final s = engine.tick(dt, now)?.routeDistance;
    if (s == null) continue;
    for (final a in guidance.update(s).announcements) {
      print('${_clock(t)}  ${formatter.announcement(a)}');
    }
  }
}

String _clock(double seconds) {
  final s = seconds.round();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}
