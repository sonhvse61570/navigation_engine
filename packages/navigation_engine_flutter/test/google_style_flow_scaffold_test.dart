import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/flow_harness.dart';

const _centre = ValueKey('google_style_trip_sheet_centre');
const _handle = ValueKey('google_style_trip_sheet_handle');
const _pill = ValueKey('google_style_sound_pill');
const _gas = ValueKey('google_style_search_chip_gas');

const _fuel = AlongRoutePlace(
  id: 'fuel',
  name: 'Fuel Stop',
  position: GeoPoint(10.776, 106.701),
  detour: Duration(minutes: 3),
);
const _cafe = AlongRoutePlace(
  id: 'cafe',
  name: 'Corner Cafe',
  position: GeoPoint(10.777, 106.702),
);

/// A session map that records its alternates (as [RecordingMap] does) and
/// the search pins it is asked to draw.
class _PinsMap extends RecordingMap implements SearchPinsMap {
  /// The places pinned; null once cleared (or never shown).
  List<AlongRoutePlace>? places;
  String? focusedId;
  void Function(AlongRoutePlace place)? onTap;
  var shows = 0;
  var clears = 0;

  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) async {
    this.places = places;
    this.focusedId = focusedId;
    this.onTap = onTap;
    shows++;
  }

  @override
  void clearSearchPins() {
    places = null;
    focusedId = null;
    onTap = null;
    clears++;
  }
}

/// A [_PinsMap] whose camera throws at once, not through its future, as a
/// map that is not an `async` function may.
class _SyncThrowMap extends _PinsMap {
  @override
  Future<void> moveCamera(CameraTarget target) => throw StateError('boom');
}

/// A [_PinsMap] whose calls fail as the test sets, at once or through a
/// future.
class _FailingMap extends _PinsMap {
  var showThrows = false;
  var showFails = false;
  var clearThrows = false;
  var cameraFails = false;

  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) {
    if (showThrows) throw StateError('show');
    if (showFails) return Future<void>.error(StateError('show failed'));
    return super.showSearchPins(places, focusedId: focusedId, onTap: onTap);
  }

  @override
  void clearSearchPins() {
    if (clearThrows) throw StateError('clear');
    super.clearSearchPins();
  }

  @override
  Future<void> moveCamera(CameraTarget target) => cameraFails
      ? Future<void>.error(StateError('camera failed'))
      : super.moveCamera(target);
}

/// A set of colours that differs from the defaults in its [accent] and
/// [alternative]; two calls give two equal-looking but distinct values.
GoogleStyleColors _colours(Color accent, Color alternative) =>
    GoogleStyleColors(
      guidance: const Color(0xFF111111),
      guidanceSecondary: const Color(0xFF222222),
      onGuidance: const Color(0xFF333333),
      surface: const Color(0xFF444444),
      onSurface: const Color(0xFF555555),
      onSurfaceVariant: const Color(0xFF666666),
      accent: accent,
      onAccent: const Color(0xFF777777),
      alternative: alternative,
      etaText: const Color(0xFF888888),
      warning: const Color(0xFF999999),
    );

final _dayColours = _colours(const Color(0xFF0A0B0C), const Color(0xFF0D0E0F));
final _nightColours = _colours(
  const Color(0xFFA0B0C0),
  const Color(0xFFD0E0F0),
);

/// A map that reports itself ready after its first frame.
class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.config});

  final NavigationMapConfig config;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.config.onMapReady(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('fake_map'), color: Color(0xFF808080));
}

/// The scaffold on [h]'s session and flow, with every callback, recording
/// what its map builder gets.
class _Screen {
  _Screen(this.h);

  final FlowHarness h;

  /// Every layers value the map builder got, in order.
  final layers = <GoogleStyleMapLayers>[];
  GoogleStyleMapLayers get last => layers.last;

  /// The config of the map builder's last build.
  late NavigationMapConfig config;

