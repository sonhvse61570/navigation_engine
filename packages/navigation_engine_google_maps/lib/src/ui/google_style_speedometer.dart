import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_strings.dart';

const _signRed = Color(0xFFD93025);

/// The current speed bubble, with the speed limit sign beside it when the
/// limit is known. The numbers and the unit come from [formatter]
/// ([GuidanceFormatter.speedValue] and [GuidanceFormatter.speedUnit]).
class GoogleStyleSpeedometer extends StatelessWidget {
  /// Creates the speedometer for [info].
  const GoogleStyleSpeedometer({
    super.key,
    required this.info,
    this.sign = SpeedLimitSign.circular,
    this.strings = const GoogleStyleStrings(),
    this.colors = GoogleStyleColors.day,
    this.formatter = const EnglishGuidanceFormatter(),
  });

  /// The speed and the limit, in metres per second.
  final SpeedInfo info;

  /// How the limit sign is drawn.
  final SpeedLimitSign sign;

  /// The words of the sign.
  final GoogleStyleStrings strings;

  /// The colours of the bubble.
  final GoogleStyleColors colors;

  /// Formats the speed, the limit and the unit.
  final GuidanceFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final limit = info.limit;
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
          const SizedBox(width: 8),
        ],
        Material(
          color: colors.surface,
          elevation: 4,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Padding(
              padding: const EdgeInsets.all(6),
              // Large text shrinks to fit the circle.
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
