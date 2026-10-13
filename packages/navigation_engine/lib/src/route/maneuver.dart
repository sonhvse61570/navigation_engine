/// What the driver has to do at a [RouteStep]. Routing back ends map their
/// own vocabulary onto these (OSRM `maneuver.type`, Google `maneuver`, …).
enum ManeuverType {
  /// The start of the route.
  depart,

  /// The arrival at the destination.
  arrive,

  /// A turn onto another road, in the direction of the step's
  /// [ManeuverModifier].
  turn,

  /// The road changes name; nothing to do.
  newName,

  /// Keep going (OSRM `continue`, `notification`, …).
  continueOn,

  /// Merge into the traffic of another road.
  merge,

  /// Take a ramp to join a highway.
  onRamp,

  /// Take a ramp to leave a highway.
  offRamp,

  /// Keep to one branch of a fork in the road.
  fork,

  /// The road ends at a junction, where the driver has to turn.
  endOfRoad,

  /// Enter a roundabout.
  roundabout,

  /// Leave a roundabout.
  exitRoundabout,
}

/// The direction of a manoeuvre.
enum ManeuverModifier {
  /// No direction.
  none,

  /// Turn back the way you came.
  uturn,

  /// A sharp turn to the right.
  sharpRight,

  /// A turn to the right.
  right,

  /// A slight turn to the right.
  slightRight,

  /// Straight on.
  straight,

  /// A slight turn to the left.
  slightLeft,

  /// A turn to the left.
  left,

  /// A sharp turn to the left.
  sharpLeft;

  /// Whether this turns to the left: [left], [slightLeft] or [sharpLeft].
  bool get isLeft => this == left || this == slightLeft || this == sharpLeft;
}
