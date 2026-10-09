import 'package:navigation_engine/navigation_engine.dart';

import 'place_label.dart';

/// Where a [NavigationFlowController] is in a trip: idle, loading routes,
/// showing route options, navigating, arrived, or failed.
sealed class NavigationFlowState {
  /// Creates a state; the subclasses are the states.
  const NavigationFlowState();
}

/// No destination.
final class FlowIdle extends NavigationFlowState {
  /// Creates the idle state.
  const FlowIdle();

  @override
  String toString() => 'FlowIdle()';
}

/// Routes to [to] are being requested.
final class FlowLoading extends NavigationFlowState {
  /// Creates the state of a request for routes to [to].
  const FlowLoading(this.to);

  /// The destination requested.
  final GeoPoint to;

  @override
  String toString() => 'FlowLoading($to)';
}

/// Route options are shown; [selected] indexes [routes] (best first).
final class FlowOverview extends NavigationFlowState {
  /// Creates an overview of [routes] with [selected] chosen; throws
  /// [RangeError] when [selected] is not an index of [routes].
  FlowOverview(List<NavRoute> routes, this.selected, {this.destination})
    : routes = List.unmodifiable(routes) {
    RangeError.checkValidIndex(selected, this.routes, 'selected');
  }

  /// The route options, best first; unmodifiable.
  final List<NavRoute> routes;

  /// The index in [routes] of the route chosen.
  final int selected;

  /// The destination's label, as passed to `preview` or `previewRoutes`;
  /// null when none was given.
  final PlaceLabel? destination;

  /// The selected route.
  NavRoute get route => routes[selected];

  @override
  String toString() => 'FlowOverview(${routes.length} routes, $selected)';
}

/// Turn-by-turn guidance along [route] (the current one, after reroutes).
final class FlowNavigating extends NavigationFlowState {
  /// Creates the state of guidance along [route] to [destination].
  const FlowNavigating(this.route, {this.destination});

  /// The route being driven.
  final NavRoute route;

  /// The trip's destination label; null when none was given.
  final PlaceLabel? destination;

  @override
  String toString() => 'FlowNavigating(${route.name})';
}

/// The vehicle reached the end of [route].
final class FlowArrived extends NavigationFlowState {
  /// Creates the state of an arrival at the end of [route].
  const FlowArrived(this.route, {this.destination});

  /// The route that was driven to the end.
  final NavRoute route;

  /// The trip's destination label; null when none was given.
  final PlaceLabel? destination;

  @override
  String toString() => 'FlowArrived(${route.name})';
}

/// Requesting routes to [to] failed. [previous] is the state before the
/// request: `NavigationFlowController.cancel` goes back to it, and
/// `NavigationFlowController.retry` repeats the failed request.
final class FlowError extends NavigationFlowState {
  /// Creates the state of a failed request for routes to [to], made from
  /// [previous].
  const FlowError(this.error, this.previous, this.to);

  /// Why the request failed: the provider's error, or a [StateError] when
  /// there was no start point, no provider or no route.
  final Object error;

  /// The state before the request, never a loading or an error state.
  final NavigationFlowState previous;

  /// The destination that was requested.
  final GeoPoint to;

  @override
  String toString() => 'FlowError($error, previous: $previous, to: $to)';
}
