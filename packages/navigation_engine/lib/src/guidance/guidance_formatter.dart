import '../route/route_step.dart';
import 'guidance_announcement.dart';

/// Turns guidance into words for one language. Implement it to add a
/// language; `EnglishGuidanceFormatter` and `VietnameseGuidanceFormatter`
/// ship with the package.
abstract class GuidanceFormatter {
  const GuidanceFormatter();

  /// The banner text for [step]: "Turn right onto Main Street".
  String instruction(RouteStep step);

  /// The spoken prompt: "In 200 m, turn right onto Main Street, then turn
  /// left".
  String announcement(GuidanceAnnouncement a);

  /// A distance as shown and spoken: "80 m", "1.2 km".
  String distance(double metres);

  /// A remaining time: "45 s" below a minute, then whole minutes ("12 min"),
  /// then hours and minutes ("1 h 5 min"). Negative durations read as 0 s.
  String duration(Duration d) {
    final (:seconds, :hours, :minutes) = splitDuration(d);
    if (seconds != null) return '$seconds s';
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  /// A time of day, 24-hour, in [t]'s own time zone: "14:35".
  String clockTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// A speed with its unit: [speedValue] and [speedUnit], "42 km/h".
  String speed(double metresPerSecond) =>
      '${speedValue(metresPerSecond)} $speedUnit';

  /// The number of a speed, without its unit: whole km/h by default, "42".
  /// Override it with [speedUnit] to show another unit, such as mph.
  String speedValue(double metresPerSecond) =>
      '${(metresPerSecond * 3.6).round()}';

  /// The unit of [speedValue]: "km/h" by default.
  String get speedUnit => 'km/h';
}

/// [d] split the way [GuidanceFormatter.duration] reads it: `seconds` is set
/// (and the rest zero) below one minute; otherwise the duration is rounded
/// to whole minutes and split into hours and minutes. Third-party
/// formatters can reuse it to word durations in their own language with
/// the same rounding.
({int? seconds, int hours, int minutes}) splitDuration(Duration d) {
  final s = d.isNegative ? 0 : d.inMilliseconds / 1000;
  if (s < 59.5) return (seconds: s.round(), hours: 0, minutes: 0);
  final total = (s / 60).round();
  return (seconds: null, hours: total ~/ 60, minutes: total % 60);
}

/// Metres rounded the way prompts say them: to 10 m below 100 m, to 50 m
/// above, and never less than 10 m.
int roundedMetres(double m) {
  final r = m < 100 ? (m / 10).round() * 10 : (m / 50).round() * 50;
  return r < 10 ? 10 : r;
}

String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
