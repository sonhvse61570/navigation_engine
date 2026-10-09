import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: app!,
  ),
  home: Scaffold(body: Center(child: child)),
);

const _button = ValueKey('google_style_report_button');
Key _tile(IncidentType t) => ValueKey('google_style_report_tile_${t.name}');

void main() {
  const en = NavigationStrings();
  const vi = NavigationStrings.vietnamese();

  test('IncidentType: 8 values, each with a label, an icon and a colour', () {
    expect(IncidentType.values.map((t) => t.name), [
      'crash',
      'slowdown',
      'police',
      'construction',
      'laneClosure',
      'stalledVehicle',
      'objectOnRoad',
      'roadClosure',
    ]);
    expect(IncidentType.values.map((t) => t.label(en)), [
      en.crash,
      en.slowdown,
      en.police,
      en.construction,
      en.laneClosure,
      en.stalledVehicle,
      en.objectOnRoad,
      en.roadClosure,
    ]);
    expect(IncidentType.crash.label(vi), 'Va chạm');
    expect(IncidentType.values.map((t) => t.icon).toSet(), hasLength(8));
    for (final t in IncidentType.values) {
      expect(t.tileColor.a, 1.0, reason: t.name);
    }
  });

  group('GoogleStyleReportButton', () {
    testWidgets('a pill with the label, then a 52 dp circle after 5 s', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(GoogleStyleReportButton(onPressed: () => taps++)),
      );
      expect(find.text(en.report), findsOneWidget);
      expect(tester.getSize(find.byKey(_button)).height, 52);
      expect(tester.getSize(find.byKey(_button)).width, greaterThan(52));
      await tester.tap(find.byKey(_button));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(en.report), findsNothing);
      expect(tester.getSize(find.byKey(_button)), const Size(52, 52));
      expect(find.bySemanticsLabel(en.report), findsOneWidget);
      await tester.tap(find.byKey(_button));
      expect(taps, 2);
    });

    testWidgets('night colours', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleReportButton(
            onPressed: () {},
            colors: GoogleStyleColors.night,
          ),
        ),
      );
      final material = tester.widget<Material>(find.byKey(_button));
      expect(material.color, GoogleStyleColors.night.buttonSurface);
      expect(material.elevation, 1);
      // Unmounting cancels the 5 s countdown: no timer is left pending.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('2x text: the pill fits on one line', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleReportButton(onPressed: () {}, strings: vi), scale: 2),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(_button)).height, 52);
      final label = tester.renderObject<RenderParagraph>(find.text(vi.report));
      expect(label.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(find.text(vi.report)).height,
        lessThanOrEqualTo(16 * 2 * 1.5),
        reason: 'one line',
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('in a narrow parent the label ellipsizes, without an '
        'overflow', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 90,
            child: GoogleStyleReportButton(onPressed: () {}, strings: vi),
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(_button)).width, lessThanOrEqualTo(90));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a new collapseAfter starts the countdown again', (
      tester,
    ) async {
      Widget button(Duration after) => _host(
        GoogleStyleReportButton(onPressed: () {}, collapseAfter: after),
      );
      await tester.pumpWidget(button(const Duration(seconds: 5)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(button(const Duration(seconds: 2)));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text(en.report), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        find.text(en.report),
        findsNothing,
        reason: '2 s after the new value',
      );
    });

    testWidgets('the semantics node keeps the tap action', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _host(GoogleStyleReportButton(onPressed: () => taps++)),
      );
      final node = tester.getSemantics(find.bySemanticsLabel(en.report));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(taps, 1, reason: 'the action reaches onPressed');
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });
  });

  group('GoogleStyleReportSheet', () {
    testWidgets('the title and 8 round 64 dp tiles; a tile reports its '
        'type', (tester) async {
      final chosen = <IncidentType>[];
      await tester.pumpWidget(
        _host(GoogleStyleReportSheet(onSelected: chosen.add)),
      );
      expect(find.text(en.addReport), findsOneWidget);
      for (final t in IncidentType.values) {
        expect(tester.getSize(find.byKey(_tile(t))), const Size(64, 64));
        expect(find.text(t.label(en)), findsOneWidget);
      }
      await tester.tap(find.byKey(_tile(IncidentType.police)));
      expect(chosen, [IncidentType.police]);
    });

    testWidgets('360 dp: a 4x2 grid', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(GoogleStyleReportSheet(onSelected: (_) {})),
      );
      final rows = <double, int>{};
      for (final t in IncidentType.values) {
        final top = tester.getRect(find.byKey(_tile(t))).top;
        rows[top] = (rows[top] ?? 0) + 1;
      }
      expect(rows.values, [4, 4]);
    });

    testWidgets('night colours; the title is a header', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          GoogleStyleReportSheet(
            onSelected: (_) {},
            colors: GoogleStyleColors.night,
          ),
        ),
      );
      final title = tester.widget<Text>(find.text(en.addReport));
      expect(title.style!.color, GoogleStyleColors.night.onSurface);
      final label = tester.widget<Text>(find.text(en.crash));
      expect(label.style!.color, GoogleStyleColors.night.onSurface);
      expect(
        tester.getSemantics(find.text(en.addReport)),
        matchesSemantics(label: en.addReport, isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('360 dp at 2x text in Vietnamese: the labels are not cut', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          GoogleStyleReportSheet(onSelected: (_) {}, strings: vi),
          scale: 2,
        ),
      );
      for (final t in IncidentType.values) {
        final label = tester.renderObject<RenderParagraph>(
          find.text(t.label(vi)),
        );
        expect(label.didExceedMaxLines, isFalse, reason: t.name);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('360 dp at 2x text in Vietnamese: no overflow', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          GoogleStyleReportSheet(onSelected: (_) {}, strings: vi),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('in a modal sheet it spans the screen, the tiles centred', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGoogleStyleReportSheet(context),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GoogleStyleReportSheet)).width, 412);
      final first = tester.getRect(find.byKey(_tile(IncidentType.crash)));
      final last = tester.getRect(find.byKey(_tile(IncidentType.construction)));
      expect(first.left, closeTo(412 - last.right, 1), reason: 'centred');
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('at ${scale}x text no name breaks inside a word', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(360, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(GoogleStyleReportSheet(onSelected: (_) {}), scale: scale),
        );
        for (final t in IncidentType.values) {
          final name = t.label(en);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(name),
          );
          final lines = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: name.length),
              )
              .map((box) => box.top.round())
              .toSet()
              .length;
          expect(
            lines,
            lessThanOrEqualTo(name.split(' ').length),
            reason: '$name: $lines lines',
          );
        }
      });
    }

    testWidgets('showGoogleStyleReportSheet returns the choice, or null', (
      tester,
    ) async {
      final results = <IncidentType?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await showGoogleStyleReportSheet(context)),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_tile(IncidentType.crash)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      expect(results, [IncidentType.crash, null]);
    });
  });
}
