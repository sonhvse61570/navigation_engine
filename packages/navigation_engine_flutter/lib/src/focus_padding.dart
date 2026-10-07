import 'package:flutter/widgets.dart';

/// The padding that moves a map's camera centre to [focus] of [size]'s
/// height (0 = top, 1 = bottom), e.g. 0.7 to show more road ahead of a
/// vehicle drawn low on the screen.
///
/// Map SDKs centre the camera in the padded viewport, so a top inset of
/// `(2 * focus - 1) * height` puts the centre at `focus * height`.
EdgeInsets focusPadding(Size size, double focus) {
  final f = focus.clamp(0.0, 1.0);
  final h = size.height;
  return EdgeInsets.only(
    top: f > 0.5 ? (2 * f - 1) * h : 0,
    bottom: f < 0.5 ? (1 - 2 * f) * h : 0,
  );
}
