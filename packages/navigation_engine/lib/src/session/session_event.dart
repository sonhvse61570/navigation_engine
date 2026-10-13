import '../route/nav_route.dart';

/// Something that happened during a `NavigationSession`.
sealed class SessionEvent {
  const SessionEvent();
}

/// The vehicle has been away from the route long enough to count.
final class OffRoute extends SessionEvent {
  /// Creates the event.
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
  /// Creates the event.
  const Rerouting();
}

/// The session switched to [route] after going off route.
final class Rerouted extends SessionEvent {
  /// Creates the event for the switch to [route].
  const Rerouted(this.route);

  /// The route the session switched to.
  final NavRoute route;
}

/// The `RouteProvider` failed; the session keeps going and retries later.
final class RerouteFailed extends SessionEvent {
  /// Creates the event for a failed request, with the [error] and its
  /// [stackTrace].
  const RerouteFailed(this.error, this.stackTrace);

  /// What the `RouteProvider` threw.
  final Object error;

  /// Where [error] was thrown.
  final StackTrace stackTrace;
}

/// The vehicle reached the destination.
final class Arrived extends SessionEvent {
  /// Creates the event.
  const Arrived();
}

/// The `FixSource` stream reported an error; the session keeps listening.
final class FixSourceError extends SessionEvent {
  /// Creates the event for an [error] reported with its [stackTrace].
  const FixSourceError(this.error, this.stackTrace);

  /// The error the fix stream reported.
  final Object error;

  /// The stack trace that came with [error].
  final StackTrace stackTrace;
}

/// Counters for diagnostics overlays.
final class SessionStats {
  /// Creates a snapshot of the counters.
  const SessionStats({
    required this.fixesAccepted,
    required this.fixesRejected,
    required this.cameraMoves,
    required this.cameraFramesSkipped,
  });

  /// Fixes that passed the `FixFilter`.
  final int fixesAccepted;

  /// Dropped by the `FixFilter`.
  final int fixesRejected;

  /// Camera updates sent to the map.
  final int cameraMoves;

  /// Frames whose camera update was dropped because the previous one was
  /// still being applied.
  final int cameraFramesSkipped;
}
