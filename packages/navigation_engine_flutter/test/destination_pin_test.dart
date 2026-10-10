import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/flow_harness.dart';

/// A session map that records its alternates (as [RecordingMap] does) and
/// every destination pin it is asked to show, null for a clear.
class _PinMap extends RecordingMap implements DestinationPinMap {
  final pins = <GeoPoint?>[];

  /// When set, [showDestinationPin] throws it.
  Object? error;

  @override
  void showDestinationPin(GeoPoint? point) {
    if (error != null) throw error!;
    pins.add(point);
  }
}

/// A map that draws the route and pins, and nothing else: no route options.
class _OnlyPinMap extends PlainMap implements DestinationPinMap {
  final pins = <GeoPoint?>[];

  @override
  void showDestinationPin(GeoPoint? point) => pins.add(point);
}

/// A map that reports itself ready after its first frame.
class _ReadyMap extends StatefulWidget {
  const _ReadyMap({required this.config});

  final NavigationMapConfig config;

  @override
  State<_ReadyMap> createState() => _ReadyMapState();
}

class _ReadyMapState extends State<_ReadyMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.config.onMapReady(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF808080));
}

/// Which styled scaffold a test mounts.
enum _Style { google, mapbox }

/// Mounts the [style] scaffold on [h]'s session and flow; returns a getter
/// of the config of the map builder's last build.
Future<NavigationMapConfig Function()> _mount(
  WidgetTester tester,
  FlowHarness h,
  _Style style,
) async {
  tester.view
    ..physicalSize = const Size(400, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late NavigationMapConfig config;
  await tester.pumpWidget(_screen(style, h.session, h.flow, (c) => config = c));
  await tester.pump();
  return () => config;
}

/// The [style] scaffold of [flow] on [session]; [onConfig] gets each
/// config the map builder gets.
Widget _screen(
  _Style style,
  NavigationSession session,
  NavigationFlowController flow,
  void Function(NavigationMapConfig config) onConfig,
) {
  Widget map(NavigationMapConfig c) {
    onConfig(c);
    return _ReadyMap(config: c);
  }

  return MaterialApp(
    home: switch (style) {
      _Style.google => GoogleStyleFlowScaffold(
        session: session,
        flow: flow,
        mapBuilder: (context, c, layers) => map(c),
      ),
      _Style.mapbox => MapboxStyleFlowScaffold(
        session: session,
        flow: flow,
        mapBuilder: (context, c, colors, routeColors, label) => map(c),
      ),
    },
  );
}

/// A [flowTest] on [style]'s scaffold, unmounted before the flow is
/// disposed.
void _pinTest(
  String description,
  _Style style,
  Future<void> Function(
    WidgetTester tester,
    FlowHarness h,
    NavigationMapConfig Function() config,
  )
  body, {
  NavigationMap Function()? map,
  RouteProvider? Function()? provider,
}) => flowTest(
  '$description (${style.name} style)',
  (tester, h) async {
    try {
      final config = await _mount(tester, h, style);
      await body(tester, h, config);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  },
  map: map ?? _PinMap.new,
  provider: provider,
);

void main() {
  final north = northRoute();
  final branch = branchRoute(1500);

  late Completer<List<NavRoute>> gate;

  for (final style in _Style.values) {
    _pinTest('a map that pins but has no route options gets the pin', style, (
      tester,
      h,
      config,
    ) async {
      final map = h.map as _OnlyPinMap;
      h.flow.previewRoutes([north]);
      await tester.pump();
      h.flow.stop();
      await tester.pump();
      expect(map.pins, [north.points.last, null]);
    }, map: _OnlyPinMap.new);

    _pinTest(
      'a new preview from the overview removes the pin while it loads, '
      'then pins the new route; a cancel shows the old one again',
      style,
      (tester, h, config) async {
        final map = h.map as _PinMap;
        h.flow.previewRoutes([north]);
        await tester.pump();
        expect(map.pins.last, north.points.last);

        gate = Completer();
        unawaited(h.flow.preview(to: branch.points.last, from: testOrigin));
        await tester.pump();
        expect(h.flow.state.value, isA<FlowLoading>());
        expect(map.pins.last, isNull, reason: 'as the route options go');
        h.flow.cancel();
        await tester.pump();
        expect(map.pins.last, north.points.last);

        gate = Completer();
        unawaited(h.flow.preview(to: branch.points.last, from: testOrigin));
        await tester.pump();
        expect(map.pins.last, isNull);
        gate.complete([branch]);
        await tester.pump();
        expect(h.flow.state.value, isA<FlowOverview>());
        expect(map.pins.last, branch.points.last);
      },
      provider: () => CountingRouteProvider((_, _) => gate.future),
    );

    _pinTest(
      'a request that fails at once from the overview removes the pin; a '
      'cancel shows it again',
      style,
      (tester, h, config) async {
        final map = h.map as _PinMap;
        h.flow.previewRoutes([north]);
        await tester.pump();
        // No fix yet and no `from`: the request fails at once, without a
        // loading state.
        final states = <NavigationFlowState>[];
        void record() => states.add(h.flow.state.value);
        h.flow.state.addListener(record);
        await h.flow.preview(to: branch.points.last);
        h.flow.state.removeListener(record);
        await tester.pump();
        expect(states, [isA<FlowError>()]);
        expect(map.pins.last, isNull);
        h.flow.cancel();
        await tester.pump();
        expect(map.pins.last, north.points.last);
      },
      provider: () => CountingRouteProvider((_, _) => gate.future),
    );

    _pinTest('a new flow handed to the scaffold sends its pin', style, (
      tester,
      h,
      config,
    ) async {
      final map = h.map as _PinMap;
      final other = NavigationFlowController(
        session: h.session,
        nightMode: NightMode.alwaysDay,
        clock: () => h.now,
      );
      try {
        other.previewRoutes([branch]);
        final sent = map.pins.length;
        await tester.pumpWidget(_screen(style, h.session, other, (_) {}));
        await tester.pump();
        expect(map.pins.skip(sent), [branch.points.last]);
        // The scaffold now follows the new flow only.
        h.flow.previewRoutes([north]);
        await tester.pump();
        expect(map.pins.last, branch.points.last);
        other.stop();
        await tester.pump();
        expect(map.pins.last, isNull);
      } finally {
        // Before the pending-timer check: the flow has a night timer.
        await tester.pumpWidget(const SizedBox());
        other.dispose();
      }
    });

    _pinTest(
      'the pin marks the selected route\'s end in the overview, '
      'while navigating and arrived, and is cleared when idle',
      style,
      (tester, h, config) async {
        final map = h.map as _PinMap;
        expect(map.pins, isEmpty, reason: 'idle: nothing to pin');

        h.flow.previewRoutes([north, branch]);
        await tester.pump();
        expect(map.pins.last, north.points.last);

        h.flow.select(1);
        await tester.pump();
        expect(map.pins.last, branch.points.last);

        h.flow.start();
        await tester.pump();
        expect(h.flow.state.value, isA<FlowNavigating>());
        expect(map.pins.last, branch.points.last);

        await h.arriveOn(tester, branch);
        expect(h.flow.state.value, isA<FlowArrived>());
        expect(map.pins.last, branch.points.last);

        h.flow.stop();
        await tester.pump();
        expect(map.pins.last, isNull);
      },
    );

    _pinTest('closing a preview clears the pin', style, (
      tester,
      h,
      config,
    ) async {
      final map = h.map as _PinMap;
      h.flow.previewRoutes([north]);
      await tester.pump();
      expect(map.pins.last, north.points.last);
      h.flow.closeOverview();
      await tester.pump();
      expect(map.pins.last, isNull);
    });

    _pinTest('an alternate taken while navigating moves the pin', style, (
      tester,
      h,
      config,
    ) async {
      final map = h.map as _PinMap;
      h.flow.previewRoutes([north, branch]);
      h.flow.start();
      await h.run(tester, 3, fixAt: (s) => h.fixOn(north, 500.0 + 10 * s));
      expect(map.pins.last, north.points.last);
      h.flow.selectAlternate(0);
      await tester.pump();
      expect((h.flow.state.value as FlowNavigating).route, same(branch));
      expect(map.pins.last, branch.points.last);
    });

    _pinTest(
      'a reroute moves the pin to the new route\'s end',
      style,
      (tester, h, config) async {
        final map = h.map as _PinMap;
        h.flow.previewRoutes([north]);
        h.flow.start();
        await h.run(tester, 6, fixAt: (s) => h.offRoute(north, s));
        await h.run(tester, 0.5);
        final route = (h.flow.state.value as FlowNavigating).route;
        expect(route.name, 'rerouted');
        expect(route.points.last, isNot(north.points.last));
        expect(map.pins.last, route.points.last);
      },
      provider: () => CountingRouteProvider(
        (from, to) async => [
          NavRoute.fromPoints([
            from,
            offsetPoint(to, 90, 200),
          ], name: 'rerouted'),
        ],
      ),
    );

    _pinTest(
      'the app\'s own pin while idle is left alone, and the flow\'s '
      'replaces it in the overview',
      style,
      (tester, h, config) async {
        final map = h.map as _PinMap;
        const mine = GeoPoint(10.8, 106.7);
        map.showDestinationPin(mine);
        // A map that reports itself ready again, and a failed request that is
        // cancelled, do not touch the app's pin.
        config().onMapReady();
        await tester.pump();
        await h.flow.preview(to: mine, from: testOrigin);
        await tester.pump();
        expect(h.flow.state.value, isA<FlowError>(), reason: 'no provider');
        h.flow.cancel();
        await tester.pump();
        expect(h.flow.state.value, isA<FlowIdle>());
        expect(map.pins, [mine]);

        h.flow.previewRoutes([north]);
        await tester.pump();
        expect(map.pins.last, north.points.last);
      },
    );

    _pinTest(
      'a newly attached map gets the pin when it reports itself '
      'ready',
      style,
      (tester, h, config) async {
        h.flow.previewRoutes([north, branch]);
        h.flow.select(1);
        await tester.pump();
        final fresh = _PinMap();
        h.session.map = fresh;
        config().onMapReady();
        await tester.pump();
        expect(fresh.pins, [branch.points.last]);
      },
    );

    _pinTest(
      'a map without DestinationPinMap goes through a whole trip',
      style,
      (tester, h, config) async {
        h.flow.previewRoutes([north, branch]);
        await tester.pump();
        h.flow.select(1);
        h.flow.start();
        await tester.pump();
        await h.arriveOn(tester, branch);
        h.flow.stop();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
      map: RecordingMap.new,
    );

    _pinTest(
      'a pin call that throws is reported, and the flow goes on',
      style,
      (tester, h, config) async {
        final errors = collectFlutterErrors();
        final map = h.map as _PinMap..error = StateError('pin');
        h.flow.previewRoutes([north]);
        await tester.pump();
        expect(h.flow.state.value, isA<FlowOverview>());
        expect(errors, hasLength(1));
        expect(errors.single.exception, isA<StateError>());
        expect(errors.single.library, 'navigation_engine_flutter');
        map.error = null;
        h.flow.start();
        await tester.pump();
        expect(map.pins.last, north.points.last);
      },
    );
  }

  group('paintDestinationPin', () {
    Future<(Uint8List, ByteData)> paint(
      WidgetTester tester, {
      required double ratio,
      Color color = const Color(0xFFE53935),
    }) async => (await tester.runAsync(() async {
      final png = await paintDestinationPin(pixelRatio: ratio, color: color);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData();
      frame.image.dispose();
      return (png, data!);
    }))!;

    int width(Uint8List png) => ByteData.sublistView(png, 16, 20).getUint32(0);
    int height(Uint8List png) => ByteData.sublistView(png, 20, 24).getUint32(0);

    testWidgets('paints a PNG of 32x42 logical px times the ratio', (
      tester,
    ) async {
      final (png, _) = await paint(tester, ratio: 2);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      expect((width(png), height(png)), (64, 84));
      final (one, _) = await paint(tester, ratio: 1.5);
      expect((width(one), height(one)), (48, 63));
    });

    testWidgets('is a pin in the colour with a white outline and a white '
        'ring around a dark centre', (tester) async {
      const red = Color(0xFFE53935);
      final (_, pixels) = await paint(tester, ratio: 1);
      (int, int, int, int) at(int x, int y) {
        final i = (y * 32 + x) * 4;
        return (
          pixels.getUint8(i),
          pixels.getUint8(i + 1),
          pixels.getUint8(i + 2),
          pixels.getUint8(i + 3),
        );
      }

      // The outline: 2 px of white at the widest row (16 px down).
      for (final x in [0, 1]) {
        final (r, g, b, a) = at(x, 16);
        expect(a, greaterThan(200), reason: 'x $x is painted');
        expect([r, g, b], everyElement(greaterThan(200)), reason: 'white');
      }
      // The fill, between the outline and the ring.
      final (fr, fg, fb, fa) = at(4, 16);
      expect(fa, 255);
      expect(fr, closeTo((red.r * 255).round(), 2));
      expect(fg, closeTo((red.g * 255).round(), 2));
      expect(fb, closeTo((red.b * 255).round(), 2));
      // The white ring, then the dark centre.
      final (rr, rg, rb, _) = at(16 + 5, 16);
      expect([rr, rg, rb], everyElement(greaterThan(200)), reason: 'ring');
      final (cr, cg, cb, _) = at(16, 16);
      expect(cr, lessThan((red.r * 255).round() - 40));
      expect(cg, lessThan(80));
      expect(cb, lessThan(80));
      // The tip at the bottom centre; the bottom corners stay clear.
      expect(at(16, 40).$4, greaterThan(0));
      expect(at(0, 41).$4, 0);
      expect(at(31, 41).$4, 0);
    });

    testWidgets('paintSearchPin is shared from here too', (tester) async {
      final png = (await tester.runAsync(
        () => paintSearchPin(
          focused: false,
          pixelRatio: 1,
          color: const Color(0xFFD93025),
        ),
      ))!;
      expect((width(png), height(png)), (28, 36));
    });
  });
}
