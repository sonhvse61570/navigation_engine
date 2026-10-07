import 'dart:async';
import 'dart:math' as math;

import '../fix/fix_source.dart';
import '../fix/nav_fix.dart';
import 'gps_simulator.dart';

/// Runs a [GpsSimulator] in real time and streams its fixes at ~1 Hz.
///
/// Fixes are stamped with the `clock` given to the constructor, which must
/// be the clock the session uses
/// (`NavigationSession(clock: ...)`): the engines compare the two.
class SimulatedFixSource implements FixSource {
  SimulatedFixSource(this.sim, {DateTime Function() clock = DateTime.now})
    : _now = clock;

  final GpsSimulator sim;
  final DateTime Function() _now;
  final _controller = StreamController<NavFix>.broadcast();
  final _rng = math.Random(3);
  Timer? _physics;
  Timer? _emit;
  final _clock = Stopwatch();
  Duration _lastPhysics = Duration.zero;

  @override
  Stream<NavFix> get fixes => _controller.stream;

  @override
  bool get isRunning => _physics != null;

  @override
  void start() {
    if (isRunning || _controller.isClosed) return;
    _clock
      ..reset()
      ..start();
    _lastPhysics = Duration.zero;
    _physics = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = _clock.elapsed;
      sim.advance((now - _lastPhysics).inMicroseconds / 1e6);
      _lastPhysics = now;
    });
    _scheduleFix();
  }

  void _scheduleFix() {
    // Real receivers deliver at ~1 Hz but not on the dot.
    final ms = 1000 + ((_rng.nextDouble() - 0.5) * 300).round();
    _emit = Timer(Duration(milliseconds: ms), () {
      _controller.add(sim.sample(_now()));
      _scheduleFix();
    });
  }

  @override
  void stop() {
    _physics?.cancel();
    _emit?.cancel();
    _physics = _emit = null;
    _clock.stop();
  }

  @override
  void dispose() {
    stop();
    unawaited(_controller.close());
  }
}
