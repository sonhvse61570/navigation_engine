import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'speed_limit_sign_style.dart';

const _signRed = Color(0xFFD93025);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

/// How far over the speed limit the vehicle is.
enum SpeedingLevel {
  /// Not over, or by less than the minor threshold.
  none,

  /// Over by the minor threshold or more.
  minor,

  /// Over by the major threshold or more.
  major,
}

/// The speed limit sign and the speedometer joined in one rounded group, at
/// the bottom start of the navigation screen.
///
/// - **The group:** radius 16, [GoogleStyleColors.speedometerSurface],
///   elevation 3.
/// - **The sign**, drawn as [style], shows when [showLimit] and the limit
///   is known. A tap calls [onLimitTap], such as to show or hide the
///   speedometer.
/// - **The speedometer**, a 56 dp square with the speed and the unit,
///   shows when [showSpeed] and either [speedometerVisible] or the limit is
///   unknown. Alone (no sign), it is a 58 dp circle of its own instead, as
///   in Google Maps.
/// - **Speeding.** By [speedingLevel], a minor alert draws the speed in
///   [GoogleStyleColors.speeding], and a major one draws it in white on
///   that colour.
/// - **Formatting.** Numbers and the unit come from [formatter].
///
/// These keys are stable test hooks: `google_style_speed_cluster`,
/// `google_style_speed_limit`, `google_style_speedometer` and
/// `google_style_speed_value`.
class GoogleStyleSpeedCluster extends StatelessWidget {
  /// Creates the speed cluster for [info].
  const GoogleStyleSpeedCluster({
    super.key,
    required this.info,
    this.style = SpeedLimitSignStyle.vienna,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.showSpeed = true,
    this.showLimit = true,
    this.speedometerVisible = true,
    this.onLimitTap,
    this.speedingMinor,
    this.speedingMajor,
  });

  /// The speed and the limit, in metres per second.
  final SpeedInfo info;

  /// How the limit sign is drawn.
  final SpeedLimitSignStyle style;

  /// Formats the speed, the limit and the unit.
  final GuidanceFormatter formatter;

  /// The words of the sign.
  final NavigationStrings strings;

  /// The colours of the group.
  final GoogleStyleColors colors;

  /// Whether the speedometer may show at all.
  final bool showSpeed;

  /// Whether the limit sign may show at all.
  final bool showLimit;

  /// Whether the driver wants the speedometer beside the sign; it shows
  /// regardless when there is no sign.
  final bool speedometerVisible;

  /// Called on a tap on the sign.
  final VoidCallback? onLimitTap;

  /// Over the limit by this much (in the formatter's unit) is a minor
  /// alert; null for 10, or 5 with an mph formatter. Keep it below
  /// [speedingMajor].
  final double? speedingMinor;

  /// Over the limit by this much is a major alert; null for 20, or 10 with
  /// an mph formatter.
  final double? speedingMajor;

  /// How far over the limit [info] is, in [formatter]'s unit (mph when its
  /// [GuidanceFormatter.speedUnit] is `mph`, else km/h). Minor from [minor]
  /// over (default 10 km/h or 5 mph), major from [major] over (default
  /// 20 km/h or 10 mph); none without a limit.
  static SpeedingLevel speedingLevel(
    SpeedInfo info,
    GuidanceFormatter formatter, {
    double? minor,
    double? major,
  }) {
    final limit = _knownLimit(info);
    if (limit == null) return SpeedingLevel.none;
    final imperial = formatter.speedUnit == 'mph';
    // The tolerance absorbs the rounding of the m/s round trip, so a speed
    // exactly at a threshold counts as reaching it.
    final over = (info.speed - limit) * (imperial ? 2.236936 : 3.6) + 1e-6;
    if (over >= (major ?? (imperial ? 10 : 20))) return SpeedingLevel.major;
    if (over >= (minor ?? (imperial ? 5 : 10))) return SpeedingLevel.minor;
    return SpeedingLevel.none;
  }

