import 'package:navigation_engine/navigation_engine.dart';

/// Where a [NavigationFlowController] is in a trip: idle, loading routes,
/// showing route options, navigating, arrived, or failed.
sealed class NavigationFlowState {
  const NavigationFlowState();
}

/// No destination.
final class FlowIdle extends NavigationFlowState {
  const FlowIdle();

  @override
  String toString() => 'FlowIdle()';
}

/// Routes to [to] are being requested.
final class FlowLoading extends NavigationFlowState {
  const FlowLoading(this.to);

  final GeoPoint to;

  @override
  String toString() => 'FlowLoading($to)';
}

/// Route options are shown; [selected] indexes [routes] (best first).
final class FlowOverview extends NavigationFlowState {
  FlowOverview(List<NavRoute> routes, this.selected)
    : routes = List.unmodifiable(routes) {
    RangeError.checkValidIndex(selected, this.routes, 'selected');
  }

  final List<NavRoute> routes;
  final int selected;

  /// The selected route.
  NavRoute get route => routes[selected];

  @override
  String toString() => 'FlowOverview(${routes.length} routes, $selected)';
}

/// Turn-by-turn guidance along [route] (the current one, after reroutes).
final class FlowNavigating extends NavigationFlowState {
  const FlowNavigating(this.route);

  final NavRoute route;

  @override
  String toString() => 'FlowNavigating(${route.name})';
}

/// The vehicle reached the end of [route].
final class FlowArrived extends NavigationFlowState {
  const FlowArrived(this.route);

  final NavRoute route;

  @override
  String toString() => 'FlowArrived(${route.name})';
}

/// Requesting routes to [to] failed. [previous] is the state before the
/// request: `NavigationFlowController.cancel` goes back to it, and
/// `preview(to: error.to)` retries.
final class FlowError extends NavigationFlowState {
  const FlowError(this.error, this.previous, this.to);

  final Object error;
  final NavigationFlowState previous;

  /// The destination that was requested.
  final GeoPoint to;

  @override
  String toString() => 'FlowError($error, previous: $previous, to: $to)';
}
