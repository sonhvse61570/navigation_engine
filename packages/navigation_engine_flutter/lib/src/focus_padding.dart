import 'package:flutter/widgets.dart';

/// The padding that moves a map's camera centre to [focus] of [size]'s
/// height (0 = top, 1 = bottom) and [horizontal] of its width (0 = left,
/// 1 = right; 0.5 is the centre), e.g. a focus of 0.7 to show more road
/// ahead of a vehicle drawn low on the screen.
///
/// Map SDKs centre the camera in the padded viewport, so a top inset of
/// `(2 * focus - 1) * height` puts the centre at `focus * height`, and a
/// left inset of `(2 * horizontal - 1) * width` puts it at
/// `horizontal * width`.
EdgeInsets focusPadding(Size size, double focus, {double horizontal = 0.5}) {
  final f = focus.clamp(0.0, 1.0);
  final x = horizontal.clamp(0.0, 1.0);
  final h = size.height;
  final w = size.width;
  return EdgeInsets.only(
    top: f > 0.5 ? (2 * f - 1) * h : 0,
    bottom: f < 0.5 ? (1 - 2 * f) * h : 0,
    left: x > 0.5 ? (2 * x - 1) * w : 0,
    right: x < 0.5 ? (1 - 2 * x) * w : 0,
  );
}
