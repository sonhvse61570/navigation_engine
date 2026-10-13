/// An arrow painted on a lane.
enum LaneDirection {
  /// An arrow for a U-turn.
  uturn,

  /// An arrow for a sharp turn to the left.
  sharpLeft,

  /// An arrow for a turn to the left.
  left,

  /// An arrow bearing slightly to the left.
  slightLeft,

  /// An arrow pointing straight on.
  straight,

  /// An arrow bearing slightly to the right.
  slightRight,

  /// An arrow for a turn to the right.
  right,

  /// An arrow for a sharp turn to the right.
  sharpRight,
}

/// One lane before a manoeuvre, as routing back ends report it (OSRM
/// `intersections.lanes`, Google `lanes`).
final class Lane {
  /// Creates a lane painted with [directions], which is [valid] for the
  /// manoeuvre or not; [active] is the arrow to follow.
  const Lane({required this.directions, this.valid = false, this.active});

  /// The arrows painted on the lane. The const constructor keeps the given
  /// set as it is, so do not mutate it after construction.
  final Set<LaneDirection> directions;

  /// Whether the lane can be used for this manoeuvre.
  final bool valid;

  /// The arrow to follow in this lane, when it is valid.
  final LaneDirection? active;

  @override
  bool operator ==(Object other) =>
      other is Lane &&
      other.valid == valid &&
      other.active == active &&
      other.directions.length == directions.length &&
      other.directions.containsAll(directions);

  @override
  int get hashCode =>
      Object.hash(valid, active, Object.hashAllUnordered(directions));

  @override
  String toString() =>
      'Lane(${directions.map((d) => d.name).join('|')}'
      '${valid ? ', valid' : ''}${active == null ? '' : ', → ${active!.name}'})';
}