  List<AlongRoutePlace> places = const [];
  final searches = <AlongRouteQuery>[];
  final added = <AlongRoutePlace>[];
  AudioGuidance audio = AudioGuidance.sound;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    TextDirection direction = TextDirection.ltr,
    bool pushed = false,
    GoogleStyleColors dayColors = GoogleStyleColors.day,
    GoogleStyleColors nightColors = GoogleStyleColors.night,
    RouteColors? dayRouteColors,
    RouteColors? nightRouteColors,
    GuidanceFormatter formatter = const EnglishGuidanceFormatter(),
    NavigationStrings strings = const NavigationStrings(),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final screen = StatefulBuilder(
      builder: (context, setState) => GoogleStyleFlowScaffold(
        session: h.session,
        flow: h.flow,
        dayColors: dayColors,
        nightColors: nightColors,
        dayRouteColors: dayRouteColors,
        nightRouteColors: nightRouteColors,
        formatter: formatter,
        strings: strings,
        audioGuidance: audio,
        onAudioGuidanceChanged: (a) => setState(() => audio = a),
        onReportIncident: (_) {},
        searchAlongRoute: (q) async {
          searches.add(q);
          return places;
        },
        onAddStop: added.add,
        onShareTrip: () {},
        onSettings: () {},
        mapBuilder: (context, config, layers) {
          this.config = config;
          this.layers.add(layers);
          return _FakeMap(config: config);
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: pushed
            ? Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                    child: const Text('HOME'),
                  ),
                ),
              )
            : screen,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump();
  }

  /// Previews [routes], starts the first and drives 4 s from [from] m.
  Future<void> drive(
    WidgetTester tester, {
    List<NavRoute>? routes,
    double from = 500,
  }) async {
    final all = routes ?? [sampleRoute];
    h.flow.previewRoutes(all);
    await tester.pump();
    h.flow.start();
    await tester.pump();
    await h.run(tester, 4, fixAt: (s) => h.fixOn(all.first, from + 10 * s));
  }

  double get sheetHeight =>
      _tester!.getSize(find.byType(GoogleStyleTripSheet)).height;
  WidgetTester? _tester;

  /// The trip sheet's collapsed and expanded heights, read by opening and
  /// closing it with taps.
  Future<(double, double)> extremes(WidgetTester tester) async {
    _tester = tester;
    final collapsed = sheetHeight;
    await tester.tap(find.byKey(_centre));
    await settle(tester);
    final expanded = sheetHeight;
    await tester.tap(find.byKey(_centre));
    await settle(tester);
    expect(sheetHeight, collapsed);
    return (collapsed, expanded);
  }

  /// Two 16 ms frames, so the overlays follow a change.
  Future<void> frames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// 40 frames of 16 ms: the trip sheet's animation settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }
}

/// A [flowTest] with a [_Screen], unmounted before the flow is disposed.
void _screenTest(
  String description,
  Future<void> Function(WidgetTester tester, _Screen s) body, {
  NavigationMap Function()? map,
}) => flowTest(description, (tester, h) async {
  final s = _Screen(h);
  try {
    await body(tester, s);
  } finally {
    await s.end(tester);
  }
}, map: map);

