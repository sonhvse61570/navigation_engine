import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

class _Fixes implements FixSource {
  final _controller = StreamController<NavFix>.broadcast();
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => false;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
}

void main() {
  test('the default horizontal focus adds no side padding', () {
    final p = focusPadding(const Size(800, 400), 0.7);
    expect(p.top, closeTo(160, 1e-9));
    expect(p.left, 0);
    expect(p.right, 0);
  });

  test('a focus right of centre pads the left, left of centre the right', () {
    final right = focusPadding(const Size(800, 400), 0.5, horizontal: 0.7);
    expect(right.left, closeTo(320, 1e-9));
    expect(right.right, 0);
    expect(right.top, 0);
    expect(right.bottom, 0);
    final left = focusPadding(const Size(800, 400), 0.5, horizontal: 0.25);
    expect(left.right, closeTo(400, 1e-9));
    expect(left.left, 0);
    expect(
      focusPadding(const Size(800, 400), 0.5, horizontal: 2).left,
      closeTo(800, 1e-9),
      reason: 'clamped to 1',
    );
  });

  testWidgets('NavigationMapFrame puts the puck at the horizontal focus', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = NavigationSession(fixes: _Fixes());
    EdgeInsets? padding;
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMapFrame(
          session: session,
          focus: 0.5,
          horizontalFocus: 0.7,
          puck: const SizedBox(key: ValueKey('puck'), width: 10, height: 10),
          mapBuilder: (context, p) {
            padding = p;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('puck'))).dx,
      closeTo(560, 0.5),
    );
    expect(padding!.left, closeTo(320, 1e-9));
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
