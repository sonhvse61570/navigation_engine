// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';
import 'package:navigation_engine_google_maps/src/google_maps_navigation_map.dart'
    show toCameraPosition;

import 'support/fake_google_maps_platform.dart';

class FakeFixSource implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => true;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
  void add(NavFix fix) => _controller.add(fix);
}

NavFix fixAt(double meters) => NavFix(
  position: sampleRoute.pointAt(meters),
  accuracy: 5,
  speed: 10,
  heading: sampleRoute.bearingAt(meters),
  time: DateTime.now(),
);

Widget app(
  NavigationSession session, {
  Set<gm.Marker> markers = const {},
  Widget puck = const CarPuck(),
  VehicleImageBuilder? vehicleImage,
  RouteColors routeColors = const RouteColors(),
  String? style,
  bool showRecenterButton = true,
  String Function(NavRoute route)? routeLabel,
  void Function(int index)? onRouteOptionTap,
  Color? alternativeRouteColor,
  GoogleStyleColors? labelColors,
}) => MaterialApp(
  home: GoogleMapsNavigationView(
    session: session,
    initialCenter: sampleRoute.points.first,
    markers: markers,
    puck: puck,
    vehicleImage: vehicleImage,
    routeColors: routeColors,
    style: style,
    showRecenterButton: showRecenterButton,
    routeLabel: routeLabel,
    onRouteOptionTap: onRouteOptionTap,
    alternativeRouteColor: alternativeRouteColor,
    labelColors: labelColors,
  ),
);

/// The width of a PNG, from its IHDR chunk.
int pngWidth(Uint8List png) => ByteData.sublistView(png).getUint32(16);

/// Lets the real (non fake-async) PNG rendering finish.
Future<void> renderDone(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pump();
}

