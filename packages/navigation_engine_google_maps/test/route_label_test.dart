import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

/// The width of a PNG, from its IHDR chunk.
int pngWidth(Uint8List png) => ByteData.sublistView(png).getUint32(16);

void main() {
  testWidgets('paints a PNG', (tester) async {
    final png = (await tester.runAsync(
      () => paintRouteLabel('12 min', selected: false, pixelRatio: 1),
    ))!;
    expect(png.sublist(0, 4), [137, 80, 78, 71]);
  });

  testWidgets('the image size follows the pixel ratio', (tester) async {
    final (one, two) = (await tester.runAsync(() async {
      return (
        await paintRouteLabel('12 min', selected: true, pixelRatio: 1),
        await paintRouteLabel('12 min', selected: true, pixelRatio: 2),
      );
    }))!;
    expect(pngWidth(two), closeTo(pngWidth(one) * 2, 2));
  });

  testWidgets('a longer text gives a wider image', (tester) async {
    final (short, long) = (await tester.runAsync(() async {
      return (
        await paintRouteLabel('5 min', selected: false, pixelRatio: 2),
        await paintRouteLabel('1 h 25 min', selected: false, pixelRatio: 2),
      );
    }))!;
    expect(pngWidth(long), greaterThan(pngWidth(short)));
  });
}
