import '../route/route_step.dart';
import 'guidance_state.dart';

enum AnnouncementKind {
  /// "In 200 m, turn right".
  approaching,

  /// "Turn right" — the manoeuvre is imminent.
  now,

  /// "You have arrived".
  arrived,
}

/// A one-off prompt: what a voice would say. Turn it into words with a
/// `GuidanceFormatter`.
final class GuidanceAnnouncement {
  const GuidanceAnnouncement({
    required this.stepIndex,
    required this.step,
    required this.kind,
    required this.threshold,
    required this.distance,
    this.thenStep,
  });

  /// Index of [step] in `route.steps` (-1 for an arrival on a route without
  /// steps).
  final int stepIndex;

  /// The manoeuvre announced. For an arrival it is the route's last step,
  /// which is the arrival step when the route has one and otherwise its last
  /// manoeuvre; null only on a route without steps. Formatters do not read
  /// it for arrivals.
  final RouteStep? step;
  final AnnouncementKind kind;

  /// The threshold that fired (metres; 0 = "now" and arrival).
  final double threshold;

  /// Actual metres to the manoeuvre when it fired.
  final double distance;

  /// The manoeuvre that follows closely, to be announced along ("…, then
  /// turn left").
  final RouteStep? thenStep;
}

/// The result of one `NavGuidance.update`.
final class GuidanceUpdate {
  const GuidanceUpdate({required this.state, required this.announcements});

  final GuidanceState state;

  /// Prompts that became due since the previous update, in order.
  final List<GuidanceAnnouncement> announcements;
}
