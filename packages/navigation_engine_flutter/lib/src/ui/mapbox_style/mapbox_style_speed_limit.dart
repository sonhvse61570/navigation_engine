import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import '../../flow/trip_progress.dart';
import '../navigation_strings.dart';
import '../speed_limit_sign.dart';
import 'mapbox_style_colors.dart';

/// The red of the circular limit sign's ring. A regulatory sign colour
/// deliberately does not follow the theme.
const _speedLimitSignRed = Color(0xFFD62828);

/// The current speed, with the speed limit sign beside it when the limit is
/// known. The numbers and the unit come from [formatter]
/// ([GuidanceFormatter.speedValue] and [GuidanceFormatter.speedUnit]); the
/// speed turns to the warning colour over the limit.
class MapboxStyleSpeedLimit extends StatelessWidget {
  /// Creates the speed display for [info].
  const MapboxStyleSpeedLimit({
    super.key,
    required this.info,
    this.sign = SpeedLimitSign.circular,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = MapboxStyleColors.day,
    this.showSpeed = true,
    this.showLimit = true,
  });

  /// The speed and the limit, in metres per second.
  final SpeedInfo info;

  /// How the limit sign is drawn.
  final SpeedLimitSign sign;

  /// Formats the speed, the limit and the unit.
  final GuidanceFormatter formatter;

  /// The words of the sign.
  final NavigationStrings strings;

  /// The colours of the speed tile.
  final MapboxStyleColors colors;

  /// Whether the current speed tile shows.
  final bool showSpeed;

  /// Whether the speed limit sign shows (when the limit is known).
  final bool showLimit;

  @override
  Widget build(BuildContext context) {
    final limit = showLimit ? info.limit : null;
    final textColor = info.isOverLimit ? colors.warning : colors.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (limit != null) ...[
          _LimitSign(
            value: formatter.speedValue(limit),
            sign: sign,
            speedLimit: strings.speedLimit,
          ),
          if (showSpeed) const SizedBox(width: 8),
        ],
        if (showSpeed)
          Material(
            color: colors.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 60,
              height: 56,
              child: Padding(
                padding: const EdgeInsets.all(6),
                // Large text shrinks to fit the tile.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatter.speedValue(info.speed),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        formatter.speedUnit,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LimitSign extends StatelessWidget {
  const _LimitSign({
    required this.value,
    required this.sign,
    required this.speedLimit,
  });

  /// The limit, formatted.
  final String value;
  final SpeedLimitSign sign;
  final String speedLimit;

  @override
  Widget build(BuildContext context) {
    switch (sign) {
      case SpeedLimitSign.circular:
        return Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _speedLimitSignRed, width: 6),
          ),
          child: SizedBox(
            width: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        );
      case SpeedLimitSign.rectangular:
        return Container(
          width: 48,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(width: 2),
          ),
          // The sign is a fixed-size graphic: its text does not grow past
          // the normal size, which already fills it.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1),
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
                      color: Colors.black,
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
                        color: Colors.black,
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
