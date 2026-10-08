import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The navigation arrow, pointing up. [NavigationMapFrame] turns it by the
/// vehicle's bearing minus the camera's: while the camera is heading up the
/// map turns and the arrow stays up (the direction of travel); while it is
/// north up the arrow turns to the vehicle's bearing.
class CarPuck extends StatelessWidget {
  const CarPuck({super.key, this.size = 44, this.color = defaultColor});

  static const defaultColor = Color(0xFF1A73E8);

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(size: Size.square(size), painter: _PuckPainter(color)),
    );
  }

  /// This puck (its [size] and [color]) as a PNG, [size] × [pixelRatio]
  /// pixels square. Static [toPngBytes] takes the values as parameters.
  Future<Uint8List> renderPng({double pixelRatio = 3}) =>
      toPngBytes(size: size, pixelRatio: pixelRatio, color: color);

  /// The same arrow as a PNG, for map SDKs that draw markers natively.
  /// The image is [size] × [pixelRatio] pixels square.
  static Future<Uint8List> toPngBytes({
    double size = 44,
    double pixelRatio = 3,
    Color color = defaultColor,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _PuckPainter(color).paint(canvas, Size.square(size));
    final px = (size * pixelRatio).round();
    final image = await recorder.endRecording().toImage(px, px);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

/// Renders the vehicle image of a native map marker at a pixel ratio.
typedef VehicleImageBuilder = Future<Uint8List> Function(double pixelRatio);

/// The image builder for [puck]: when it is a [CarPuck], that puck (its size
/// and colour); otherwise the default [CarPuck]. A custom widget cannot be
/// rendered off screen, so apps with one pass their own [VehicleImageBuilder]
/// to the native adapters.
VehicleImageBuilder vehicleImageFor(Widget puck) {
  final car = puck is CarPuck ? puck : const CarPuck();
  return (pixelRatio) => car.renderPng(pixelRatio: pixelRatio);
}

class _PuckPainter extends CustomPainter {
  _PuckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(c, r * 0.86, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c, r * 0.72, Paint()..color = color);
    final arrow = Path()
      ..moveTo(c.dx, c.dy - r * 0.48)
      ..lineTo(c.dx + r * 0.36, c.dy + r * 0.38)
      ..lineTo(c.dx, c.dy + r * 0.2)
      ..lineTo(c.dx - r * 0.36, c.dy + r * 0.38)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_PuckPainter old) => old.color != color;
}
