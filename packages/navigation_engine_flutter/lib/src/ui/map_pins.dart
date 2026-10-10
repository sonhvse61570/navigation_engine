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
}) {
  final scale = focused ? 1.3 : 1.0;
  return _paintPin(
    width: 28 * scale,
    height: 36 * scale,
    pixelRatio: pixelRatio,
    color: color,
    inside: (canvas, centre, r) => canvas.drawCircle(
      centre,
      r * 0.35,
      Paint()..color = const Color(0xFFFFFFFF),
    ),
  );
}

/// Paints the trip's destination pin and returns it as PNG bytes, for a
/// native marker icon. Every map adapter draws this one marker, so the
/// destination looks the same on any map: a teardrop in [color] (a red by
/// default) with a 2 px white outline (wholly inside the image), and in its
/// head a white ring around a dark centre (the colour darkened), 32×42
/// logical px, the tip at the bottom centre. Anchor it at the bottom
/// centre. The image is the logical size times [pixelRatio], rounded up.
Future<Uint8List> paintDestinationPin({
  required double pixelRatio,
  Color color = const Color(0xFFE53935),
}) => _paintPin(
  width: 32,
  height: 42,
  pixelRatio: pixelRatio,
  color: color,
  inside: (canvas, centre, r) => canvas
    ..drawCircle(centre, r * 0.45, Paint()..color = const Color(0xFFFFFFFF))
    ..drawCircle(
      centre,
      r * 0.22,
      Paint()..color = Color.lerp(color, const Color(0xFF000000), 0.45)!,
    ),
);

/// A teardrop [width]×[height] logical px in [color] with a 2 px white
/// outline, its head's content painted by [inside] (given the head's centre
/// and radius), as PNG bytes at [pixelRatio].
Future<Uint8List> _paintPin({
  required double width,
  required double height,
  required double pixelRatio,
  required Color color,
  required void Function(Canvas canvas, Offset centre, double radius) inside,
}) async {
  final w = width;
  final h = height;
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
    );
  inside(canvas, centre, r);
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
