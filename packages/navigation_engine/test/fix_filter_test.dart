import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

void main() {
  const o = GeoPoint(10.77, 106.69);
  final t0 = DateTime.utc(2026);

  NavFix fix(double northMetres, int ms, {double accuracy = 5}) => NavFix(
    position: offsetPoint(o, 0, northMetres),
    accuracy: accuracy,
    time: t0.add(Duration(milliseconds: ms)),
  );

  test('speed and heading are optional', () {
    final f = fix(0, 0);
    expect(f.speed, isNull);
    expect(f.heading, isNull);
  });

  test('rejects fixes less accurate than maxAccuracy', () {
    expect(FixFilter().accept(fix(0, 0, accuracy: 31)), isFalse);
    expect(FixFilter().accept(fix(0, 0, accuracy: 30)), isTrue);
  });

  test('rejects jumps that imply an impossible speed', () {
    final f = FixFilter();
    expect(f.accept(fix(0, 0)), isTrue);
    // 500 m in 1 s; allowed is 55 m/s * 1 s + 5 + 5 m of accuracy slack.
    expect(f.accept(fix(500, 1000)), isFalse);
    // The rejected fix is not remembered: 40 m from the last accepted one.
    expect(f.accept(fix(40, 1000)), isTrue);
  });

  test('rejects fixes that do not move forward in time', () {
    final f = FixFilter();
    expect(f.accept(fix(0, 1000)), isTrue);
    expect(f.accept(fix(1, 1000)), isFalse);
    expect(f.accept(fix(1, 500)), isFalse);
  });

  test('reset forgets the last fix', () {
    final f = FixFilter()..accept(fix(0, 0));
    f.reset();
    expect(f.accept(fix(500, 1000)), isTrue);
  });
}