  /// The limit, or null when it is unknown or not positive.
  static double? _knownLimit(SpeedInfo info) {
    final limit = info.limit;
    return limit == null || limit <= 0 ? null : limit;
  }

  @override
  Widget build(BuildContext context) {
    final limit = showLimit ? _knownLimit(info) : null;
    final speedShown = showSpeed && (speedometerVisible || limit == null);
    if (limit == null && !speedShown) return const SizedBox.shrink();
    final level = speedingLevel(
      info,
      formatter,
      minor: speedingMinor,
      major: speedingMajor,
    );
    if (limit == null) {
      // The speedometer alone: a white circle with the speed and the unit.
      return Material(
        key: const ValueKey('google_style_speed_cluster'),
        color: colors.speedometerSurface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: _Speedometer(
          value: formatter.speedValue(info.speed),
          unit: formatter.speedUnit,
          level: level,
          colors: colors,
          circle: true,
        ),
      );
    }
    return Material(
      key: const ValueKey('google_style_speed_cluster'),
      color: colors.speedometerSurface,
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: onLimitTap != null,
              label:
                  '${strings.speedLimit} ${formatter.speedValue(limit)} '
                  '${formatter.speedUnit}',
              excludeSemantics: true,
              onTap: onLimitTap,
              child: GestureDetector(
                key: const ValueKey('google_style_speed_limit'),
                behavior: HitTestBehavior.opaque,
                onTap: onLimitTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 56,
                    minHeight: 56,
                  ),
                  child: Center(
                    child: _LimitSign(
                      value: formatter.speedValue(limit),
                      style: style,
                      speedLimit: strings.speedLimit,
                    ),
                  ),
                ),
              ),
            ),
            if (speedShown) const SizedBox(width: 4),
            if (speedShown)
              _Speedometer(
                value: formatter.speedValue(info.speed),
                unit: formatter.speedUnit,
                level: level,
                colors: colors,
              ),
          ],
        ),
      ),
    );
  }
}

class _Speedometer extends StatelessWidget {
  const _Speedometer({
    required this.value,
    required this.unit,
    required this.level,
    required this.colors,
    this.circle = false,
  });

  final String value;
  final String unit;
  final SpeedingLevel level;
  final GoogleStyleColors colors;

  /// A 58 dp circle (alone) instead of the 56 dp rounded square.
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final major = level == SpeedingLevel.major;
    final text = switch (level) {
      SpeedingLevel.major => _white,
      SpeedingLevel.minor => colors.speeding,
      SpeedingLevel.none => colors.speedometerText,
    };
    return Semantics(
      label: '$value $unit',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('google_style_speedometer'),
        width: circle ? 58 : 56,
        height: circle ? 58 : 56,
        padding: EdgeInsets.all(circle ? 10 : 6),
        decoration: BoxDecoration(
          color: major ? colors.speeding : colors.speedometerSurface,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(12),
        ),
        // Large text shrinks to fit the square.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                key: const ValueKey('google_style_speed_value'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              Text(
                unit,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: text, fontSize: 10, height: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitSign extends StatelessWidget {
  const _LimitSign({
    required this.value,
    required this.style,
    required this.speedLimit,
  });

  final String value;
  final SpeedLimitSignStyle style;
  final String speedLimit;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case SpeedLimitSignStyle.vienna:
        return Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _white,
            shape: BoxShape.circle,
            border: Border.all(color: _signRed, width: 6),
          ),
          child: SizedBox(
            width: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                softWrap: false,
                style: const TextStyle(
                  color: _black,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        );
      case SpeedLimitSignStyle.us:
        return Container(
          width: 48,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(width: 2),
          ),
          // A fixed-size sign: its text does not grow past the normal size.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    speedLimit,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _black,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      softWrap: false,
                      style: const TextStyle(
                        color: _black,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}
