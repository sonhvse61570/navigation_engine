/// What the driver has to do at a [RouteStep]. Routing back ends map their
/// own vocabulary onto these (OSRM `maneuver.type`, Google `maneuver`, …).
enum ManeuverType {
  depart,
  arrive,
  turn,

  /// The road changes name; nothing to do.
  newName,

  /// Keep going (OSRM `continue`, `notification`, …).
  continueOn,
  merge,
  onRamp,
  offRamp,
  fork,
  endOfRoad,
  roundabout,
  exitRoundabout,
}

/// The direction of a manoeuvre.
enum ManeuverModifier {
  none,
  uturn,
  sharpRight,
  right,
  slightRight,
  straight,
  slightLeft,
  left,
  sharpLeft;

  bool get isLeft => this == left || this == slightLeft || this == sharpLeft;
}
