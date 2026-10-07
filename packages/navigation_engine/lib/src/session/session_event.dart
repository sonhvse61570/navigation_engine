import '../route/nav_route.dart';

/// Something that happened during a `NavigationSession`.
sealed class SessionEvent {
  const SessionEvent();
}

/// The vehicle has been away from the route long enough to count.
final class OffRoute extends SessionEvent {
  const OffRoute();
}

/// A new route is being requested from the `RouteProvider`.
///
/// It is followed by [Rerouted] or [RerouteFailed], unless the request is
/// superseded: when the app calls `setRoute` or `stop` (or disposes the
/// session) first, the outcome is dropped without an event. An app showing
/// a "rerouting…" indicator must therefore also clear it on its own
/// `setRoute` / `stop`.
final class Rerouting extends SessionEvent {
  const Rerouting();
}

/// The session switched to [route] after going off route.
final class Rerouted extends SessionEvent {
  const Rerouted(this.route);
  final NavRoute route;
}

/// The `RouteProvider` failed; the session keeps going and retries later.
final class RerouteFailed extends SessionEvent {
  const RerouteFailed(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// The vehicle reached the destination.
final class Arrived extends SessionEvent {
  const Arrived();
}

/// The `FixSource` stream reported an error; the session keeps listening.
final class FixSourceError extends SessionEvent {
  const FixSourceError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// Counters for diagnostics overlays.
final class SessionStats {
  const SessionStats({
    required this.fixesAccepted,
    required this.fixesRejected,
    required this.cameraMoves,
    required this.cameraFramesSkipped,
  });

  final int fixesAccepted;

  /// Dropped by the `FixFilter`.
  final int fixesRejected;

  /// Camera updates sent to the map.
  final int cameraMoves;

  /// Frames whose camera update was dropped because the previous one was
  /// still being applied.
  final int cameraFramesSkipped;
}
