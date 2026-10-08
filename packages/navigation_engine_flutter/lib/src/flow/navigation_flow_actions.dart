import 'package:flutter/foundation.dart';

/// The flow actions a [NavigationFlowScaffold] gives the pieces it builds:
/// the panel, the header, the footer, the top end slot and the arrival.
///
/// Each one is guarded against stale state: a call in a state where the
/// action does not apply does nothing, so a double tap, or a tap on a piece
/// built for a state the flow has since left, is harmless.
final class NavigationFlowActions {
  /// Creates the actions.
  const NavigationFlowActions({
    required this.select,
    required this.start,
    required this.end,
    required this.backToOverview,
    required this.cancel,
    required this.close,
    required this.retry,
    required this.showSteps,
    required this.recenter,
  });

  /// Selects a route option; only in the overview.
  final ValueChanged<int> select;

  /// Starts the selected route, or resumes the trip from its own overview;
  /// only in the overview.
  final VoidCallback start;

  /// Ends the trip: the scaffold's `onEnd`, or else
  /// `NavigationFlowController.stop`. Only while a trip runs: navigating,
  /// arrived, or in the trip's own overview.
  final VoidCallback end;

  /// From navigating or arrived, to the trip's own overview.
  final VoidCallback backToOverview;

  /// Leaves loading or an error for the state before the request.
  final VoidCallback cancel;

  /// Closes a route preview, back to idle. Null unless the state is the
  /// overview of a preview (not the trip's own overview).
  final VoidCallback? close;

  /// Repeats the failed request; only in an error. A failure is reported
  /// through `FlutterError.reportError`, not thrown.
  final VoidCallback retry;

  /// Opens the step list of the route shown, in a sheet that follows the
  /// guidance and closes when the flow moves on; in the overview and while
  /// navigating.
  final VoidCallback showSteps;

  /// Makes the camera follow the vehicle again (`session.follow = true`);
  /// while idle or navigating.
  final VoidCallback recenter;
}
