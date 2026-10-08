import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

const double _fontSize = 14;
const double _paddingX = 10;
const double _paddingY = 6;
const double _radius = 8;
const Color _borderColor = Color(0x33000000);

/// Paints a rounded bubble with [text] (a route's duration, say) and returns
/// it as PNG bytes, for use as a native map marker icon.
///
/// The text is 14 logical px, weight 600, inside a 10 x 6 logical px padding
/// and a corner radius of 8. An unselected bubble is [color] with a 1 px
/// border; a selected one is [selectedColor] without a border, and its text
/// is [selectedTextColor] instead of [textColor]. The image is the logical
/// size times [pixelRatio] pixels, rounded up.
Future<Uint8List> paintRouteLabel(
  String text, {
  required bool selected,
  required double pixelRatio,
  Color selectedColor = const Color(0xFF1A73E8),
  Color color = const Color(0xFFFFFFFF),
  Color selectedTextColor = const Color(0xFFFFFFFF),
  Color textColor = const Color(0xFF202124),
}) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
        color: selected ? selectedTextColor : textColor,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = Size(
    painter.width + 2 * _paddingX,
    painter.height + 2 * _paddingY,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final bubble = RRect.fromRectAndRadius(
    Offset.zero & size,
    const Radius.circular(_radius),
  );
  canvas.drawRRect(bubble, Paint()..color = selected ? selectedColor : color);
  if (!selected) {
    // Stroked inside the bubble so the border is not clipped by the image.
    canvas.drawRRect(
      bubble.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _borderColor,
    );
  }
  painter.paint(canvas, const Offset(_paddingX, _paddingY));
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