void main() {
  const strings = NavigationStrings();

  group('GoogleStyleMapLayers', () {
    test('defaults, equality and hashCode', () {
      const a = GoogleStyleMapLayers();
      expect(a.traffic, isFalse);
      expect(a.satellite, isFalse);
      expect(a.horizontalFocus, 0.5);
      expect(a.bottomOverlay, 0);
      expect(a.colors, GoogleStyleColors.day);
      expect(a, const GoogleStyleMapLayers());
      expect(a.hashCode, const GoogleStyleMapLayers().hashCode);
      expect(a, isNot(const GoogleStyleMapLayers(traffic: true)));
      expect(a, isNot(const GoogleStyleMapLayers(satellite: true)));
      expect(a, isNot(const GoogleStyleMapLayers(horizontalFocus: 0.7)));
      expect(a, isNot(const GoogleStyleMapLayers(bottomOverlay: 1)));
    });

    test('equality and hashCode cover the colours, the route colours and '
        'both labels', () {
      String route(NavRoute r) => 'route';
      String alternate(AlternateRoute a) => 'alternate';
      String other(AlternateRoute a) => 'other';
      final a = GoogleStyleMapLayers(
        colors: _dayColours,
        routeColors: const RouteColors(driven: Color(0xFF010203)),
        routeLabel: route,
        alternateLabel: alternate,
      );
      GoogleStyleMapLayers like({
        GoogleStyleColors? colors,
        RouteColors? routeColors,
        String Function(NavRoute)? routeLabel,
        String Function(AlternateRoute)? alternateLabel,
      }) => GoogleStyleMapLayers(
        colors: colors ?? _dayColours,
        routeColors:
            routeColors ?? const RouteColors(driven: Color(0xFF010203)),
        routeLabel: routeLabel ?? route,
        alternateLabel: alternateLabel ?? alternate,
      );
      expect(a, like());
      expect(a.hashCode, like().hashCode);
      expect(a, isNot(like(colors: GoogleStyleColors.night)));
      expect(a, isNot(like(routeColors: const RouteColors())));
      expect(
        a,
        isNot(
          like(
            routeColors: const RouteColors(
              driven: Color(0xFF010203),
              ahead: Color(0xFF000000),
            ),
          ),
        ),
      );
      expect(
        a,
        isNot(
          like(
            routeColors: const RouteColors(
              driven: Color(0xFF010203),
              drivenWidth: 1,
            ),
          ),
        ),
      );
      expect(
        a,
        isNot(
          like(
            routeColors: const RouteColors(
              driven: Color(0xFF010203),
              aheadWidth: 1,
            ),
          ),
        ),
      );
      expect(a, isNot(like(routeLabel: (r) => 'route')));
      expect(a, isNot(like(alternateLabel: other)));
      expect(a, isNot(const GoogleStyleMapLayers()));
    });

    test('the route colours are compared by their fields', () {
      const a = GoogleStyleMapLayers(
        routeColors: RouteColors(ahead: Color(0xFF123456)),
      );
      const b = GoogleStyleMapLayers(
        routeColors: RouteColors(ahead: Color(0xFF123456)),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the colours are compared by identity', () {
      // GoogleStyleColors has no `==`: two equal-looking values differ.
      final a = GoogleStyleMapLayers(colors: _colours(Colors.red, Colors.blue));
      final b = GoogleStyleMapLayers(colors: _colours(Colors.red, Colors.blue));
      expect(a, isNot(b));
      expect(a, a);
    });

    test('toString prints all 8 fields', () {
      String route(NavRoute r) => '';
      final text = GoogleStyleMapLayers(
        traffic: true,
        satellite: true,
        horizontalFocus: 0.25,
        bottomOverlay: 7,
        routeLabel: route,
      ).toString();
      for (final part in [
        'traffic: true',
        'satellite: true',
        'horizontalFocus: 0.25',
        'bottomOverlay: 7',
        'colors: ',
        'routeColors: ',
        'routeLabel: ',
        'alternateLabel: null',
      ]) {
        expect(text, contains(part));
      }
      expect(text, isNot(contains('routeLabel: null')));
    });
  });

  group('the layers the map builder gets', () {
    _screenTest('traffic and satellite follow the trip sheet menu\'s '
        'switches', (tester, s) async {
      await s.mount(tester);
      await s.drive(tester);
      expect(s.last.traffic, isFalse);
      expect(s.last.satellite, isFalse);
      await tester.tap(find.byKey(_centre));
      await s.settle(tester);
      await tester.tap(find.text(strings.showTraffic));
      await s.frames(tester);
      expect(s.last.traffic, isTrue);
      expect(s.last.satellite, isFalse);
      await tester.tap(find.text(strings.satellite));
      await s.frames(tester);
      expect(s.last.traffic, isTrue);
      expect(s.last.satellite, isTrue);
      await tester.tap(find.text(strings.showTraffic));
      await s.frames(tester);
      expect(s.last.traffic, isFalse);
      expect(s.last.satellite, isTrue);
    });

    _screenTest('horizontalFocus is the centre in portrait', (tester, s) async {
      await s.mount(tester);
      await s.drive(tester);
      expect(s.last.horizontalFocus, 0.5);
    });

    for (final direction in TextDirection.values) {
      _screenTest('horizontalFocus in landscape (${direction.name}): the '
          'middle of the map beside the side panel', (tester, s) async {
        const size = Size(915, 412);
        await s.mount(tester, size: size, direction: direction);
        await s.drive(tester);
        await s.frames(tester);
        final start =
            2 * NavigationFlowScaffold.sidePanelMargin +
            NavigationFlowScaffold.sidePanelWidth(size);
        final centre = (start + size.width) / 2 / size.width;
        expect(centre, greaterThan(0.5));
        expect(
          s.last.horizontalFocus,
          closeTo(direction == TextDirection.ltr ? centre : 1 - centre, 1e-9),
        );
      });
    }

    _screenTest('bottomOverlay is the scaffold\'s bottom overlay', (
      tester,
      s,
    ) async {
      await s.mount(tester);
      s.h.flow.previewRoutes([sampleRoute]);
      await s.frames(tester);
      await s.frames(tester);
      expect(s.config.bottomOverlayHeight.value, greaterThan(0));
      expect(s.last.bottomOverlay, s.config.bottomOverlayHeight.value);
      s.h.flow.start();
      await tester.pump();
      await s.h.run(
        tester,
        4,
        fixAt: (t) => s.h.fixOn(sampleRoute, 500.0 + 10 * t),
      );
      await s.frames(tester);
      expect(s.config.bottomOverlayHeight.value, greaterThan(0));
      expect(s.last.bottomOverlay, s.config.bottomOverlayHeight.value);
    });

    for (final (name, size) in [
      ('portrait', const Size(412, 915)),
      ('side panel', const Size(915, 412)),
    ]) {
      _screenTest('$name: a sheet drag holds the focus and the layers, '
          'while dragged, settling and open', (tester, s) async {
        await s.mount(tester, size: size);
        await s.drive(tester);
        final (collapsedSheet, expandedSheet) = await s.extremes(tester);
        await s.frames(tester);
        final held = s.last;
        final collapsed = s.config.bottomOverlayHeight.value;
        final span = expandedSheet - collapsedSheet;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_handle)),
        );
        for (var i = 1; i <= 6; i++) {
          await gesture.moveBy(Offset(0, -span / 10));
          await s.frames(tester);
          expect(s.last, held, reason: 'step $i');
        }
        expect(s.sheetHeight, closeTo(collapsedSheet + span * 0.6, 1));
        await gesture.up();
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(s.last, held, reason: 'settling, frame $i');
        }
        expect(s.sheetHeight, expandedSheet);
        expect(find.text(strings.directions), findsOneWidget);
        // The flow scaffold's own overlay moved with the sheet; the map's
        // did not.
        expect(s.config.bottomOverlayHeight.value, isNot(collapsed));
        expect(s.last, held, reason: 'open');
        await tester.tap(find.byKey(_centre));
        await s.settle(tester);
        await s.frames(tester);
        expect(s.last, held, reason: 'closed again');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the look of the moment the map builder gets', () {
    _screenTest('colors are the day colours, then the night colours with '
        'the flow\'s night mode', (tester, s) async {
      await s.mount(tester, dayColors: _dayColours, nightColors: _nightColours);
      await s.drive(tester);
      expect(s.last.colors, same(_dayColours));
      s.h.flow.nightMode = NightMode.alwaysNight;
      await s.frames(tester);
      expect(s.last.colors, same(_nightColours));
      s.h.flow.nightMode = NightMode.alwaysDay;
      await s.frames(tester);
      expect(s.last.colors, same(_dayColours));
    });

    _screenTest('routeColors fall back to the alternative and accent of '
        'the colours of the moment', (tester, s) async {
      await s.mount(tester, dayColors: _dayColours, nightColors: _nightColours);
      await s.drive(tester);
      expect(s.last.routeColors.driven, _dayColours.alternative);
      expect(s.last.routeColors.ahead, _dayColours.accent);
      s.h.flow.nightMode = NightMode.alwaysNight;
      await s.frames(tester);
      expect(s.last.routeColors.driven, _nightColours.alternative);
      expect(s.last.routeColors.ahead, _nightColours.accent);
    });

    _screenTest('dayRouteColors and nightRouteColors override the fallback, '
        'each in its own mode', (tester, s) async {
      const day = RouteColors(
        driven: Color(0xFF111111),
        ahead: Color(0xFF222222),
        drivenWidth: 3,
        aheadWidth: 4,
      );
      const night = RouteColors(
        driven: Color(0xFF333333),
        ahead: Color(0xFF444444),
      );
      await s.mount(
        tester,
        dayColors: _dayColours,
        nightColors: _nightColours,
        dayRouteColors: day,
        nightRouteColors: night,
      );
      await s.drive(tester);
      expect(s.last.routeColors, same(day));
      s.h.flow.nightMode = NightMode.alwaysNight;
      await s.frames(tester);
      expect(s.last.routeColors, same(night));
    });

    _screenTest('only the day override set: at night the colours of the '
        'night are the fallback, not the day override', (tester, s) async {
      const day = RouteColors(driven: Color(0xFF111111));
      await s.mount(
        tester,
        dayColors: _dayColours,
        nightColors: _nightColours,
        dayRouteColors: day,
      );
      await s.drive(tester);
      expect(s.last.routeColors, same(day));
      s.h.flow.nightMode = NightMode.alwaysNight;
      await s.frames(tester);
      expect(s.last.routeColors.driven, _nightColours.alternative);
      expect(s.last.routeColors.ahead, _nightColours.accent);
    });

    _screenTest('routeLabel is the formatter\'s duration', (tester, s) async {
      const english = EnglishGuidanceFormatter();
      const vietnamese = VietnameseGuidanceFormatter();
      final duration = Duration(seconds: sampleRoute.duration.round());
      expect(english.duration(duration), isNot(vietnamese.duration(duration)));
      await s.mount(tester, formatter: vietnamese);
      await s.drive(tester);
      expect(s.last.routeLabel!(sampleRoute), vietnamese.duration(duration));
    });

    _screenTest('alternateLabel is the strings\' faster, slower or similar '
        'text', (tester, s) async {
      const vietnamese = NavigationStrings.vietnamese();
      await s.mount(tester, strings: vietnamese);
      await s.drive(tester);
      AlternateRoute by(int seconds) => AlternateRoute(
        route: sampleRoute,
        timeDelta: Duration(seconds: seconds),
        divergence: 0,
      );
      final label = s.last.alternateLabel!;
      expect(label(by(-120)), vietnamese.minFaster(2));
      expect(label(by(180)), vietnamese.minSlower(3));
      expect(label(by(10)), vietnamese.similarEta);
      expect(vietnamese.minFaster(2), isNot(strings.minFaster(2)));
    });
  });

  group('alternates, through AlternateRoutesMap on the session map', () {
    _screenTest('are drawn while navigating, a tap switches to one and '
        're-follows, and they are cleared at the end', (tester, s) async {
      final alt = sampleRouteAlternatives.single;
      await s.mount(tester);
      await s.drive(tester, routes: [sampleRoute, alt], from: 100);
      final map = s.h.recording;
      expect(map.shownAlternates, isNotNull);
      expect(map.shownAlternates!.single.route, same(alt));
      s.h.session.follow = false;
      map.alternateTap!(0);
      await s.frames(tester);
      expect((s.h.flow.state.value as FlowNavigating).route, same(alt));
      expect(s.h.session.follow, isTrue);
      s.h.flow.stop();
      await s.frames(tester);
      expect(map.shownAlternates, isNull);
    });
  });

  group('search pins, through SearchPinsMap on the session map', () {
    Future<void> openAndSearch(WidgetTester tester, _Screen s) async {
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await tester.pump();
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      await tester.tap(find.byKey(_gas));
      await tester.pump();
      await tester.pump();
    }

    _screenTest('are shown with the results, follow the focus, and are '
        'cleared on close', (tester, s) async {
      s.places = const [_fuel, _cafe];
      await s.mount(tester);
      await s.drive(tester);
      final map = s.h.map as _PinsMap;
      await openAndSearch(tester, s);
      expect(s.searches.single.route, same(sampleRoute));
      expect(map.places, [_fuel, _cafe]);
      expect(map.focusedId, isNull);
      await tester.tap(find.text(_fuel.name));
      await s.frames(tester);
      expect(map.focusedId, 'fuel');
      expect(s.h.session.follow, isFalse);
      expect(map.cameraMoves.last.position, _fuel.position);
      // A tap on a pin focuses its place.
      map.onTap!(_cafe);
      await s.frames(tester);
      expect(map.focusedId, 'cafe');
      expect(map.cameraMoves.last.position, _cafe.position);
      final clears = map.clears;
      await tester.tap(find.byTooltip(strings.cancel));
      await s.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(map.clears, greaterThan(clears));
      expect(map.places, isNull);
      expect(s.h.session.follow, isTrue);
    }, map: _PinsMap.new);

    _screenTest('are cleared when navigation ends', (tester, s) async {
      s.places = const [_fuel];
      await s.mount(tester);
      await s.drive(tester);
      final map = s.h.map as _PinsMap;
      await openAndSearch(tester, s);
      expect(map.places, [_fuel]);
      s.h.flow.stop();
      await s.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(map.places, isNull);
    }, map: _PinsMap.new);

    _screenTest('a camera that throws at once is reported, and the tap '
        'still focuses the place', (tester, s) async {
      s.places = const [_fuel, _cafe];
      final errors = collectFlutterErrors();
      await s.mount(tester);
      await s.drive(tester);
      final map = s.h.map as _PinsMap;
      await openAndSearch(tester, s);
      await tester.tap(find.text(_fuel.name));
      await s.frames(tester);
      expect(map.focusedId, 'fuel');
      expect(s.h.session.follow, isFalse);
      final boom = errors.where((e) => e.exception is StateError);
      expect(boom, hasLength(1));
      expect(boom.single.library, 'navigation_engine_flutter');
      // A pin tap goes the same way and the screen keeps working.
      map.onTap!(_cafe);
      await s.frames(tester);
      expect(map.focusedId, 'cafe');
      expect(errors.where((e) => e.exception is StateError), hasLength(2));
      expect(errors.where((e) => e.exception is! StateError), isEmpty);
    }, map: _SyncThrowMap.new);

    for (final (name, set, message)
        in <(String, void Function(_FailingMap), String)>[
          ('showSearchPins throws at once', (m) => m.showThrows = true, 'show'),
          (
            'showSearchPins returns a failed future',
            (m) => m.showFails = true,
            'show failed',
          ),
          (
            'the camera returns a failed future',
            (m) => m.cameraFails = true,
            'camera failed',
          ),
        ]) {
      _screenTest('$name: it is reported, and the focus still happens', (
        tester,
        s,
      ) async {
        s.places = const [_fuel, _cafe];
        final errors = collectFlutterErrors();
        await s.mount(tester);
        await s.drive(tester);
        final map = s.h.map as _FailingMap;
        await openAndSearch(tester, s);
        set(map);
        await tester.tap(find.text(_fuel.name));
        await s.frames(tester);
        expect(s.h.session.follow, isFalse);
        expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
        final reported = errors.where((e) => e.exception is StateError);
        expect(reported.map((e) => e.toString()), [contains(message)]);
        expect(reported.single.library, 'navigation_engine_flutter');
        expect(errors.where((e) => e.exception is! StateError), isEmpty);
      }, map: _FailingMap.new);
    }

    _screenTest('clearSearchPins throws: it is reported, and the search '
        'still closes', (tester, s) async {
      s.places = const [_fuel];
      final errors = collectFlutterErrors();
      await s.mount(tester);
      await s.drive(tester);
      final map = s.h.map as _FailingMap;
      await openAndSearch(tester, s);
      map.clearThrows = true;
      await tester.tap(find.byTooltip(strings.cancel));
      await s.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(s.h.session.follow, isTrue);
      final reported = errors.where((e) => e.exception is StateError);
      expect(reported, isNotEmpty);
      expect(
        reported.every((e) => e.library == 'navigation_engine_flutter'),
        isTrue,
      );
    }, map: _FailingMap.new);

    _screenTest('a map that is not a SearchPinsMap: the search works and '
        'nothing throws', (tester, s) async {
      s.places = const [_fuel];
      await s.mount(tester);
      await s.drive(tester);
      expect(s.h.map, isNot(isA<SearchPinsMap>()));
      await openAndSearch(tester, s);
      expect(find.text(_fuel.name), findsOneWidget);
      await tester.tap(find.text(_fuel.name));
      await s.frames(tester);
      expect(s.h.recording.cameraMoves.last.position, _fuel.position);
      await tester.tap(find.byTooltip(strings.cancel));
      await s.frames(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the system back closes the open layer first', () {
    _screenTest('one layer per back: the pill, then the search, then the '
        'screen', (tester, s) async {
      await s.mount(tester, pushed: true);
      await s.drive(tester);
      await tester.tap(find.byTooltip(strings.searchAlongRoute));
      await tester.pump();
      await tester.tap(find.byType(GoogleStyleSoundButton));
      await tester.pump();
      expect(find.byKey(_pill), findsOneWidget);
      await s.back(tester);
      expect(find.byKey(_pill), findsNothing);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsOneWidget);
      s.h.session.follow = false;
      await s.back(tester);
      expect(find.byType(GoogleStyleSearchAlongRoute), findsNothing);
      expect(find.byType(GoogleStyleFlowScaffold), findsOneWidget);
      expect(s.h.session.follow, isTrue);
      await s.back(tester);
      expect(find.byType(GoogleStyleFlowScaffold), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    _screenTest('the expanded trip sheet menu', (tester, s) async {
      await s.mount(tester, pushed: true);
      await s.drive(tester);
      await tester.tap(find.byKey(_centre));
      await s.settle(tester);
      expect(find.text(strings.directions), findsOneWidget);
      await s.back(tester);
      await s.settle(tester);
      expect(find.text(strings.directions), findsNothing);
      expect(find.byType(GoogleStyleFlowScaffold), findsOneWidget);
    });
  });

  group('layout smoke', () {
    for (final (name, size) in [
      ('portrait', const Size(412, 915)),
      ('landscape', const Size(915, 412)),
    ]) {
      _screenTest('$name: every state lays out without overflow', (
        tester,
        s,
      ) async {
        await s.mount(tester, size: size);
        expect(find.byKey(const ValueKey('fake_map')), findsOneWidget);
        s.h.flow.previewRoutes([sampleRoute, sampleRouteAlternatives.single]);
        await s.frames(tester);
        expect(find.byType(GoogleStyleOverviewPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
        s.h.flow.start();
        await tester.pump();
        await s.h.run(
          tester,
          4,
          fixAt: (t) => s.h.fixOn(sampleRoute, 500.0 + 10 * t),
        );
        expect(find.byType(GoogleStyleManeuverHeader), findsOneWidget);
        expect(find.byType(GoogleStyleTripSheet), findsOneWidget);
        expect(find.byType(GoogleStyleSpeedCluster), findsOneWidget);
        expect(find.byType(GoogleStyleControlStack), findsOneWidget);
        expect(tester.takeException(), isNull);
        s.h.flow.stop();
        await s.frames(tester);
        s.h.flow.previewRoutes([sampleRoute]);
        await tester.pump();
        s.h.flow.start();
        await s.h.arriveOn(tester, sampleRoute);
        await s.frames(tester);
        expect(find.byType(GoogleStyleArrivalSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
