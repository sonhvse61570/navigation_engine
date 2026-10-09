import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

final _formatter = const EnglishGuidanceFormatter();
final _overview = FlowOverview([
  sampleRoute,
  sampleRouteAlternatives.single,
], 0);

void main() {
  group('GoogleStyleOverviewPanel', () {
    testWidgets('loading shows a spinner and the message', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: FlowLoading(sampleRoute.points.last)),
        ),
      );
      expect(find.text('Finding routes…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loading offers Cancel only with onCancel', (tester) async {
      final loading = FlowLoading(sampleRoute.points.last);
      await tester.pumpWidget(_host(GoogleStyleOverviewPanel(state: loading)));
      expect(find.text('Cancel'), findsNothing);

      var cancel = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: loading, onCancel: () => cancel++),
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      expect(cancel, 1);
    });

    testWidgets('the close button shows only with onClose, in an overview', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: _overview)),
      );
      expect(find.byIcon(Icons.close), findsNothing);

      var closed = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: _overview, onClose: () => closed++),
        ),
      );
      final close = find.widgetWithIcon(IconButton, Icons.close);
      expect(close, findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      // At the top right of the panel.
      final panel = tester.getRect(find.byType(GoogleStyleOverviewPanel));
      final button = tester.getRect(close);
      expect(button.top - panel.top, lessThan(24));
      expect(panel.right - button.right, lessThan(24));
      await tester.tap(close);
      expect(closed, 1);

      // Not in loading or an error.
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(
            state: FlowLoading(sampleRoute.points.last),
            onClose: () => closed++,
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows a card per route', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: _overview)),
      );
      expect(find.byKey(const ValueKey('route_card_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_card_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_card_2')), findsNothing);
      expect(
        find.text(
          _formatter.duration(Duration(seconds: sampleRoute.duration.round())),
        ),
        findsWidgets,
      );
      expect(find.text('8 min'), findsWidgets);
      expect(find.text('via Ly Tu Trong, Nguyen Huu Canh'), findsOneWidget);
      expect(find.text('Fastest'), findsOneWidget);
    });

    testWidgets('a single route is not labelled fastest', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: FlowOverview([sampleRoute], 0))),
      );
      expect(find.text('Fastest'), findsNothing);
    });

    testWidgets('tapping a card selects it', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: _overview, onSelect: selected.add),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('route_card_1')));
      expect(selected, [1]);
    });

    testWidgets('start and resume buttons', (tester) async {
      var started = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: _overview, onStart: () => started++),
        ),
      );
      expect(find.text('Resume'), findsNothing);
      await tester.tap(find.text('Start'));
      expect(started, 1);

      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(
            state: _overview,
            tripOverview: true,
            onStart: () => started++,
          ),
        ),
      );
      expect(find.text('Start'), findsNothing);
      await tester.tap(find.text('Resume'));
      expect(started, 2);
    });

    testWidgets('Steps appears only with onSteps', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: _overview)),
      );
      expect(find.text('Steps'), findsNothing);

      var steps = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(state: _overview, onSteps: () => steps++),
        ),
      );
      await tester.tap(find.text('Steps'));
      expect(steps, 1);
    });

    testWidgets('error shows the message with retry and cancel', (
      tester,
    ) async {
      var retry = 0, cancel = 0;
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(
            state: FlowError(
              Exception('offline'),
              const FlowIdle(),
              sampleRoute.points.last,
            ),
            onRetry: () => retry++,
            onCancel: () => cancel++,
          ),
        ),
      );
      expect(find.text('No route found'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Cancel'));
      expect([retry, cancel], [1, 1]);
    });

    Future<void> pumpRoutes(
      WidgetTester tester,
      int count, {
      Size size = const Size(400, 900),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: GoogleStyleOverviewPanel(
                state: FlowOverview(List.filled(count, sampleRoute), 0),
                onSteps: () {},
              ),
            ),
          ),
        ),
      );
    }

    double maxScroll(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .maxScrollExtent;

    testWidgets('3 routes show without scrolling', (tester) async {
      await pumpRoutes(tester, 3);
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), 0);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('4 routes scroll', (tester) async {
      await pumpRoutes(tester, 4);
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), greaterThan(0));
    });

    testWidgets(
      '3 routes at 2x text scale show without scrolling and do not overflow',
      (tester) async {
        await pumpRoutes(tester, 3, textScale: 2);
        expect(tester.takeException(), isNull);
        expect(maxScroll(tester), 0);
      },
    );

    testWidgets('a 360x360 viewport with 5 routes does not overflow', (
      tester,
    ) async {
      await pumpRoutes(tester, 5, size: const Size(360, 360));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a 1 h 25 min duration is not truncated at 320 dp on the fastest card',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final route = NavRoute.fromPoints(
          const [GeoPoint(10.0, 106.0), GeoPoint(10.1, 106.0)],
          summary: 'Highway 1',
          segmentDurations: const [5100],
        );
        final text = _formatter.duration(
          Duration(seconds: route.duration.round()),
        );
        await tester.pumpWidget(
          _host(
            GoogleStyleOverviewPanel(
              state: FlowOverview([route, route], 0),
              onSteps: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(text).first)
              .didExceedMaxLines,
          isFalse,
        );
      },
    );

    testWidgets('other states are empty', (tester) async {
      await tester.pumpWidget(
        _host(const GoogleStyleOverviewPanel(state: FlowIdle())),
      );
      expect(find.byType(SafeArea), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no overflow at 320 dp with a 150-character summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final route = NavRoute.fromPoints(const [
        GeoPoint(10.0, 106.0),
        GeoPoint(10.01, 106.0),
      ], summary: List.filled(150, 'x').join());
      await tester.pumpWidget(
        _host(
          GoogleStyleOverviewPanel(
            state: FlowOverview([route, route], 0),
            onSteps: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('GoogleStyleStepList', () {
    Future<void> pump(WidgetTester tester, {int currentStep = -1}) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 3000,
            child: GoogleStyleStepList(
              route: sampleRoute,
              currentStep: currentStep,
            ),
          ),
        ),
      );
    }

    testWidgets('one tile per step', (tester) async {
      await pump(tester);
      expect(find.byType(ListTile), findsNWidgets(14));
      final first = tester.widget<ListTile>(find.byType(ListTile).first);
      expect(
        (first.title! as Text).data,
        _formatter.instruction(sampleRoute.steps[0]),
      );
    });

    testWidgets('the subtitle has the distance and time to the next step', (
      tester,
    ) async {
      await pump(tester);
      final tile = tester.widget<ListTile>(find.byType(ListTile).at(3));
      final subtitle = (tile.subtitle! as Text).data!;
      final step = sampleRoute.steps[3];
      final next = sampleRoute.steps[4].distance;
      expect(
        subtitle,
        '${_formatter.distance(next - step.distance)}'
        ' · ${_formatter.duration(Duration(seconds: (sampleRoute.durationAt(next) - sampleRoute.durationAt(step.distance)).round()))}',
      );
      expect(subtitle, contains('3 min'));
    });

    testWidgets('steps before the current one are dimmed', (tester) async {
      await pump(tester, currentStep: 2);
      double opacityOf(int i) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(ListTile).at(i),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacityOf(0), 0.45);
      expect(opacityOf(1), 0.45);
      expect(
        find.ancestor(
          of: find.byType(ListTile).at(2),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });
  });

  group('floating', () {
    Material material(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(GoogleStyleOverviewPanel),
            matching: find.byType(Material),
          )
          .first,
    );

    testWidgets('a bottom panel by default: the top corners rounded 16', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: _overview)),
      );
      expect(
        material(tester).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(16)),
      );
    });

    testWidgets('floating: a card with all four corners rounded 16', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(GoogleStyleOverviewPanel(state: _overview, floating: true)),
      );
      expect(material(tester).borderRadius, BorderRadius.circular(16));
      expect(material(tester).elevation, 8);
    });
  });
}
