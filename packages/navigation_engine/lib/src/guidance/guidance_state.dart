import '../route/route_step.dart';
import 'guidance_announcement.dart';

/// What a turn-by-turn banner shows at one moment.
final class GuidanceState {
  const GuidanceState({
    required this.step,
    required this.stepIndex,
    required this.distanceToStep,
    required this.thenStep,
    required this.remaining,
    required this.arrived,
  });

  /// The next manoeuvre; null when no manoeuvre remains before the
  /// destination (once arrived, after the last one on a route without an
  /// `arrive` step, or when the route has no steps).
  final RouteStep? step;

  /// Index of [step] in `route.steps`; -1 when no manoeuvre remains before
  /// the destination.
  final int stepIndex;

  /// Metres along the route to [step] (not straight-line), or to the
  /// destination when [step] is null.
  final double distanceToStep;

  /// The manoeuvre to show after [step] ("Then" and its icon), else null:
  /// the next manoeuvre whenever [step] goes straight on, skipping further
  /// straight-on steps (the arrival when no manoeuvre is left), or the next
  /// step when it follows within `NavGuidance.thenWithin`. Speech reads
  /// [GuidanceAnnouncement.thenStep] instead, which reaches only
  /// `NavGuidance.spokenThenWithin`.
  final RouteStep? thenStep;

  /// Metres along the route to the destination.
  final double remaining;
  final bool arrived;
}
