import '../route/maneuver.dart';
import '../route/nav_route.dart';
import '../route/route_step.dart';
import 'guidance_announcement.dart';
import 'guidance_state.dart';

/// Turn-by-turn progress along a [NavRoute], driven by the distance the
/// vehicle has travelled (so the banner always matches what is on screen).
///
/// Distances are measured along the route: a straight-line distance to the
/// next turn is wrong on any curved road and wildly wrong after a U-turn.
class NavGuidance {
  NavGuidance(
    this.route, {
    this.thresholds = const [500, 200, 0],
    this.nowDistance = 30,
    this.thenWithin = 100,
    this.arriveWithin = 15,
    this.minGap = 80,
  });

  final NavRoute route;

  /// Announcement distances (m), largest first; 0 is the "now" prompt, which
  /// fires at [nowDistance].
  final List<double> thresholds;
  final double nowDistance;

  /// Two manoeuvres closer than this are announced together.
  final double thenWithin;

  /// Metres from the end that count as arrived.
  final double arriveWithin;

  /// A distance prompt is dropped when the previous prompt for the same step
  /// was less than this many metres earlier ("in 200 m" heard at 223 m and
  /// again at 200 m).
  final double minGap;

  late int _stepIndex = _firstStep();
  final _fired = <(int, double)>{};

  /// Skips the departure step: it is behind the driver from the first frame.
  int _firstStep() {
    final steps = route.steps;
    return steps.isNotEmpty && steps.first.type == ManeuverType.depart ? 1 : 0;
  }

  void reset() {
    _stepIndex = _firstStep();
    _fired.clear();
  }

  /// Updates progress to [distance] metres along the route and returns the
  /// new state plus the announcements that became due since the last call
  /// (in order).
  GuidanceUpdate update(double distance) {
    final steps = route.steps;
    final out = <GuidanceAnnouncement>[];

    // Move past every manoeuvre already driven through. Several can be
    // passed in one update when frames are dropped or the vehicle jumps.
    while (_stepIndex < steps.length &&
        !steps[_stepIndex].isArrival &&
        distance >= steps[_stepIndex].distance) {
      _stepIndex++;
    }

    final remaining = (route.length - distance).clamp(0.0, route.length);
    final arrived = remaining <= arriveWithin;
    if (arrived || _stepIndex >= steps.length) {
      if (arrived && _fired.add((-1, 0))) {
        out.add(
          GuidanceAnnouncement(
            stepIndex: steps.length - 1,
            step: steps.isEmpty ? null : steps.last,
            kind: AnnouncementKind.arrived,
            threshold: 0,
            distance: remaining,
          ),
        );
      }
      // Every manoeuvre is behind (a route without an `arrive` step): only
      // the destination is left.
      return GuidanceUpdate(
        state: GuidanceState(
          step: null,
          stepIndex: -1,
          distanceToStep: remaining,
          thenStep: null,
          remaining: remaining,
          arrived: arrived,
        ),
        announcements: out,
      );
    }

    final step = steps[_stepIndex];
    final toStep = step.distance - distance;
    final next = _stepIndex + 1 < steps.length ? steps[_stepIndex + 1] : null;
    final then = next != null && next.distance - step.distance <= thenWithin
        ? next
        : null;

    // Only the most urgent due threshold is spoken: arriving at a step that
    // is already 150 m away must not read the 500 m prompt first. The ones
    // skipped are marked fired so they never come later.
    double? due;
    for (final t in thresholds) {
      // The arrival is announced once, by the branch above.
      if (step.isArrival && t == 0) continue;
      if (isSilentStep(step)) continue;
      final at = t == 0 ? nowDistance : t;
      if (toStep <= at && !_fired.contains((_stepIndex, t))) due = t;
    }
    if (due != null) {
      for (final t in thresholds) {
        if (t >= due || (t > 0 && toStep - t < minGap)) {
          _fired.add((_stepIndex, t));
        }
      }
      out.add(
        GuidanceAnnouncement(
          stepIndex: _stepIndex,
          step: step,
          kind: due == 0 ? AnnouncementKind.now : AnnouncementKind.approaching,
          threshold: due,
          distance: toStep,
          thenStep: then,
        ),
      );
    }

    return GuidanceUpdate(
      state: GuidanceState(
        step: step,
        stepIndex: _stepIndex,
        distanceToStep: toStep,
        thenStep: then,
        remaining: remaining,
        arrived: false,
      ),
      announcements: out,
    );
  }
}

/// Steps shown on a banner but never spoken: the road only changes name,
/// the departure, or the instruction is to keep going straight.
bool isSilentStep(RouteStep step) =>
    step.type == ManeuverType.newName ||
    step.type == ManeuverType.depart ||
    (step.modifier == ManeuverModifier.straight && !step.isArrival);
