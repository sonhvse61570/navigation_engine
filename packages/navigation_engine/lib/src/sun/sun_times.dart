import 'dart:math' as math;

import '../geo/geo_point.dart';

/// Sunrise and sunset at one place on one local solar day, from the NOAA
/// sunrise equation (no time-zone data needed). Within about 2 minutes of
/// published times at mid-latitudes. All times are UTC.
final class SunTimes {
  const SunTimes._(this.sunrise, this.sunset, this.alwaysUp);

  /// The sun times at [position] for the local solar day that contains
  /// [time] (the day is chosen from the longitude, so 06:30 in Ho Chi Minh
  /// City is the same day as that evening's sunset, even though it is the
  /// previous UTC day).
  factory SunTimes.at(GeoPoint position, DateTime time) {
    final lon = position.lng;
    final solar = time.toUtc().add(
      Duration(milliseconds: (lon / 15 * 3600000).round()),
    );
    final noon = DateTime.utc(solar.year, solar.month, solar.day, 12);
    // Days since J2000.0 (2000-01-01 12:00 UTC).
    final n = noon.difference(_j2000).inHours / 24;
    final jStar = n - lon / 360;
    final m = _norm(357.5291 + 0.98560028 * jStar);
    final mr = _rad(m);
    final c =
        1.9148 * math.sin(mr) +
        0.0200 * math.sin(2 * mr) +
        0.0003 * math.sin(3 * mr);
    final lambda = _rad(_norm(m + c + 180 + 102.9372));
    final transit =
        jStar + 0.0053 * math.sin(mr) - 0.0069 * math.sin(2 * lambda);
    final sinDec = math.sin(lambda) * math.sin(_rad(23.4397));
    final cosDec = math.sqrt(1 - sinDec * sinDec);
    final lat = _rad(position.lat);
    final cosH =
        (math.sin(_rad(-0.833)) - math.sin(lat) * sinDec) /
        (math.cos(lat) * cosDec);
    if (cosH > 1) return const SunTimes._(null, null, false);
    if (cosH < -1) return const SunTimes._(null, null, true);
    final h = math.acos(cosH) * 180 / math.pi / 360;
    return SunTimes._(_at(transit - h), _at(transit + h), false);
  }

  /// Sunrise (UTC); null when the sun does not rise or set that day.
  final DateTime? sunrise;

  /// Sunset (UTC); null when the sun does not rise or set that day.
  final DateTime? sunset;

  /// True on a polar day (the sun stays up). False on a polar night.
  final bool alwaysUp;

  /// Whether [t] is before sunrise or from sunset on. A polar day is never
  /// night; a polar night always is.
  bool isNight(DateTime t) {
    final rise = sunrise, set = sunset;
    if (rise == null || set == null) return !alwaysUp;
    final u = t.toUtc();
    return u.isBefore(rise) || !u.isBefore(set);
  }

  @override
  String toString() => alwaysUp
      ? 'SunTimes(polar day)'
      : sunrise == null
      ? 'SunTimes(polar night)'
      : 'SunTimes(rise $sunrise, set $sunset)';

  static final _j2000 = DateTime.utc(2000, 1, 1, 12);

  static DateTime _at(double days) =>
      _j2000.add(Duration(milliseconds: (days * 86400000).round()));

  static double _norm(double deg) => deg % 360;

  static double _rad(double deg) => deg * math.pi / 180;
}
