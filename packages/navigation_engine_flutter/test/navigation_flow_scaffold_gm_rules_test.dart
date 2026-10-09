import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/scaffold_harness.dart';

void main() {
  final route = sampleRoute;
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> navigate(
    WidgetTester tester,
    Harness h, {
    bool moved = false,
  }) async {
    h.flow.previewRoutes([route]);
    await tester.pump();
    await h.startDriving(tester, route);
    if (moved) {
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
    }
  }

  group('recenterReplacesSpeed (D4)', () {
    scaffoldTest('the recenter takes the speed slot while shown', (
      tester,
      h,
    ) async {
      await h.mount(tester, recenterReplacesSpeed: true);
      await navigate(tester, h);
      expect(key('speed'), findsOneWidget);
      expect(key('recenter'), findsNothing);
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      expect(key('speed'), findsNothing);
      final recenter = tester.getRect(key('recenter'));
      final footer = tester.getRect(key('footer'));
      expect(recenter.left, closeTo(16, 1));
      expect(recenter.bottom, closeTo(footer.top - 16, 1));
      await tester.tap(key('recenter'));
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 550));
      expect(key('speed'), findsOneWidget);
      expect(key('recenter'), findsNothing);
    });

    scaffoldTest('off by default: the recenter stacks above the speed', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await navigate(tester, h, moved: true);
      expect(key('speed'), findsOneWidget);
      expect(
        tester.getRect(key('recenter')).bottom,
        lessThanOrEqualTo(tester.getRect(key('speed')).top),
      );
    });
  });

  group('bottom end slot (D3)', () {
    scaffoldTest('at the bottom end, 16 above the footer, only navigating', (
      tester,
      h,
    ) async {
      await h.mount(tester, bottomEnd: true);
      expect(key('bottomEnd'), findsNothing, reason: 'idle');
      h.flow.previewRoutes([route]);
      await tester.pump();
      expect(key('bottomEnd'), findsNothing, reason: 'overview');
      await h.startDriving(tester, route);
      final end = tester.getRect(key('bottomEnd'));
      final footer = tester.getRect(key('footer'));
      expect(end.right, closeTo(400 - 16, 1));
      expect(end.bottom, closeTo(footer.top - 16, 1));
    });

    scaffoldTest('never under the footer at 2x text on 360x640', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        size: const Size(360, 640),
        long: true,
        bottomEnd: true,
        textScaler: const TextScaler.linear(2),
      );
      await navigate(tester, h);
      expect(tester.takeException(), isNull);
      final end = tester.getRect(key('bottomEnd'));
      final footer = tester.getRect(key('footer'));
      expect(end.overlaps(footer), isFalse);
      expect(end.bottom, lessThanOrEqualTo(footer.top - 16 + 0.5));
    });

    // Pre-flight B4: the bottom start group and the bottom end piece do not
    // share a row too narrow for both; the bottom end piece lifts above it.
    scaffoldTest('lifts 16 above a bottom start group too wide to share the '
        'row (360x640, 2x text)', (tester, h) async {
      await h.mount(
        tester,
        size: const Size(360, 640),
        long: true,
        bottomEnd: true,
        textScaler: const TextScaler.linear(2),
      );
      await navigate(tester, h);
      expect(tester.takeException(), isNull);
      final end = tester.getRect(key('bottomEnd'));
      final speed = tester.getRect(key('speed'));
      expect(end.overlaps(speed), isFalse);
      expect(end.bottom, lessThanOrEqualTo(speed.top - 16 + 0.5));
    });
  });

  group('top end height (D2)', () {
    scaffoldTest('bounded 16 above the bottom end piece', (tester, h) async {
      await h.mount(tester, bottomEnd: true, topEndHeight: 2000);
      await navigate(tester, h);
      expect(tester.takeException(), isNull);
      final top = tester.getRect(key('topEnd'));
      final end = tester.getRect(key('bottomEnd'));
      expect(
        top.top,
        greaterThanOrEqualTo(tester.getRect(key('header')).bottom + 16 - 0.5),
      );
      expect(top.bottom, closeTo(end.top - 16, 1));
    });

    scaffoldTest('bounded 16 above the footer without a bottom end piece', (
      tester,
      h,
    ) async {
      await h.mount(tester, topEndHeight: 2000);
      await navigate(tester, h);
      expect(
        tester.getRect(key('topEnd')).bottom,
        closeTo(tester.getRect(key('footer')).top - 16, 1),
      );
    });
  });

  scaffoldTest('arrivalHeaderBuilder shows at the top only when arrived', (
    tester,
    h,
  ) async {
    await h.mount(tester, arrivalHeader: true);
    h.flow.previewRoutes([
      route,
    ], destination: const PlaceLabel(name: 'Landmark 81'));
    await tester.pump();
    expect(key('arrivalHeader'), findsNothing);
    await h.startDriving(tester, route);
    expect(key('arrivalHeader'), findsNothing);
    // The drive jumps from about 540 m to 200 m before the end: the fix
    // filter would reject it as too fast, so the session forgets its motion
    // (a teleport) first.
    h.session.resetMotion();
    await h.run(tester, 25, fixAt: (s) => h.nearEnd(route, s));
    expect(h.flow.state.value, isA<FlowArrived>());
    expect(find.text('ARRIVED Landmark 81'), findsOneWidget);
    expect(tester.getRect(key('arrivalHeader')).top, closeTo(0, 1));
    expect(key('arrival'), findsOneWidget);
  });

  scaffoldTest('map ready refreshes the overview and the alternates', (
    tester,
    h,
  ) async {
    await h.mount(tester);
    expect(h.flow.refreshes, 1);
    expect(h.flow.alternateRefreshes, 1);
  });

  group('landscape side panel (D7)', () {
    const landscape = Size(915, 412);
    const width = 915 * 0.42; // 384.3, under the 400 cap
    const areaStart = 8 + width + 8;

    scaffoldTest('header and footer in the start column, the rest in the '
        'map area', (tester, h) async {
      await h.mount(
        tester,
        size: landscape,
        landscapeSidePanel: true,
        bottomEnd: true,
        recenterReplacesSpeed: true,
      );
      await navigate(tester, h);
      expect(tester.takeException(), isNull);
      final header = tester.getRect(key('header'));
      final footer = tester.getRect(key('footer'));
      expect(header.left, closeTo(8, 0.5));
      expect(header.top, closeTo(8, 0.5));
      expect(header.right, lessThanOrEqualTo(8 + width + 0.5));
      expect(footer.left, closeTo(8, 0.5));
      expect(footer.bottom, closeTo(412 - 8, 0.5));
      final speed = tester.getRect(key('speed'));
      expect(speed.left, closeTo(areaStart + 16, 0.5));
      expect(speed.bottom, closeTo(412 - 16, 0.5));
      final topEnd = tester.getRect(key('topEnd'));
      expect(topEnd.right, closeTo(915 - 16, 0.5));
      expect(topEnd.top, closeTo(16, 0.5));
      final end = tester.getRect(key('bottomEnd'));
      expect(end.right, closeTo(915 - 16, 0.5));
      expect(end.bottom, closeTo(412 - 16, 0.5));
      expect(end.overlaps(footer), isFalse);
      expect(h.config.startOverlayWidth.value, closeTo(areaStart, 0.01));
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      final recenter = tester.getRect(key('recenter'));
      expect(recenter.left, closeTo(areaStart + 16, 0.5));
      expect(recenter.bottom, closeTo(412 - 16, 0.5));
      expect(key('speed'), findsNothing);
    });

    for (final direction in TextDirection.values) {
      scaffoldTest('the bottom end piece lifts above a bottom start group too '
          'wide to share the map area\'s row (${direction.name}, insets, 2x '
          'text)', (tester, h) async {
        const insets = FakeViewPadding(left: 47, right: 47, bottom: 21);
        tester.view
          ..padding = insets
          ..viewPadding = insets;
        await h.mount(
          tester,
          size: landscape,
          landscapeSidePanel: true,
          long: true,
          bottomEnd: true,
          textDirection: direction,
          textScaler: const TextScaler.linear(2),
        );
        await navigate(tester, h);
        expect(tester.takeException(), isNull);
        final end = tester.getRect(key('bottomEnd'));
        final speed = tester.getRect(key('speed'));
        expect(end.overlaps(speed), isFalse);
        expect(end.bottom, lessThanOrEqualTo(speed.top - 16 + 0.5));
        // Both stay inside the safe area, beside the column.
        final column = 47 + 8 + 915 * 0.42 + 8;
        if (direction == TextDirection.ltr) {
          expect(speed.left, greaterThanOrEqualTo(column - 0.5));
          expect(end.right, lessThanOrEqualTo(915 - 47 + 0.5));
        } else {
          expect(speed.right, lessThanOrEqualTo(915 - column + 0.5));
          expect(end.left, greaterThanOrEqualTo(47 - 0.5));
        }
      });
    }

    scaffoldTest('the overview panel sits in the column; the overview '
        'padding clears it', (tester, h) async {
      await h.mount(tester, size: landscape, landscapeSidePanel: true);
      h.flow.previewRoutes([route]);
      await tester.pump();
      await tester.pump();
      final panel = tester.getRect(key('panel'));
      expect(panel.left, closeTo(8, 0.5));
      expect(panel.width, closeTo(width, 0.5));
      expect(panel.bottom, closeTo(412 - 8, 0.5));
      final padding = h.flow.overviewPadding;
      expect(padding.left, closeTo(areaStart + 32, 0.01));
      expect(padding.top, closeTo(32, 0.01));
      expect(padding.right, closeTo(32, 0.01));
      expect(padding.bottom, closeTo(32, 0.01));
    });

    scaffoldTest('RTL: the column sits on the right; padding and overlay '
        'mirror', (tester, h) async {
      await h.mount(
        tester,
        size: landscape,
        landscapeSidePanel: true,
        textDirection: TextDirection.rtl,
      );
      await navigate(tester, h);
      final header = tester.getRect(key('header'));
      expect(header.right, closeTo(915 - 8, 0.5));
      expect(header.left, greaterThanOrEqualTo(915 - 8 - width - 0.5));
      final speed = tester.getRect(key('speed'));
      expect(speed.right, closeTo(915 - areaStart - 16, 0.5));
      expect(tester.getRect(key('topEnd')).left, closeTo(16, 0.5));
      final padding = h.flow.overviewPadding;
      expect(padding.right, closeTo(areaStart + 32, 0.01));
      expect(padding.left, closeTo(32, 0.01));
      expect(h.config.startOverlayWidth.value, closeTo(areaStart, 0.01));
    });

    scaffoldTest('insets: the column and the map area keep inside the safe '
        'area', (tester, h) async {
      const insets = FakeViewPadding(left: 47, right: 47, bottom: 21);
      tester.view
        ..padding = insets
        ..viewPadding = insets;
      await h.mount(
        tester,
        size: const Size(844, 390),
        landscapeSidePanel: true,
        bottomEnd: true,
      );
      await navigate(tester, h);
      expect(tester.takeException(), isNull);
      const w = 844 * 0.42;
      const start = 47 + 8 + w + 8;
      expect(tester.getRect(key('header')).left, closeTo(47 + 8, 0.5));
      expect(tester.getRect(key('footer')).bottom, closeTo(390 - 21 - 8, 0.5));
      expect(tester.getRect(key('speed')).left, closeTo(start + 16, 0.5));
      expect(tester.getRect(key('topEnd')).right, closeTo(844 - 47 - 16, 0.5));
      expect(
        tester.getRect(key('bottomEnd')).bottom,
        closeTo(390 - 21 - 16, 0.5),
      );
      expect(h.config.startOverlayWidth.value, closeTo(start, 0.01));
    });

    scaffoldTest('arrived: the arrival header and the arrival in the '
        'column', (tester, h) async {
      await h.mount(
        tester,
        size: landscape,
        landscapeSidePanel: true,
        arrivalHeader: true,
      );
      h.flow.previewRoutes([route]);
      await tester.pump();
      await h.startDriving(tester, route);
      // The drive jumps from about 540 m to 200 m before the end: the fix
      // filter would reject it as too fast, so the session forgets its motion
      // (a teleport) first.
      h.session.resetMotion();
      await h.run(tester, 25, fixAt: (s) => h.nearEnd(route, s));
      expect(h.flow.state.value, isA<FlowArrived>());
      final header = tester.getRect(key('arrivalHeader'));
      final arrival = tester.getRect(key('arrival'));
      expect(header.left, closeTo(8, 0.5));
      expect(header.top, closeTo(8, 0.5));
      expect(arrival.left, closeTo(8, 0.5));
      expect(arrival.bottom, closeTo(412 - 8, 0.5));
    });

    // Final fix wave, M1: the map keeps its logo (at the bottom start of
    // the map area) above the speed or the recenter button there.
    scaffoldTest('the bottom overlay is the bottom start group\'s height in '
        'the map area', (tester, h) async {
      await h.mount(
        tester,
        size: landscape,
        landscapeSidePanel: true,
        recenterReplacesSpeed: true,
      );
      await navigate(tester, h);
      await tester.pump(const Duration(milliseconds: 16));
      final height = h.config.bottomOverlayHeight;
      final speed = tester.getRect(key('speed'));
      expect(height.value, closeTo(412 - speed.top, 0.5), reason: 'speed');
      h.session.follow = false;
      await h.run(tester, 0.1, fixAt: (_) => h.fixOn(route, 545));
      await tester.pump(const Duration(milliseconds: 16));
      expect(key('speed'), findsNothing);
      final recenter = tester.getRect(key('recenter'));
      expect(
        height.value,
        closeTo(412 - recenter.top, 0.5),
        reason: 'the recenter button in the speed\'s place',
      );
    });

    scaffoldTest('the bottom overlay counts the recenter stacked above the '
        'speed', (tester, h) async {
      await h.mount(tester, size: landscape, landscapeSidePanel: true);
      await navigate(tester, h, moved: true);
      await tester.pump(const Duration(milliseconds: 16));
      final recenter = tester.getRect(key('recenter'));
      final speed = tester.getRect(key('speed'));
      expect(recenter.bottom, lessThanOrEqualTo(speed.top));
      expect(
        h.config.bottomOverlayHeight.value,
        closeTo(412 - recenter.top, 0.5),
      );
    });

    // Final fix wave, T13-7: a footer that grows (an expanded menu) may take
    // the room a header leaves empty, beyond the column's 60 % share.
    scaffoldTest('the footer takes at most 60 % of the column beside a '
        'header, and the room an empty header leaves', (tester, h) async {
      h
        ..headerHeight = 160
        ..footerHeight = 330;
      await h.mount(tester, size: landscape, landscapeSidePanel: true);
      await navigate(tester, h);
      await tester.pump(const Duration(milliseconds: 16));
      const available = 412 - 2 * 8.0;
      // The footer's column scrolls inside its cap.
      Rect column() => tester.getRect(
        find
            .ancestor(of: key('footer'), matching: find.byType(ConstrainedBox))
            .first,
      );
      expect(column().height, closeTo(available * 0.6, 0.5));
      h.headerHeight = 0;
      await h.run(tester, 1.2, fixAt: (s) => h.fixOn(route, 560.0 + 10 * s));
      await tester.pump(const Duration(milliseconds: 16));
      expect(column().height, closeTo(330, 0.5));
      expect(tester.takeException(), isNull);
    });

    // Review fix round 1: idle shows nothing in the column, so nothing
    // covers the start of the map.
    scaffoldTest('the start overlay is 0 while idle, the column while '
        'navigating', (tester, h) async {
      await h.mount(tester, size: landscape, landscapeSidePanel: true);
      await tester.pump();
      expect(h.flow.state.value, isA<FlowIdle>());
      expect(h.config.startOverlayWidth.value, 0);
      await navigate(tester, h);
      expect(h.config.startOverlayWidth.value, closeTo(areaStart, 0.01));
    });

    scaffoldTest('off by default: landscape keeps the portrait layout', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: landscape);
      await navigate(tester, h);
      expect(tester.getRect(key('header')).left, closeTo(0, 0.5));
      expect(h.config.startOverlayWidth.value, 0);
      expect(
        tester.getRect(key('topEnd')).top,
        greaterThanOrEqualTo(tester.getRect(key('header')).bottom),
      );
    });

    scaffoldTest('below 600 dp wide, landscape keeps the portrait layout', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        size: const Size(590, 360),
        landscapeSidePanel: true,
      );
      await navigate(tester, h);
      expect(tester.getRect(key('header')).left, closeTo(0, 0.5));
      expect(h.config.startOverlayWidth.value, 0);
    });
  });
}
