// The "Then" rule and trip sheet drag wave: the sheet follows the finger,
// settles with a spring, and the floating controls fade with it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

const _centre = ValueKey('google_style_trip_sheet_centre');
const _handle = ValueKey('google_style_trip_sheet_handle');
const _header = ValueKey('google_style_header_card');

/// The opacity [finder] paints with: the product of its [Opacity]
/// ancestors'.
double _opacityOf(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    opacity *= o.opacity;
  }
  return opacity;
}

double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(GoogleStyleTripSheet)).height;

/// The trip sheet's collapsed and expanded heights, read by opening and
/// closing it with taps.
Future<(double, double)> _extremes(WidgetTester tester, DropInHarness h) async {
  final collapsed = _sheetHeight(tester);
  await tester.tap(find.byKey(_centre));
  await h.settle(tester);
  final expanded = _sheetHeight(tester);
  await tester.tap(find.byKey(_centre));
  await h.settle(tester);
  expect(_sheetHeight(tester), collapsed);
  return (collapsed, expanded);
}

void main() {
  group('the floating controls fade with the sheet', () {
    final floating = {
      'stack': find.byType(GoogleStyleControlStack),
      'speed': find.byType(GoogleStyleSpeedCluster),
      'report': find.byType(GoogleStyleReportButton),
    };

    dropInTest('they fade and ignore pointers while it moves, go when it is '
        'open, and come back as it closes', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      final (collapsed, expanded) = await _extremes(tester, h);
      final span = expanded - collapsed;
      for (final MapEntry(key: name, value: f) in floating.entries) {
        expect(_opacityOf(tester, f), 1, reason: name);
        expect(f.hitTestable(), findsOneWidget, reason: name);
      }

      // Half way up, held.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(Offset(0, -span / 2));
      await h.frames(tester);
      expect(_sheetHeight(tester), closeTo(collapsed + span / 2, 1));
      for (final MapEntry(key: name, value: f) in floating.entries) {
        expect(f, findsOneWidget, reason: '$name fading');
        expect(_opacityOf(tester, f), closeTo(0.5, 0.01), reason: name);
        expect(f.hitTestable(), findsNothing, reason: '$name ignores taps');
      }
      await gesture.moveBy(Offset(0, -span));
      await gesture.up();
      await h.settle(tester);
      for (final MapEntry(key: name, value: f) in floating.entries) {
        expect(f, findsNothing, reason: '$name while open');
      }

      // A quarter of the way down, held: back, faint, still ignoring.
      final down = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await down.moveBy(Offset(0, span / 4));
      await h.frames(tester);
      for (final MapEntry(key: name, value: f) in floating.entries) {
        expect(_opacityOf(tester, f), closeTo(0.25, 0.01), reason: name);
        expect(f.hitTestable(), findsNothing, reason: name);
      }
      await down.moveBy(Offset(0, span));
      await down.up();
      await h.settle(tester);
      for (final MapEntry(key: name, value: f) in floating.entries) {
        expect(_opacityOf(tester, f), 1, reason: '$name after collapse');
        expect(f.hitTestable(), findsOneWidget, reason: name);
      }
    });

    dropInTest('Re-center fades too', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester);
      h.session.follow = false;
      await h.frames(tester);
      final recenter = find.byType(GoogleStyleRecenterButton);
      expect(recenter.hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(_centre));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final opacity = _opacityOf(tester, recenter);
      expect(opacity, inExclusiveRange(0, 1));
      expect(recenter.hitTestable(), findsNothing);
      await h.settle(tester);
      expect(recenter, findsNothing);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(recenter.hitTestable(), findsOneWidget);
    });
  });

  group('the floating controls fade in place', () {
    /// The end column's members and the speed cluster, by name, with their
    /// rects on screen; members off stage (hidden) are left out.
    Map<String, Rect> layout(WidgetTester tester, NavigationStrings strings) {
      final stack = find.byType(GoogleStyleControlStack);
      final out = <String, Rect>{};
      for (final (name, finder) in [
        ('report', find.byType(GoogleStyleReportButton)),
        ('compass', find.byType(GoogleStyleCompassButton)),
        ('search', find.byTooltip(strings.searchAlongRoute)),
        ('sound', find.byType(GoogleStyleSoundButton)),
        ('route options', find.byTooltip(strings.routeOptions)),
      ]) {
        final member = find.descendant(of: stack, matching: finder);
        if (member.evaluate().isNotEmpty) {
          out[name] = tester.getRect(member.first);
        }
      }
      final speed = find.byType(GoogleStyleSpeedCluster);
      if (speed.evaluate().isNotEmpty) out['speed'] = tester.getRect(speed);
      return out;
    }

    for (final (size, scale) in [
      (const Size(412, 915), 1.0),
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
    ]) {
      dropInTest('$size at ${scale}x: closing, the members and their rects '
          'stay as collapsed until t = 0; only the opacity changes', (
        tester,
        h,
      ) async {
        await h.mount(tester, size: size, scale: scale);
        await h.drive(tester);
        // The Report pill collapses to a circle by itself after 5 s: let it,
        // so only the sheet changes the layout below.
        await h.run(tester, 3);
        await h.settle(tester);
        final collapsed = layout(tester, h.strings);
        expect(collapsed.keys, contains('speed'));
        expect(collapsed.keys, contains('route options'));
        await tester.tap(find.byKey(_centre));
        await h.settle(tester);
        await tester.tap(find.byKey(_centre));
        await tester.pump();
        final stack = find.byType(GoogleStyleControlStack);
        final opacities = <double>[];
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (stack.evaluate().isEmpty) continue; // still t = 1
          final opacity = _opacityOf(tester, stack);
          opacities.add(opacity);
          final now = layout(tester, h.strings);
          expect(now.keys.toSet(), collapsed.keys.toSet(), reason: 'f$i');
          for (final MapEntry(key: name, value: rect) in collapsed.entries) {
            expect(now[name], rect, reason: '$name, frame $i ($opacity)');
          }
        }
        expect(opacities.length, greaterThan(5));
        expect(opacities.first, lessThan(0.5));
        expect(opacities.last, 1);
        for (var i = 1; i < opacities.length; i++) {
          expect(opacities[i], greaterThanOrEqualTo(opacities[i - 1]));
        }
      });
    }

    dropInTest('opening, they stay put under the rising sheet', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      await h.run(tester, 3);
      await h.settle(tester);
      final collapsed = layout(tester, h.strings);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await h.frames(tester);
        expect(layout(tester, h.strings), collapsed, reason: 'step $i');
      }
      await gesture.up();
      await h.settle(tester);
    });

    dropInTest('an open sound pill closes as the sheet leaves collapsed; the '
        'sound button stays a member', (tester, h) async {
      await h.mount(tester, size: const Size(412, 915));
      await h.drive(tester);
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await tester.pump();
      const pill = ValueKey('google_style_sound_pill');
      expect(find.byKey(pill), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(const Offset(0, -40));
      await h.frames(tester);
      expect(find.byKey(pill), findsNothing);
      expect(find.byType(GoogleStyleSoundButton), findsOneWidget);
      await gesture.up();
      await h.settle(tester);
      expect(find.byKey(pill), findsNothing);
    });
  });

  group('the drop-in sheet', () {
    dropInTest('the system back closes the expanded sheet, animated', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      final (collapsed, expanded) = await _extremes(tester, h);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_sheetHeight(tester), inExclusiveRange(collapsed, expanded));
      await h.settle(tester);
      expect(_sheetHeight(tester), collapsed);
      expect(find.byType(GoogleStyleNavigation), findsOneWidget);
      expect(find.byKey(_header), findsOneWidget);
    });

    dropInTest('landscape side panel: a partial drag grows the floating '
        'sheet upwards inside the panel; the header gives way', (
      tester,
      h,
    ) async {
      await h.mount(tester, size: const Size(915, 412));
      await h.drive(tester);
      expect(find.byKey(_header), findsOneWidget);
      final before = tester.getRect(find.byType(GoogleStyleTripSheet));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handle)),
      );
      await gesture.moveBy(const Offset(0, -60));
      await h.frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_header), findsNothing);
      final during = tester.getRect(find.byType(GoogleStyleTripSheet));
      expect(during.bottom, closeTo(before.bottom, 0.5));
      expect(during.top, closeTo(before.top - 60, 1));
      await gesture.moveBy(const Offset(0, -200));
      await gesture.up();
      await h.settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(h.strings.directions), findsOneWidget);
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(find.byKey(_header), findsOneWidget, reason: 'back on close');
    });

    for (final (name, size) in [
      ('portrait', const Size(412, 915)),
      ('side panel', const Size(915, 412)),
    ]) {
      dropInTest('$name: the map focus, its padding and overviewPadding hold '
          'while the sheet is dragged, settles and stays open', (
        tester,
        h,
      ) async {
        await h.mount(tester, size: size);
        await h.drive(tester);
        final (collapsed, expanded) = await _extremes(tester, h);
        await h.settle(tester);
        final span = expanded - collapsed;
        final view = find.byType(GoogleMapsNavigationView);
        final overlay = tester
            .widget<GoogleMapsNavigationView>(view)
            .bottomOverlay;
        final padding = h.map.mapPadding;
        final platformPadding = h.platform.mapConfiguration.padding;
        final overview = h.flow.overviewPadding;
        void unchanged(String when) {
          expect(
            tester.widget<GoogleMapsNavigationView>(view).bottomOverlay,
            overlay,
            reason: 'bottomOverlay $when',
          );
          expect(h.map.mapPadding, padding, reason: 'focus padding $when');
          expect(
            h.platform.mapConfiguration.padding,
            platformPadding,
            reason: 'platform padding $when',
          );
          expect(h.flow.overviewPadding, overview, reason: 'overview $when');
        }

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_handle)),
        );
        for (var i = 1; i <= 6; i++) {
          await gesture.moveBy(Offset(0, -span / 10));
          await h.frames(tester);
          unchanged('at t = ${i / 10}');
        }
        expect(_sheetHeight(tester), closeTo(collapsed + span * 0.6, 1));
        await gesture.up();
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          unchanged('settling, frame $i');
        }
        expect(_sheetHeight(tester), expanded);
        await h.frames(tester);
        unchanged('open');
        // Closed again: the same values, without a blip on the way.
        await tester.tap(find.byKey(_centre));
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          unchanged('closing, frame $i');
        }
        expect(_sheetHeight(tester), collapsed);
      });
    }

    for (final (size, scale, direction) in [
      (const Size(360, 640), 2.0, TextDirection.ltr),
      (const Size(412, 915), 1.3, TextDirection.rtl),
      (const Size(915, 412), 1.0, TextDirection.ltr),
      (const Size(844, 390), 2.0, TextDirection.rtl),
    ]) {
      dropInTest('$size at ${scale}x (${direction.name}): no overflow with '
          'the sheet half dragged', (tester, h) async {
        await h.mount(tester, size: size, scale: scale, direction: direction);
        await h.drive(tester);
        final (collapsed, expanded) = await _extremes(tester, h);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_handle)),
        );
        await gesture.moveBy(Offset(0, -(expanded - collapsed) / 2));
        await h.frames(tester);
        expect(tester.takeException(), isNull);
        expect(_sheetHeight(tester), inExclusiveRange(collapsed, expanded));
        await gesture.up();
        await h.settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
