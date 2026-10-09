import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

/// A search whose every query waits on its own completer.
class _Search {
  final queries = <AlongRouteQuery>[];
  final pending = <Completer<List<AlongRoutePlace>>>[];

  Future<List<AlongRoutePlace>> call(AlongRouteQuery query) {
    queries.add(query);
    final c = Completer<List<AlongRoutePlace>>();
    pending.add(c);
    return c.future;
  }
}

const _fuel = AlongRoutePlace(
  id: 'fuel',
  name: 'Fuel Stop',
  position: GeoPoint(10.78, 106.70),
  detour: Duration(minutes: 4),
  subtitle: 'Open 24 hours',
);
const _cafe = AlongRoutePlace(
  id: 'cafe',
  name: 'Corner Cafe',
  position: GeoPoint(10.79, 106.71),
);

Key _chip(AlongRouteCategory c) =>
    ValueKey('google_style_search_chip_${c.name}');
const _progress = ValueKey('google_style_search_progress');
const _addStop = ValueKey('google_style_search_add_stop');

void main() {
  const strings = NavigationStrings();
  late _Search search;
  late List<List<AlongRoutePlace>> results;
  late List<AlongRoutePlace> focused;
  late List<AlongRoutePlace> added;
  late int closes;

  setUp(() {
    search = _Search();
    results = [];
    focused = [];
    added = [];
    closes = 0;
  });

  Widget overlay({
    bool addStop = true,
    NavigationStrings s = strings,
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    GoogleStyleColors colors = GoogleStyleColors.day,
    AlongRoutePlace? focusedPlace,
    NavRoute? route,
    double fromDistance = 1200,
  }) => GoogleStyleSearchAlongRoute(
    search: search.call,
    route: route ?? sampleRoute,
    fromDistance: fromDistance,
    onResults: results.add,
    onFocus: focused.add,
    onClose: () => closes++,
    onAddStop: addStop ? added.add : null,
    formatter: formatter,
    strings: s,
    colors: colors,
    focusedPlace: focusedPlace,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: app!),
      ),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('focusedPlace selects that result from outside (a pin tap) '
      'and shows Add stop', (tester) async {
    ListTile tile(AlongRoutePlace p) => tester.widget<ListTile>(
      find.byKey(ValueKey('google_style_search_result_${p.id}')),
    );
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    search.pending.single.complete([_fuel, _cafe]);
    await tester.pump();
    expect(find.byKey(_addStop), findsNothing);
    await pump(tester, overlay(focusedPlace: _cafe));
    expect(tile(_cafe).selected, isTrue);
    expect(tile(_fuel).selected, isFalse);
    expect(find.byKey(_addStop), findsOneWidget);
    expect(focused, isEmpty, reason: 'the host chose it; no echo');
    await tester.tap(find.byKey(_addStop));
    expect(added, [_cafe]);
    // A list tap still moves the selection; the host's input then follows.
    await tester.tap(find.text('Fuel Stop'));
    await tester.pump();
    expect(tile(_fuel).selected, isTrue);
    await pump(tester, overlay(focusedPlace: _fuel));
    expect(tile(_fuel).selected, isTrue);
    // Another pin: the selection moves again.
    await pump(tester, overlay(focusedPlace: _cafe));
    expect(tile(_cafe).selected, isTrue);
    expect(tile(_fuel).selected, isFalse);
  });

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('$name: the field\'s cursor is the accent token (T11-6)', (
      tester,
    ) async {
      await pump(tester, overlay(colors: colors));
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('google_style_search_field')),
      );
      expect(field.cursorColor, colors.accent);
    });
  }

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('$name colours: the bar, the results card and a result', (
      tester,
    ) async {
      await pump(tester, overlay(colors: colors));
      final bar = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('google_style_search_field')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.color, colors.buttonSurface);
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      search.pending.single.complete([_fuel]);
      await tester.pump();
      final card = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('google_style_search_result_fuel')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.color, colors.surface);
      final title = tester.widget<Text>(find.text('Fuel Stop'));
      expect(title.style!.color, colors.onSurface);
    });
  }

  testWidgets('screen readers: the progress is labelled, and the failed and '
      'empty messages are live regions', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.coffee)));
    await tester.pump();
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(_progress),
    );
    expect(progress.semanticsLabel, strings.searchAlongRoute);
    Finder liveRegion(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
    );
    search.pending.last.completeError(Exception('offline'));
    await tester.pump();
    expect(liveRegion(strings.searchFailed), findsOneWidget);
    await tester.tap(find.byKey(_chip(AlongRouteCategory.grocery)));
    await tester.pump();
    search.pending.last.complete(const []);
    await tester.pump();
    expect(liveRegion(strings.noResults), findsOneWidget);
    handle.dispose();
  });

  testWidgets('giving or dropping onBarHeight keeps the field (and its '
      'focus)', (tester) async {
    Widget withBar(ValueChanged<double>? onBarHeight) =>
        GoogleStyleSearchAlongRoute(
          search: search.call,
          route: sampleRoute,
          fromDistance: 0,
          onResults: results.add,
          onFocus: focused.add,
          onClose: () {},
          onBarHeight: onBarHeight,
        );
    await pump(tester, withBar(null));
    final field = find.byKey(const ValueKey('google_style_search_field'));
    await tester.tap(field);
    await tester.pump();
    final state = tester.state(field);
    bool hasFocus() => tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;
    expect(hasFocus(), isTrue);
    final heights = <double>[];
    await pump(tester, withBar(heights.add));
    await tester.pump();
    expect(tester.state(field), same(state), reason: 'not remounted');
    expect(hasFocus(), isTrue);
    expect(heights, isNotEmpty);
    await pump(tester, withBar(null));
    expect(tester.state(field), same(state));
  });

  group('a new route (a reroute) while results show (T12-5)', () {
    final reroute = NavRoute.fromPoints(
      sampleRoute.points.skip(10).toList(),
      name: 'reroute',
    );

    testWidgets('clears the results and searches the last category again '
        'along the new route', (tester) async {
      await pump(tester, overlay());
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      search.pending.single.complete([_fuel, _cafe]);
      await tester.pump();
      await tester.tap(find.text('Fuel Stop'));
      await tester.pump();
      expect(find.byKey(_addStop), findsOneWidget);
      await pump(tester, overlay(route: reroute, fromDistance: 0));
      expect(find.text('Fuel Stop'), findsNothing);
      expect(find.byKey(_addStop), findsNothing);
      await tester.pump();
      expect(search.queries, hasLength(2));
      final again = search.queries.last;
      expect(again.route, same(reroute));
      expect(again.category, AlongRouteCategory.gas);
      expect(again.text, isNull);
      expect(again.fromDistance, 0);
      expect(results.last, isEmpty, reason: 'the old pins go at once');
      expect(find.byKey(_progress), findsOneWidget);
      search.pending.last.complete([_cafe]);
      await tester.pump();
      expect(find.text('Corner Cafe'), findsOneWidget);
      expect(results.last, [_cafe]);
    });

    testWidgets('searches the last text again', (tester) async {
      await pump(tester, overlay());
      await tester.enterText(
        find.byKey(const ValueKey('google_style_search_field')),
        'atm',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      search.pending.single.complete([_fuel]);
      await tester.pump();
      await pump(tester, overlay(route: reroute));
      await tester.pump();
      expect(search.queries, hasLength(2));
      expect(search.queries.last.text, 'atm');
      expect(search.queries.last.route, same(reroute));
    });

    testWidgets('an answer for the old route that lands later is dropped', (
      tester,
    ) async {
      await pump(tester, overlay());
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      await pump(tester, overlay(route: reroute));
      await tester.pump();
      expect(search.queries, hasLength(2));
      search.pending.first.complete([_fuel]);
      await tester.pump();
      expect(find.text('Fuel Stop'), findsNothing);
    });

    testWidgets('with no search yet, nothing is searched', (tester) async {
      await pump(tester, overlay());
      await pump(tester, overlay(route: reroute));
      await tester.pump();
      expect(search.queries, isEmpty);
      expect(results, isEmpty);
    });
  });

  testWidgets('a field with the hint and the 4 category chips', (tester) async {
    await pump(tester, overlay());
    expect(find.text(strings.searchHint), findsOneWidget);
    for (final (c, label) in [
      (AlongRouteCategory.gas, strings.gasStations),
      (AlongRouteCategory.restaurant, strings.restaurants),
      (AlongRouteCategory.coffee, strings.coffee),
      (AlongRouteCategory.grocery, strings.groceries),
    ]) {
      expect(find.byKey(_chip(c)), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(_progress), findsNothing);
  });

  testWidgets('a chip searches its category along the route from the '
      'vehicle; a progress bar while it runs; results with their detour', (
    tester,
  ) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    final q = search.queries.single;
    expect(q.category, AlongRouteCategory.gas);
    expect(q.text, isNull);
    expect(q.route, same(sampleRoute));
    expect(q.fromDistance, 1200);
    expect(find.byKey(_progress), findsOneWidget);
    search.pending.single.complete([_fuel, _cafe]);
    await tester.pump();
    expect(find.byKey(_progress), findsNothing);
    expect(find.text('Fuel Stop'), findsOneWidget);
    expect(find.text('Open 24 hours'), findsOneWidget);
    expect(find.text('+4 min'), findsOneWidget);
    expect(find.text('Corner Cafe'), findsOneWidget);
    expect(results, [
      <AlongRoutePlace>[],
      [_fuel, _cafe],
    ]);
  });

  testWidgets('submitted text is searched', (tester) async {
    await pump(tester, overlay());
    await tester.enterText(
      find.byKey(const ValueKey('google_style_search_field')),
      '  atm ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(search.queries.single.text, 'atm');
    expect(search.queries.single.category, isNull);
  });

  testWidgets('a failure shows searchFailed; nothing found shows noResults', (
    tester,
  ) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.coffee)));
    await tester.pump();
    search.pending.last.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text(strings.searchFailed), findsOneWidget);
    await tester.tap(find.byKey(_chip(AlongRouteCategory.grocery)));
    await tester.pump();
    expect(find.text(strings.searchFailed), findsNothing);
    search.pending.last.complete(const []);
    await tester.pump();
    expect(find.text(strings.noResults), findsOneWidget);
  });

  testWidgets('a tap on a result focuses it and offers Add stop', (
    tester,
  ) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    search.pending.single.complete([_fuel, _cafe]);
    await tester.pump();
    expect(find.byKey(_addStop), findsNothing);
    await tester.tap(find.text('Corner Cafe'));
    await tester.pump();
    expect(focused, [_cafe]);
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('google_style_search_result_cafe')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester.getSize(find.byKey(_addStop)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(_addStop));
    expect(added, [_cafe]);
  });

  testWidgets('without onAddStop there is no Add stop', (tester) async {
    await pump(tester, overlay(addStop: false));
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    search.pending.single.complete([_fuel]);
    await tester.pump();
    await tester.tap(find.text('Fuel Stop'));
    await tester.pump();
    expect(find.byKey(_addStop), findsNothing);
  });

  testWidgets('the back button closes', (tester) async {
    await pump(tester, overlay());
    await tester.tap(find.byTooltip(strings.cancel));
    expect(closes, 1);
  });

  testWidgets('a slower first search does not overwrite a newer one', (
    tester,
  ) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    await tester.tap(find.byKey(_chip(AlongRouteCategory.coffee)));
    await tester.pump();
    search.pending[1].complete([_cafe]);
    await tester.pump();
    search.pending[0].complete([_fuel]);
    await tester.pump();
    expect(find.text('Corner Cafe'), findsOneWidget);
    expect(find.text('Fuel Stop'), findsNothing);
    expect(results.last, [_cafe]);
    expect(results.where((r) => r.contains(_fuel)), isEmpty);
  });

  testWidgets('results that arrive after closing are ignored', (tester) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    search.pending.single.complete([_fuel]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(results, [<AlongRoutePlace>[]]);
  });

  testWidgets('the middle lets touches through to what is under it', (
    tester,
  ) async {
    var mapTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => mapTaps++,
                  child: const ColoredBox(color: Color(0xFF808080)),
                ),
              ),
              Positioned.fill(child: overlay()),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 400));
    expect(mapTaps, 1);
  });

  for (final direction in TextDirection.values) {
    testWidgets('2x text at 320 dp, Vietnamese, ${direction.name}, with '
        'results: no overflow', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        overlay(
          s: const NavigationStrings.vietnamese(),
          formatter: const VietnameseGuidanceFormatter(),
          colors: GoogleStyleColors.night,
        ),
        scale: 2,
        direction: direction,
      );
      expect(tester.takeException(), isNull, reason: 'empty');
      await tester.ensureVisible(
        find.text(const NavigationStrings.vietnamese().restaurants),
      );
      await tester.pump();
      await tester.tap(find.byKey(_chip(AlongRouteCategory.restaurant)));
      await tester.pump();
      search.pending.single.complete([
        for (var i = 0; i < 8; i++)
          AlongRoutePlace(
            id: '$i',
            name: 'Nhà hàng số $i rất dài tên',
            position: const GeoPoint(10.78, 106.70),
            detour: Duration(minutes: i),
            subtitle: 'Đường Nguyễn Huệ, Quận 1',
          ),
      ]);
      await tester.pump();
      await tester.tap(find.text('Nhà hàng số 0 rất dài tên'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'results');
    });
  }

  testWidgets('landscape 844x390 at 2x text with results: no overflow, the '
      'chips stay one row of at most 58 dp', (tester) async {
    tester.view
      ..physicalSize = const Size(844, 390)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, overlay(), scale: 2);
    final heights = {
      for (final c in AlongRouteCategory.values)
        c: tester.getSize(find.byKey(_chip(c))).height,
    };
    final tops = {
      for (final c in AlongRouteCategory.values)
        tester.getTopLeft(find.byKey(_chip(c))).dy,
    };
    expect(tops, hasLength(1), reason: 'one row');
    for (final h in heights.values) {
      // A chip's label scales with the text: 58 dp at 2x.
      expect(h, lessThanOrEqualTo(58));
    }
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    search.pending.single.complete([
      for (var i = 0; i < 8; i++)
        AlongRoutePlace(
          id: '$i',
          name: 'Place $i',
          position: const GeoPoint(10.78, 106.70),
          detour: Duration(minutes: i),
          subtitle: 'Some street',
        ),
    ]);
    await tester.pump();
    await tester.tap(find.text('Place 0'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_addStop), findsOneWidget);
  });

  testWidgets('an older search that fails after a newer one succeeded keeps '
      'the newer results', (tester) async {
    await pump(tester, overlay());
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    await tester.tap(find.byKey(_chip(AlongRouteCategory.coffee)));
    await tester.pump();
    search.pending[1].complete([_cafe]);
    await tester.pump();
    search.pending[0].completeError(Exception('offline'));
    await tester.pump();
    expect(find.text('Corner Cafe'), findsOneWidget);
    expect(find.text(strings.searchFailed), findsNothing);
    expect(find.byKey(_progress), findsNothing);
  });

  testWidgets('an error thrown by onResults is reported, not shown as a '
      'failed search', (tester) async {
    final thrown = <Object>[];
    final saved = FlutterError.onError;
    FlutterError.onError = (details) => thrown.add(details.exception);
    addTearDown(() => FlutterError.onError = saved);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoogleStyleSearchAlongRoute(
            search: search.call,
            route: sampleRoute,
            fromDistance: 0,
            onResults: (r) {
              if (r.isNotEmpty) throw StateError('host bug');
            },
            onFocus: focused.add,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
    await tester.pump();
    search.pending.single.complete([_fuel]);
    await tester.pump();
    expect(thrown.single, isA<StateError>());
    expect(find.text(strings.searchFailed), findsNothing);
    expect(find.text('Fuel Stop'), findsOneWidget);
  });

  final manyPlaces = [
    for (var i = 0; i < 8; i++)
      AlongRoutePlace(
        id: '$i',
        name: 'Place $i',
        position: const GeoPoint(10.78, 106.70),
        detour: Duration(minutes: i),
        subtitle: 'Some street',
      ),
  ];

  for (final scale in [1.0, 2.0]) {
    testWidgets('keyboard open (300 dp inset) at ${scale}x text: a chip tap '
        'closes it and the results do not overflow', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await pump(tester, overlay(), scale: scale);
      final field = find.descendant(
        of: find.byKey(const ValueKey('google_style_search_field')),
        matching: find.byType(EditableText),
      );
      await tester.tap(find.byKey(const ValueKey('google_style_search_field')));
      await tester.pump();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
      search.pending.single.complete(manyPlaces);
      await tester.pump();
      await tester.tap(find.text('Place 0'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard still open (300 dp inset) at ${scale}x text: the '
        'results card shrinks to the room left', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await pump(tester, overlay(), scale: scale);
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      search.pending.single.complete(manyPlaces);
      await tester.pump();
      // Another source (the host's own field) raises the keyboard again.
      await tester.tap(find.byKey(const ValueKey('google_style_search_field')));
      await tester.pump();
      await tester.tap(find.text('Place 0'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_addStop), findsOneWidget);
    });
  }

  for (final (name, colors, tint, content) in [
    ('day', GoogleStyleColors.day, 0xFFD2E3FC, 0xFF1967D2),
    ('night', GoogleStyleColors.night, 0xFF394457, 0xFF8AB4F8),
  ]) {
    testWidgets('$name: the selected chip is Google blue, not the theme\'s '
        'tint; the others keep the button surface', (tester) async {
      await pump(tester, overlay(colors: colors));
      await tester.tap(find.byKey(_chip(AlongRouteCategory.gas)));
      await tester.pump();
      Finder inChip(AlongRouteCategory c, Finder f) =>
          find.descendant(of: find.byKey(_chip(c)), matching: f);
      Color? background(AlongRouteCategory c) =>
          (tester.widget<Ink>(inChip(c, find.byType(Ink))).decoration!
                  as ShapeDecoration)
              .color;
      Color? text(AlongRouteCategory c, String label) => tester
          .renderObject<RenderParagraph>(inChip(c, find.text(label)))
          .text
          .style
          ?.color;
      Color? icon(AlongRouteCategory c) =>
          tester.widget<Icon>(inChip(c, find.byType(Icon))).color;

      // At once: no frame of the theme's selected colour (its purple).
      expect(background(AlongRouteCategory.gas), Color(tint));
      search.pending.single.complete([_fuel]);
      await tester.pump(const Duration(seconds: 1));

      expect(background(AlongRouteCategory.gas), Color(tint));
      expect(text(AlongRouteCategory.gas, strings.gasStations), Color(content));
      expect(icon(AlongRouteCategory.gas), Color(content));
      expect(colors.selectedTint, Color(tint));
      expect(colors.onSelectedTint, Color(content));

      expect(background(AlongRouteCategory.coffee), colors.buttonSurface);
      expect(text(AlongRouteCategory.coffee, strings.coffee), colors.onSurface);
      expect(icon(AlongRouteCategory.coffee), colors.buttonIcon);
    });
  }

  testWidgets('onBarHeight reports the bar\'s height after the frame, and '
      'again when it changes', (tester) async {
    final heights = <double>[];
    Widget withBar() => GoogleStyleSearchAlongRoute(
      search: search.call,
      route: sampleRoute,
      fromDistance: 0,
      onResults: results.add,
      onFocus: focused.add,
      onClose: () {},
      onBarHeight: heights.add,
    );
    await pump(tester, withBar());
    await tester.pump();
    final chips = tester.getRect(find.byKey(_chip(AlongRouteCategory.gas)));
    expect(heights, [closeTo(chips.bottom + 8, 0.5)]);
    await pump(tester, withBar(), scale: 2);
    await tester.pump();
    expect(heights, hasLength(2));
    expect(heights.last, greaterThan(heights.first));
    final bigger = tester.getRect(find.byKey(_chip(AlongRouteCategory.gas)));
    expect(heights.last, closeTo(bigger.bottom + 8, 0.5));
  });
}
