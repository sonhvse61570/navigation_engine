import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

Matcher near(DateTime expected, {int minutes = 2}) => predicate<DateTime?>(
  (t) => t != null && t.difference(expected).inSeconds.abs() <= minutes * 60,
  'within $minutes min of $expected',
);

void main() {
  const london = GeoPoint(51.5074, -0.1278);
  const hcmc = GeoPoint(10.7769, 106.7009);
  const tromso = GeoPoint(69.6496, 18.9560);

  test('London, June and December solstices (UTC)', () {
    final june = SunTimes.at(london, DateTime.utc(2024, 6, 21, 12));
    expect(june.sunrise, near(DateTime.utc(2024, 6, 21, 3, 43)));
    expect(june.sunset, near(DateTime.utc(2024, 6, 21, 20, 21)));
    final dec = SunTimes.at(london, DateTime.utc(2024, 12, 21, 12));
    expect(dec.sunrise, near(DateTime.utc(2024, 12, 21, 8, 4)));
    expect(dec.sunset, near(DateTime.utc(2024, 12, 21, 15, 53)));
  });

  test('Ho Chi Minh City: the local day is chosen by solar time', () {
    // 06:30 local (UTC+7) on 2024-06-21 is 23:30 UTC on 2024-06-20.
    final morning = DateTime.utc(2024, 6, 20, 23, 30);
    final t = SunTimes.at(hcmc, morning);
    expect(t.sunrise, near(DateTime.utc(2024, 6, 20, 22, 32), minutes: 4));
    expect(t.sunset, near(DateTime.utc(2024, 6, 21, 11, 14), minutes: 4));
    expect(t.isNight(morning), isFalse);
    expect(t.isNight(DateTime.utc(2024, 6, 21, 13)), isTrue); // 20:00 local
    expect(t.isNight(DateTime.utc(2024, 6, 20, 21)), isTrue); // 04:00 local
  });

  test('polar day and polar night', () {
    final summer = SunTimes.at(tromso, DateTime.utc(2024, 6, 21, 12));
    expect(summer.alwaysUp, isTrue);
    expect(summer.sunrise, isNull);
    expect(summer.isNight(DateTime.utc(2024, 6, 21, 0)), isFalse);
    final winter = SunTimes.at(tromso, DateTime.utc(2024, 12, 21, 12));
    expect(winter.alwaysUp, isFalse);
    expect(winter.sunset, isNull);
    expect(winter.isNight(DateTime.utc(2024, 12, 21, 12)), isTrue);
  });
}
