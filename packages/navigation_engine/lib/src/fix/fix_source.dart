import 'nav_fix.dart';

/// Where fixes come from: the device GPS, a simulator, a recorded trip…
///
/// Implementations deliver fixes on a broadcast stream so that several
/// listeners (a session and a debug overlay, say) can share one source.
abstract interface class FixSource {
  /// Broadcast stream of fixes, in the order they were measured.
  Stream<NavFix> get fixes;

  bool get isRunning;

  /// Starts delivering fixes. Calling it while running does nothing.
  void start();

  /// Stops delivering fixes; [start] may be called again.
  void stop();

  /// Releases resources; the source cannot be restarted.
  void dispose();
}
