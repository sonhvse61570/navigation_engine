import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Paints a map pin for a search result and returns it as PNG bytes, for a
/// native marker icon: a teardrop in [color] with a 2 px white outline
/// (wholly inside the image) and a white dot, 28×36 logical px (1.3 times
/// that when [focused]), the tip at the bottom centre. The image is the
/// logical size times [pixelRatio], rounded up.
Future<Uint8List> paintSearchPin({
  required bool focused,
  required double pixelRatio,
  required Color color,
}) async {
  final scale = focused ? 1.3 : 1.0;
  final w = 28 * scale;
  final h = 36 * scale;
  // The outline is centred on the path: the path keeps half its width from
  // the image's edges, so the whole outline shows.
  const stroke = 2.0;
  const inset = stroke / 2;
  final pinW = w - 2 * inset;
  final pinH = h - 2 * inset;
  final r = pinW / 2;
  final centre = Offset(w / 2, inset + r);
  Offset at(double x, double y) => Offset(inset + x * pinW, inset + y * pinH);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final tip = at(0.5, 1);
  final pin = Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(at(0.1, 0.62).dx, at(0.1, 0.62).dy, inset, centre.dy)
    ..arcTo(Rect.fromCircle(center: centre, radius: r), math.pi, math.pi, false)
    ..quadraticBezierTo(at(0.9, 0.62).dx, at(0.9, 0.62).dy, tip.dx, tip.dy)
    ..close();
  canvas
    ..drawPath(pin, Paint()..color = color)
    ..drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFFFFFFFF),
    )
    ..drawCircle(centre, r * 0.35, Paint()..color = const Color(0xFFFFFFFF));
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(
      (w * pixelRatio).ceil(),
      (h * pixelRatio).ceil(),
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
