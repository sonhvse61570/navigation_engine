import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  const a = GeoPoint(10.77, 106.69);
  final b = offsetPoint(a, 0, 100);

  const left = Lane(directions: {LaneDirection.left});
  const straightOrRight = Lane(
    directions: {LaneDirection.straight, LaneDirection.right},
    valid: true,
    active: LaneDirection.right,
  );

  test('steps carry their lanes, left to right, unmodifiable', () {
    final r = NavRoute.fromPoints(
      [a, b],
      steps: const [
        RouteStepSeed.atVertex(
          1,
          type: ManeuverType.turn,
          modifier: ManeuverModifier.right,
          lanes: [left, straightOrRight],
        ),
      ],
    );
    final lanes = r.steps.single.lanes;
    expect(lanes, [left, straightOrRight]);
    expect(() => lanes.add(left), throwsUnsupportedError);
  });

  test('lanes default to none', () {
    const seed = RouteStepSeed.atLocation(a, type: ManeuverType.arrive);
    expect(seed.lanes, isEmpty);
    expect(
      const RouteStep(distance: 0, type: ManeuverType.arrive).lanes,
      isEmpty,
    );
  });

  test('Lane has value equality and a readable toString', () {
    const same = Lane(
      directions: {LaneDirection.right, LaneDirection.straight},
      valid: true,
      active: LaneDirection.right,
    );
    expect(same, straightOrRight);
    expect(same.hashCode, straightOrRight.hashCode);
    expect(left, isNot(straightOrRight));
    expect(straightOrRight.toString(), contains('right'));
  });

  test('RouteStep.toString mentions lanes when there are any', () {
    const plain = RouteStep(distance: 12, type: ManeuverType.turn);
    expect(plain.toString(), isNot(contains('lane')));
    const laned = RouteStep(
      distance: 12,
      type: ManeuverType.turn,
      modifier: ManeuverModifier.right,
      roadName: 'Le Lai',
      lanes: [left, straightOrRight, left],
    );
    expect(
      laned.toString(),
      'RouteStep(turn, right, "Le Lai", 12.0 m, 3 lanes)',
    );
  });
}
