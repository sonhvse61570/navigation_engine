import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

int pngWidth(Uint8List png) =>
    ByteData.sublistView(png).getUint32(16); // IHDR width

void main() {
  group('CarPuck images', () {
    testWidgets('renderPng uses the puck size and the pixel ratio', (
      tester,
    ) async {
      final png = (await tester.runAsync(
        () => const CarPuck(size: 30).renderPng(pixelRatio: 2),
      ))!;
      expect(pngWidth(png), 60);
    });

    testWidgets('the static toPngBytes keeps working', (tester) async {
      final png = (await tester.runAsync(
        () => CarPuck.toPngBytes(size: 20, pixelRatio: 2),
      ))!;
      expect(pngWidth(png), 40);
    });

    testWidgets('vehicleImageFor renders a CarPuck with its own size', (
      tester,
    ) async {
      final VehicleImageBuilder build = vehicleImageFor(
        const CarPuck(size: 30, color: Color(0xFFFF0000)),
      );
      final png = (await tester.runAsync(() => build(3)))!;
      expect(pngWidth(png), 90);
    });

    testWidgets('vehicleImageFor falls back to the default CarPuck', (
      tester,
    ) async {
      final png = (await tester.runAsync(
        () => vehicleImageFor(const SizedBox())(2),
      ))!;
      expect(pngWidth(png), 88);
    });

    testWidgets('vehicleImageFor honours the colour', (tester) async {
      final red = (await tester.runAsync(
        () => vehicleImageFor(const CarPuck(color: Color(0xFFFF0000)))(1),
      ))!;
      final blue = (await tester.runAsync(
        () => vehicleImageFor(const CarPuck())(1),
      ))!;
      expect(red, isNot(equals(blue)));
    });
  });
}