/// Shows the vehicle marker and returns its icon.
Future<gm.BitmapDescriptor> vehicleIcon(
  WidgetTester tester,
  NavigationSession session,
  FakeFixSource source,
  FakeGoogleMapsPlatform platform,
) async {
  source.add(fixAt(300));
  session.follow = false;
  await tester.pump(const Duration(milliseconds: 200));
  await frames(tester, 3);
  return platform.markers
      .singleWhere((m) => m.markerId.value == 'navigation_engine_vehicle')
      .icon;
}

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late FakeGoogleMapsPlatform platform;
  late FakeFixSource source;

  setUp(() {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    source = FakeFixSource();
  });

  testWidgets('the view attaches to the session and leaves it running when '
      'removed', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);

    await tester.pumpWidget(app(session));
    expect(session.map, isA<GoogleMapsNavigationMap>());
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.polylines.value, hasLength(2), reason: 'route drawn on attach');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(session.map, isNull);
    expect(session.isRunning, isTrue);

    final before = session.frame;
    source.add(fixAt(500));
    await frames(tester, 3);
    session.tick(0.016);
    expect(session.frame, isNotNull);
    expect(session.frame, isNot(same(before)));
  });

  testWidgets('a new session without a route clears the map', (tester) async {
    final first = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(first.dispose);
    await tester.pumpWidget(app(first));
    final map = first.map! as GoogleMapsNavigationMap;
    source.add(fixAt(300));
    first.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    expect(map.polylines.value, isNotEmpty);
    expect(map.vehicleMarker.value, isNotNull);

    final second = NavigationSession(fixes: FakeFixSource());
    addTearDown(second.dispose);
    await tester.pumpWidget(app(second));

    expect(first.map, isNull);
    expect(second.map, same(map));
    expect(map.polylines.value, isEmpty);
    expect(map.vehicleMarker.value, isNull);
  });

  testWidgets('the app markers and the vehicle marker are both drawn', (
    tester,
  ) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    const mine = gm.Marker(markerId: gm.MarkerId('mine'));
    await tester.pumpWidget(app(session, markers: {mine}));
    expect(platform.markers.map((m) => m.markerId.value), ['mine']);

    source.add(fixAt(300));
    session.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    expect(
      platform.markers.map((m) => m.markerId.value),
      containsAll(['mine', 'navigation_engine_vehicle']),
    );
  });

  testWidgets('camera updates start once the map exists', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;

    source.add(fixAt(200));
    await frames(tester, 5);
    expect(map.hasController, isFalse);
    expect(platform.cameraMoves, isEmpty);

    platform.createView();
    await tester.pump();
    expect(map.hasController, isTrue);

    source.add(fixAt(220));
    await frames(tester, 5);
    expect(platform.cameraMoves, isNotEmpty);
  });

  group('vehicle icon', () {
    testWidgets('a CarPuck is rendered at its size x the device ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const CarPuck(size: 30)));
      await renderDone(tester);

      final icon = await vehicleIcon(tester, session, source, platform);
      expect(icon, isA<gm.BytesMapBitmap>());
      final bytes = icon as gm.BytesMapBitmap;
      expect(bytes.imagePixelRatio, 2);
      expect(pngWidth(bytes.byteData), 60);
    });

    testWidgets('a ratio change re-renders the icon, a shown marker too', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, puck: const CarPuck(size: 30)));
      await renderDone(tester);
      await vehicleIcon(tester, session, source, platform);

      tester.view.devicePixelRatio = 3;
      await tester.pump();
      await renderDone(tester);
      await frames(tester, 2);

      final icon =
          platform.markers
                  .singleWhere(
                    (m) => m.markerId.value == 'navigation_engine_vehicle',
                  )
                  .icon
              as gm.BytesMapBitmap;
      expect(icon.imagePixelRatio, 3);
      expect(pngWidth(icon.byteData), 90);
    });

    testWidgets('a custom image builder gets the device ratio', (tester) async {
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final ratios = <double>[];
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        app(
          session,
          vehicleImage: (ratio) async {
            ratios.add(ratio);
            return Uint8List.fromList([1, 2, 3]);
          },
        ),
      );
      await tester.pump();
      expect(ratios, [2.5]);
    });

    testWidgets('a failing image builder keeps the default marker', (
      tester,
    ) async {
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        app(session, vehicleImage: (_) async => throw StateError('no image')),
      );
      await renderDone(tester);
      final icon = await vehicleIcon(tester, session, source, platform);
      expect(icon, gm.BitmapDescriptor.defaultMarker);
    });
  });

  testWidgets('routeColors changes restyle the drawn route', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    source.add(fixAt(300));
    session.follow = false;
    await tester.pump(const Duration(milliseconds: 200));
    await frames(tester, 3);
    Color colorOf(String id) =>
        map.polylines.value.singleWhere((p) => p.polylineId.value == id).color;
    expect(colorOf('navigation_engine_ahead'), const RouteColors().ahead);

    const red = Color(0xFFFF0000);
    await tester.pumpWidget(
      app(session, routeColors: const RouteColors(ahead: red)),
    );
    await tester.pump();

    expect(colorOf('navigation_engine_ahead'), red);
    expect(platform.lastObjects!.polylines.map((p) => p.color), contains(red));
  });
  testWidgets('style reaches the map configuration', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session, style: googleStyleNightMapStyle));
    expect(platform.mapConfiguration.style, googleStyleNightMapStyle);

    // Updates reach the platform once the native view exists.
    platform.createView();
    await tester.pump();
    await tester.pumpWidget(app(session, style: '[]'));
    await tester.pump();
    expect(platform.mapConfiguration.style, '[]');
  });

  testWidgets('route options are drawn with the route', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    ids() => platform.polylines.map((p) => p.polylineId.value).toSet();
    expect(ids(), isNot(contains('navigation_engine_option_0')));

    map.showRouteOptions([sampleRoute, ...sampleRouteAlternatives], 0);
    await tester.pump();
    expect(
      ids(),
      containsAll([
        'navigation_engine_option_0',
        'navigation_engine_option_1',
        'navigation_engine_option_casing_0',
        'navigation_engine_ahead',
      ]),
    );

    map.clearRouteOptions();
    await tester.pump();
    expect(ids(), isNot(contains('navigation_engine_option_0')));
  });

  testWidgets('the option labels are drawn with the app markers', (
    tester,
  ) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    const mine = gm.Marker(markerId: gm.MarkerId('mine'));
    await tester.pumpWidget(
      app(session, markers: {mine}, routeLabel: (r) => 'x'),
    );
    final map = session.map! as GoogleMapsNavigationMap
      ..labelPainter = (
        text, {
        required selected,
        required pixelRatio,
        required colors,
      }) async => Uint8List.fromList([1, 2, 3]);

    map.showRouteOptions([sampleRoute, ...sampleRouteAlternatives], 0);
    await tester.pump();
    await tester.pump();
    expect(
      platform.markers.map((m) => m.markerId.value),
      containsAll([
        'mine',
        'navigation_engine_option_label_0',
        'navigation_engine_option_label_1',
      ]),
    );
  });

  group('recenter button', () {
    Future<void> dragMap(WidgetTester tester) async {
      // The map takes pointers once its native view exists.
      platform.createView();
      await tester.pump();
      await tester.drag(find.byType(gm.GoogleMap), const Offset(0, -50));
      await tester.pump();
    }

    testWidgets('showRecenterButton false hides it', (tester) async {
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session, showRecenterButton: false));
      await dragMap(tester);
      expect(session.follow, isFalse);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Recenter'), findsNothing);
    });

    testWidgets('it is there by default', (tester) async {
      final session = NavigationSession(fixes: source)
        ..start(route: sampleRoute);
      addTearDown(session.dispose);
      await tester.pumpWidget(app(session));
      expect(find.byType(FloatingActionButton), findsNothing);
      await dragMap(tester);
      expect(session.follow, isFalse);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byTooltip('Recenter'), findsOneWidget);
    });
  });

  testWidgets('viewportSize follows the layout', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    Widget sized(Size size) => MaterialApp(
      home: Center(
        child: SizedBox.fromSize(
          size: size,
          child: GoogleMapsNavigationView(
            session: session,
            initialCenter: sampleRoute.points.first,
          ),
        ),
      ),
    );

    await tester.pumpWidget(sized(const Size(300, 600)));
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.viewportSize, const Size(300, 600));

    await tester.pumpWidget(sized(const Size(200, 400)));
    expect(map.viewportSize, const Size(200, 400));
  });

  testWidgets('the map padding is the focus padding of the frame', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 800,
            child: GoogleMapsNavigationView(
              session: session,
              initialCenter: sampleRoute.points.first,
            ),
          ),
        ),
      ),
    );
    platform.createView();
    await tester.pump();
    final map = session.map! as GoogleMapsNavigationMap;
    final routes = [sampleRoute, ...sampleRouteAlternatives];
    map.showRouteOptions(routes, 0);
    await map.fitRoutes(routes, EdgeInsets.zero);
    await tester.pump();

    final focus = focusPadding(const Size(400, 800), 0.7);
    expect(map.mapPadding.top, focus.top);
    expect(map.mapPadding, focus);
    expect(platform.mapConfiguration.padding, focus);
    final fitted = toCameraPosition(
      fitCameraToBounds(
        [for (final r in routes) ...r.points],
        const Size(400, 800),
        EdgeInsets.zero,
        mapPadding: focus,
      ),
    );
    final camera =
        (platform.cameraAnimations.last as gmp.CameraUpdateNewCameraPosition)
            .cameraPosition;
    expect(camera.target.latitude, closeTo(fitted.target.latitude, 1e-9));
    expect(camera.zoom, closeTo(fitted.zoom, 1e-9));
  });

  testWidgets('labelColors are forwarded; null keeps the map\'s', (
    tester,
  ) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.labelColors, GoogleStyleColors.day.routeLabelColors);

    await tester.pumpWidget(app(session, labelColors: GoogleStyleColors.night));
    expect(map.labelColors, GoogleStyleColors.night.routeLabelColors);

    await tester.pumpWidget(app(session));
    expect(map.labelColors, GoogleStyleColors.night.routeLabelColors);
  });

  testWidgets('routeLabel and onRouteOptionTap are forwarded', (tester) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    final taps = <int>[];
    await tester.pumpWidget(
      app(session, routeLabel: (r) => 'a', onRouteOptionTap: taps.add),
    );
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.routeLabel!(sampleRoute), 'a');
    map.onRouteOptionTap!(2);
    expect(taps, [2]);

    // A rebuild with new callbacks replaces them.
    final more = <int>[];
    await tester.pumpWidget(
      app(session, routeLabel: (r) => 'b', onRouteOptionTap: more.add),
    );
    expect(map.routeLabel!(sampleRoute), 'b');
    map.onRouteOptionTap!(1);
    expect(taps, [2]);
    expect(more, [1]);
  });

  testWidgets('alternativeRouteColor recolours the drawn options', (
    tester,
  ) async {
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    map.showRouteOptions([sampleRoute, ...sampleRouteAlternatives], 1);
    await tester.pump();
    Color drawn() => platform.polylines
        .singleWhere((p) => p.polylineId.value == 'navigation_engine_option_0')
        .color;
    expect(drawn(), const Color(0xFF9AA0A6));

    await tester.pumpWidget(
      app(session, alternativeRouteColor: const Color(0xFF123456)),
    );
    await tester.pump();
    expect(drawn(), const Color(0xFF123456));

    // Null keeps the colour the map has.
    await tester.pumpWidget(app(session));
    await tester.pump();
    expect(drawn(), const Color(0xFF123456));
  });

  testWidgets('the label pixel ratio is the device pixel ratio', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final session = NavigationSession(fixes: source)..start(route: sampleRoute);
    addTearDown(session.dispose);
    await tester.pumpWidget(app(session));
    final map = session.map! as GoogleMapsNavigationMap;
    expect(map.labelPixelRatio, 2.5);

    tester.view.devicePixelRatio = 3;
    await tester.pump();
    expect(map.labelPixelRatio, 3);
  });

  test('googleStyleNightMapStyle is valid JSON', () {
    final rules = jsonDecode(googleStyleNightMapStyle);
    expect(rules, isA<List<dynamic>>());
    expect((rules as List<dynamic>).length, greaterThanOrEqualTo(12));
    for (final rule in rules) {
      expect(rule, isA<Map<String, dynamic>>());
      expect((rule as Map<String, dynamic>)['stylers'], isNotEmpty);
    }
  });

  test('googleStyleNightMapStyle uses an original palette', () {
    const sample = [
      '#242f3e',
      '#38414e',
      '#212a37',
      '#746855',
      '#17263c',
      '#2f3948',
      '#515c6d',
      '#263c3f',
      '#1f2835',
    ];
    final style = googleStyleNightMapStyle.toLowerCase();
    for (final hex in sample) {
      expect(style, isNot(contains(hex)));
    }
  });
}
