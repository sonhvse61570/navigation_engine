import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/drop_in_harness.dart';

typedef _Case = ({
  Size size,
  FakeViewPadding? insets,
  double scale,
  TextDirection direction,
  bool vietnamese,
});

const _header = ValueKey('google_style_header_card');
const _centre = ValueKey('google_style_trip_sheet_centre');

/// [finder]'s rect, clipped to the scroll view it sits in (the side panel's
/// cards scroll when they do not fit).
Rect _visible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final scroll = find.ancestor(
    of: finder,
    matching: find.byType(SingleChildScrollView),
  );
  return scroll.evaluate().isEmpty
      ? rect
      : rect.intersect(tester.getRect(scroll.first));
}

/// The content of the bottom sheet [sheet]: what its [SafeArea] lays out
/// inside the insets. The sheet's surface reaches the screen's bottom edge
/// (as in the Google Maps app; the trip sheet and drop-in safe-area tests
/// assert it), so the safe area is checked on the content.
Rect _sheetContent(WidgetTester tester, Finder sheet) {
  final safeArea = find
      .descendant(of: sheet, matching: find.byType(SafeArea))
      .first;
  // SafeArea pads a MediaQuery.removePadding; its child is the content.
  return _visible(
    tester,
    find.descendant(of: safeArea, matching: find.byType(MediaQuery)).first,
  );
}

