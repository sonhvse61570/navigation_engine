import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The text size of a route label, in logical px.
const double routeLabelFontSize = 14;

/// The horizontal padding of a route label, in logical px.
const double routeLabelPaddingX = 10;

/// The vertical padding of a route label, in logical px.
const double routeLabelPaddingY = 6;

/// The corner radius of a route label, in logical px.
const double routeLabelRadius = 8;

/// Colours of a route duration label.
final class RouteLabelColors {
  /// Creates a set of label colours. The defaults are a blue selected
  /// bubble and a white one with dark text.
  const RouteLabelColors({
    this.selectedFill = const Color(0xFF1A73E8),
    this.selectedText = const Color(0xFFFFFFFF),
    this.fill = const Color(0xFFFFFFFF),
    this.text = const Color(0xFF202124),
    this.border = const Color(0x33000000),
  });

  /// The background of the selected route's label.
  final Color selectedFill;

  /// The text colour of the selected route's label.
  final Color selectedText;

  /// The background of the labels of the other routes.
  final Color fill;

  /// The text colour of the labels of the other routes.
  final Color text;

  /// The 1 px border of the labels of the other routes. The selected label
  /// has none.
  final Color border;

  @override
  bool operator ==(Object other) =>
      other is RouteLabelColors &&
      other.selectedFill == selectedFill &&
      other.selectedText == selectedText &&
      other.fill == fill &&
      other.text == text &&
      other.border == border;

  @override
  int get hashCode =>
      Object.hash(selectedFill, selectedText, fill, text, border);
}

/// Paints a rounded bubble with [text] (a route's duration, say) and returns
/// it as PNG bytes, for use as a native map marker icon.
///
/// The text is 14 logical px, weight 600, inside a 10 x 6 logical px padding
/// and a corner radius of 8. An unselected bubble is [RouteLabelColors.fill]
/// with a 1 px [RouteLabelColors.border]; a selected one is
/// [RouteLabelColors.selectedFill] without a border, and its text is
/// [RouteLabelColors.selectedText] instead of [RouteLabelColors.text]. The
/// image is the logical size times [pixelRatio] pixels, rounded up.
Future<Uint8List> paintRouteLabel(
  String text, {
  required bool selected,
  required double pixelRatio,
  RouteLabelColors colors = const RouteLabelColors(),
}) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: routeLabelFontSize,
        fontWeight: FontWeight.w600,
        color: selected ? colors.selectedText : colors.text,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = Size(
    painter.width + 2 * routeLabelPaddingX,
    painter.height + 2 * routeLabelPaddingY,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final bubble = RRect.fromRectAndRadius(
    Offset.zero & size,
    const Radius.circular(routeLabelRadius),
  );
  canvas.drawRRect(
    bubble,
    Paint()..color = selected ? colors.selectedFill : colors.fill,
  );
  if (!selected) {
    // Stroked inside the bubble so the border is not clipped by the image.
    canvas.drawRRect(
      bubble.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.border,
    );
  }
  painter.paint(canvas, const Offset(routeLabelPaddingX, routeLabelPaddingY));
  painter.dispose();

  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
  } finally {
    picture.dispose();
  }
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
