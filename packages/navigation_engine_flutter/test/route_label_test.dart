import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

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

  testWidgets('the colours change the picture, not its size', (tester) async {
    const red = RouteLabelColors(fill: Color(0xFFFF0000));
    final (plain, tinted) = (await tester.runAsync(() async {
      return (
        await paintRouteLabel('12 min', selected: false, pixelRatio: 1),
        await paintRouteLabel(
          '12 min',
          selected: false,
          pixelRatio: 1,
          colors: red,
        ),
      );
    }))!;
    expect(pngWidth(tinted), pngWidth(plain));
    expect(tinted, isNot(plain));
  });

  group('RouteLabelColors', () {
    test('defaults', () {
      const colors = RouteLabelColors();
      expect(colors.selectedFill, const Color(0xFF1A73E8));
      expect(colors.selectedText, const Color(0xFFFFFFFF));
      expect(colors.fill, const Color(0xFFFFFFFF));
      expect(colors.text, const Color(0xFF202124));
      expect(colors.border, const Color(0x33000000));
    });

    test('equal colours are equal and hash alike', () {
      const a = RouteLabelColors(fill: Color(0xFF123456));
      const b = RouteLabelColors(fill: Color(0xFF123456));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const RouteLabelColors()));
      expect(
        const RouteLabelColors(border: Color(0x11000000)),
        isNot(const RouteLabelColors()),
      );
    });
  });

  group('RouteLabelBubble', () {
    Widget host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

    testWidgets('an unselected bubble is a bordered fill with dark text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const RouteLabelBubble(text: '12 min', selected: false)),
      );
      final text = tester.widget<Text>(find.text('12 min'));
      expect(text.style!.color, const Color(0xFF202124));
      expect(text.style!.fontSize, 14);
      expect(text.style!.fontWeight, FontWeight.w600);
      final box =
          tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
              as BoxDecoration;
      expect(box.color, const Color(0xFFFFFFFF));
      expect(box.borderRadius, BorderRadius.circular(8));
      expect(box.border, isNotNull);
    });

    testWidgets(
      'a selected bubble has the selected colours, no visible border',
      (tester) async {
        await tester.pumpWidget(
          host(const RouteLabelBubble(text: '12 min', selected: true)),
        );
        final text = tester.widget<Text>(find.text('12 min'));
        expect(text.style!.color, const Color(0xFFFFFFFF));
        final box =
            tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
                as BoxDecoration;
        expect(box.color, const Color(0xFF1A73E8));
        expect((box.border! as Border).top.color, const Color(0xFF1A73E8));
      },
    );

    testWidgets('uses the given colours', (tester) async {
      const colors = RouteLabelColors(
        fill: Color(0xFF111111),
        text: Color(0xFF222222),
        border: Color(0xFF333333),
      );
      await tester.pumpWidget(
        host(
          const RouteLabelBubble(
            text: '5 min',
            selected: false,
            colors: colors,
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('5 min')).style!.color,
        const Color(0xFF222222),
      );
      final box =
          tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
              as BoxDecoration;
      expect(box.color, const Color(0xFF111111));
      expect((box.border! as Border).top.color, const Color(0xFF333333));
    });

    testWidgets('has the size of the painted bubble', (tester) async {
      await tester.pumpWidget(
        host(const RouteLabelBubble(text: '12 min', selected: false)),
      );
      final size = tester.getSize(find.byType(RouteLabelBubble));
      final png = (await tester.runAsync(
        () => paintRouteLabel('12 min', selected: false, pixelRatio: 1),
      ))!;
      expect(size.width, closeTo(pngWidth(png).toDouble(), 1));
    });

    testWidgets('ignores the app text scale, as the painted bubble (M5)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: host(
            const SizedBox(
              // The box a map gives the bubble: the painted bubble's width.
              width: 200,
              child: Align(
                child: RouteLabelBubble(text: '12 min', selected: false),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(RouteLabelBubble));
      final png = (await tester.runAsync(
        () => paintRouteLabel('12 min', selected: false, pixelRatio: 1),
      ))!;
      expect(size.width, closeTo(pngWidth(png).toDouble(), 1));
      final text = tester.renderObject<RenderParagraph>(find.text('12 min'));
      expect(text.didExceedMaxLines, isFalse);
      expect(
        text.size.width,
        greaterThanOrEqualTo(text.getMaxIntrinsicWidth(0) - 0.5),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
