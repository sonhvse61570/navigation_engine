import '../route/route_step.dart';
import 'guidance_state.dart';

/// Which prompt a [GuidanceAnnouncement] is.
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
  /// Creates the prompt of [kind] for [step], which is at [stepIndex] in the
  /// route, when the vehicle is [distance] metres from it.
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

  /// Whether this approaches the manoeuvre, announces it as imminent or
  /// announces the arrival.
  final AnnouncementKind kind;

  /// The threshold that fired (metres; 0 = "now" and arrival).
  final double threshold;

  /// Actual metres to the manoeuvre when it fired.
  final double distance;

  /// The manoeuvre that follows within `NavGuidance.spokenThenWithin`, to be
  /// announced along ("…, then turn left"). Unlike
  /// [GuidanceState.thenStep], a far manoeuvre after a straight-on step is
  /// never spoken here.
  final RouteStep? thenStep;
}

/// The result of one `NavGuidance.update`.
final class GuidanceUpdate {
  /// Creates the result of an update from the new [state] and the due
  /// [announcements].
  const GuidanceUpdate({required this.state, required this.announcements});

  /// The guidance state after the update.
  final GuidanceState state;

  /// Prompts that became due since the previous update, in order.
  final List<GuidanceAnnouncement> announcements;
}