void main() {
  const landscapeInsets = FakeViewPadding(left: 47, right: 47, bottom: 21);
  const portraitInsets = FakeViewPadding(top: 24, bottom: 34);
  final cases = <_Case>[
    for (final size in const [Size(915, 412), Size(844, 390)])
      for (final insets in [null, landscapeInsets])
        for (final scale in const [1.3, 2.0])
          for (final direction in TextDirection.values)
            (
              size: size,
              insets: insets,
              scale: scale,
              direction: direction,
              vietnamese: direction == TextDirection.rtl,
            ),
    for (final size in const [Size(360, 640), Size(412, 915)])
      for (final insets in [null, portraitInsets])
        for (final scale in const [1.0, 2.0])
          (
            size: size,
            insets: insets,
            scale: scale,
            direction: TextDirection.ltr,
            vietnamese: scale == 2.0,
          ),
    // Spec §4 also names 1.3x in portrait, 1.0x in landscape and RTL in
    // portrait: one size each.
    (
      size: const Size(412, 915),
      insets: null,
      scale: 1.3,
      direction: TextDirection.ltr,
      vietnamese: false,
    ),
    (
      size: const Size(915, 412),
      insets: null,
      scale: 1.0,
      direction: TextDirection.ltr,
      vietnamese: false,
    ),
    (
      size: const Size(412, 915),
      insets: portraitInsets,
      scale: 1.0,
      direction: TextDirection.rtl,
      vietnamese: true,
    ),
  ];

  for (final c in cases) {
    final name =
        '${c.size.width.toInt()}x${c.size.height.toInt()}'
        '${c.insets == null ? '' : ' with insets'} ${c.scale}x '
        '${c.direction.name}${c.vietnamese ? ' vi' : ''}';
    dropInTest('layout $name', (tester, h) async {
      await h.mount(
        tester,
        size: c.size,
        insets: c.insets,
        scale: c.scale,
        direction: c.direction,
        strings: c.vietnamese
            ? const NavigationStrings.vietnamese()
            : const NavigationStrings(),
      );
      final insets = c.insets;
      final safe = Rect.fromLTRB(
        insets?.left ?? 0,
        insets?.top ?? 0,
        c.size.width - (insets?.right ?? 0),
        c.size.height - (insets?.bottom ?? 0),
      );
      bool inside(Rect r) =>
          r.left >= safe.left - 0.5 &&
          r.top >= safe.top - 0.5 &&
          r.right <= safe.right + 0.5 &&
          r.bottom <= safe.bottom + 0.5;
      // A bottom sheet's surface: inside the safe area, except that it may
      // reach down under the bottom inset to the screen's edge.
      bool surfaceInside(Rect r) =>
          r.left >= safe.left - 0.5 &&
          r.top >= safe.top - 0.5 &&
          r.right <= safe.right + 0.5 &&
          r.bottom <= c.size.height + 0.5;
      final side = NavigationFlowScaffold.usesSidePanel(c.size);
      final ltr = c.direction == TextDirection.ltr;
      final panel = NavigationFlowScaffold.sidePanelWidth(c.size);
      // The side panel's far edge, on the start side.
      final panelEdge = ltr
          ? safe.left + 8 + panel + 0.5
          : safe.right - 8 - panel - 0.5;
      bool inPanel(Rect r) => ltr ? r.right <= panelEdge : r.left >= panelEdge;
      bool inMapArea(Rect r) =>
          ltr ? r.left >= panelEdge : r.right <= panelEdge;

      void check({required bool moved}) {
        final header = _visible(tester, find.byKey(_header));
        final sheet = _visible(tester, find.byType(GoogleStyleTripSheet));
        final report = tester.getRect(find.byType(GoogleStyleReportButton));
        for (final (piece, rect) in [
          ('header', header),
          (
            'sheet content',
            _sheetContent(tester, find.byType(GoogleStyleTripSheet)),
          ),
          ('report', report),
        ]) {
          expect(inside(rect), isTrue, reason: '$piece $rect in $safe');
        }
        expect(surfaceInside(sheet), isTrue, reason: 'sheet $sheet in $safe');
        expect(report.overlaps(sheet), isFalse, reason: 'report $report');
        expect(report.shortestSide, greaterThanOrEqualTo(48));
        expect(
          tester.getSize(find.byTooltip(h.strings.exitNavigation)).shortestSide,
          greaterThanOrEqualTo(48),
        );
        // The end column (the report button, the compass, search, sound
        // and route options) is never empty, keeps route options, and
        // overlaps nothing.
        final column = find.byType(GoogleStyleControlStack);
        expect(column, findsOneWidget);
        final options = find.descendant(
          of: column,
          matching: find.byTooltip(h.strings.routeOptions),
        );
        expect(options, findsOneWidget, reason: 'route options kept');
        expect(tester.getSize(options).shortestSide, greaterThanOrEqualTo(48));
        expect(
          find.descendant(
            of: column,
            matching: find.byType(GoogleStyleReportButton),
          ),
          findsOneWidget,
          reason: 'the report heads the column',
        );
        final s = tester.getRect(column);
        expect(inside(s), isTrue, reason: 'column $s');
        expect(s.overlaps(sheet), isFalse, reason: 'column $s');
        expect(s.overlaps(header), isFalse, reason: 'column $s');
        expect(
          report.bottom,
          lessThanOrEqualTo(tester.getRect(options).top - 16 + 0.5),
          reason: 'report $report above route options',
        );
        // The column's own box is as wide as its widest member (the report
        // pill): the members themselves must keep clear of the rest.
        final members = [
          for (final f in [
            find.byType(GoogleStyleReportButton),
            find.byType(GoogleStyleCompassButton),
            find.byTooltip(h.strings.searchAlongRoute),
            find.byType(GoogleStyleSoundButton),
            options,
          ])
            if (find.descendant(of: column, matching: f).evaluate().isNotEmpty)
              tester.getRect(find.descendant(of: column, matching: f)),
        ];
        if (side) {
          expect(inPanel(header), isTrue, reason: 'header $header');
          expect(inPanel(sheet), isTrue, reason: 'sheet $sheet');
          expect(inMapArea(report), isTrue, reason: 'report $report');
        } else {
          expect(header.overlaps(sheet), isFalse);
        }
        final bottomStart = moved
            ? find.byType(GoogleStyleRecenterButton)
            : find.byType(GoogleStyleSpeedCluster);
        if (bottomStart.evaluate().isNotEmpty) {
          final r = tester.getRect(bottomStart);
          // A speed cluster with nothing to show lays out empty.
          if (!r.isEmpty) {
            expect(inside(r), isTrue, reason: 'bottom start $r');
            for (final other in [header, sheet, ...members]) {
              expect(r.overlaps(other), isFalse, reason: '$r / $other');
            }
            if (side) expect(inMapArea(r), isTrue, reason: 'bottom start $r');
            if (moved) expect(r.height, greaterThanOrEqualTo(48));
          }
        }
        if (moved) {
          expect(find.byType(GoogleStyleSpeedCluster), findsNothing);
        }
      }

      await h.drive(
        tester,
        routes: [sampleRoute, sampleRouteAlternatives.single],
      );
      expect(tester.takeException(), isNull, reason: 'following');
      check(moved: false);
      h.session.follow = false;
      await h.frames(tester);
      expect(tester.takeException(), isNull, reason: 'moved');
      check(moved: true);

      h.session.follow = true;
      // Once the report pill is a circle.
      await h.run(
        tester,
        2,
        fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
      );
      expect(tester.takeException(), isNull, reason: 'report collapsed');
      check(moved: false);
      final stackRect = tester.getRect(find.byType(GoogleStyleControlStack));
      // Every screen shows the compass too, but one: 360x640 with insets at
      // 2x has room for two buttons only, the report and route options.
      final cramped =
          c.size == const Size(360, 640) && c.insets != null && c.scale == 2;
      expect(
        find.byType(GoogleStyleCompassButton),
        cramped ? findsNothing : findsOneWidget,
        reason: 'column $stackRect',
      );
      h.session.follow = false;
      await h.frames(tester);
      expect(tester.takeException(), isNull, reason: 'moved, collapsed');
      check(moved: true);

      await tester.tap(find.byKey(_centre));
      await h.settle(tester);
      expect(tester.takeException(), isNull, reason: 'expanded sheet');
      // The open menu hides the floating controls.
      await h.frames(tester);
      for (final type in [
        GoogleStyleControlStack,
        GoogleStyleReportButton,
        GoogleStyleRecenterButton,
        GoogleStyleSpeedCluster,
      ]) {
        expect(find.byType(type), findsNothing, reason: '$type, menu open');
      }
      await tester.tap(find.byKey(_centre));
      await h.settle(tester);

      h.session.resetMotion();
      await h.run(
        tester,
        8,
        fixAt: (s) =>
            h.fixOn(sampleRoute, sampleRoute.length - 40 + 8.0 * s, speed: 8),
      );
      expect(h.flow.state.value, isA<FlowArrived>());
      expect(tester.takeException(), isNull, reason: 'arrived');
      final arrivalHeader = _visible(tester, find.byKey(_header));
      final arrival = _visible(tester, find.byType(GoogleStyleArrivalSheet));
      expect(inside(arrivalHeader), isTrue, reason: 'arrival $arrivalHeader');
      final arrivalContent = _sheetContent(
        tester,
        find.byType(GoogleStyleArrivalSheet),
      );
      expect(
        inside(arrivalContent),
        isTrue,
        reason: 'arrival content $arrivalContent',
      );
      expect(surfaceInside(arrival), isTrue, reason: 'arrival $arrival');
      expect(arrivalHeader.overlaps(arrival), isFalse);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('google_style_arrival_done')))
            .height,
        greaterThanOrEqualTo(48),
      );
    });
  }

  // Fix round 3 (I-1): the end column's rows never overlap the bottom-start
  // group (the speed cluster or the Re-center pill), with route options on
  // or off, following or panned, with the sound pill open, in English and
  // Vietnamese at 1x and 2x.
  for (final (size, scale, vietnamese) in const [
    (Size(320, 640), 1.0, false),
    (Size(320, 640), 2.0, false),
    (Size(360, 640), 1.0, false),
    (Size(360, 640), 2.0, false),
    (Size(360, 640), 2.0, true),
    (Size(412, 915), 2.0, false),
  ]) {
    for (final routeOptions in [true, false]) {
      final name =
          '${size.width.toInt()}x${size.height.toInt()} ${scale}x'
          '${vietnamese ? ' vi' : ''}, route options '
          '${routeOptions ? 'on' : 'off'}';
      dropInTest('bottom row vs bottom start: $name', (tester, h) async {
        await h.mount(
          tester,
          size: size,
          scale: scale,
          routeOverviewButtonEnabled: routeOptions,
          strings: vietnamese
              ? const NavigationStrings.vietnamese()
              : const NavigationStrings(),
        );
        final column = find.byType(GoogleStyleControlStack);

        void check(String phase) {
          expect(tester.takeException(), isNull, reason: phase);
          final group = [
            find.byType(GoogleStyleRecenterButton),
            find.byType(GoogleStyleSpeedCluster),
          ].where((f) => f.evaluate().isNotEmpty).map(tester.getRect);
          final members = [
            for (final f in [
              find.byType(GoogleStyleReportButton),
              find.byType(GoogleStyleCompassButton),
              find.byTooltip(h.strings.searchAlongRoute),
              find.byType(GoogleStyleSoundButton),
              find.byKey(const ValueKey('google_style_sound_pill')),
              find.byTooltip(h.strings.routeOptions),
            ])
              if (find
                  .descendant(of: column, matching: f)
                  .evaluate()
                  .isNotEmpty)
                tester.getRect(find.descendant(of: column, matching: f).first),
          ];
          expect(members, isNotEmpty, reason: phase);
          for (final g in group) {
            if (g.isEmpty) continue;
            for (final m in members) {
              expect(m.overlaps(g), isFalse, reason: '$phase: $m / $g');
            }
          }
        }

        await h.drive(
          tester,
          routes: [sampleRoute, sampleRouteAlternatives.single],
        );
        await h.frames(tester);
        check('following, report pill');
        await h.run(
          tester,
          2,
          fixAt: (s) => h.fixOn(sampleRoute, 540.0 + 10 * s),
        );
        await h.frames(tester);
        check('following');
        h.session.follow = false;
        await h.frames(tester);
        await h.frames(tester);
        check('panned');
        final sound = find.descendant(
          of: column,
          matching: find.byType(GoogleStyleSoundButton),
        );
        if (sound.evaluate().isNotEmpty) {
          await tester.tap(sound);
          await h.frames(tester);
          await h.frames(tester);
          check('panned, sound pill open');
        }
      });
    }
  }
}
