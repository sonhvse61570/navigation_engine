import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'fake_google_maps_platform.dart';
import 'screenshots.dart';

/// A 1×1 PNG, for the label and pin painters (the fake platform draws
/// nothing).
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A fix source the test feeds by hand.
class DropInFixes implements FixSource {
  final _controller = StreamController<NavFix>.broadcast(sync: true);
  bool _running = false;
  @override
  Stream<NavFix> get fixes => _controller.stream;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void dispose() {}

  /// Sends [fix] to the listeners, synchronously.
  void add(NavFix fix) => _controller.add(fix);
}

/// A provider whose reroutes never complete.
class PendingReroutes extends RouteProvider {
  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) =>
      Completer<NavRoute>().future;
}

/// The drop-in with every callback, on the fake platform and a fake clock.
class DropInHarness {
  DropInHarness({
    RouteProvider? provider,
    NightMode nightMode = NightMode.alwaysDay,
  }) {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    session = NavigationSession(
      fixes: source,
      routeProvider: provider,
      clock: () => now,
    );
    flow = NavigationFlowController(
      session: session,
      routeProvider: provider,
      nightMode: nightMode,
      clock: () => now,
    );
  }

  late final FakeGoogleMapsPlatform platform;
  final source = DropInFixes();
  late final NavigationSession session;
  late final NavigationFlowController flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);

  /// The strings the drop-in shows; set by [mount].
  NavigationStrings strings = const NavigationStrings();

  AudioGuidance audio = AudioGuidance.sound;
  final audioChanges = <AudioGuidance>[];
  final reports = <IncidentType>[];
  final added = <AlongRoutePlace>[];
  final searches = <AlongRouteQuery>[];
  List<AlongRoutePlace> places = const [];
  var shares = 0;
  var settings = 0;

  GoogleMapsNavigationMap get map => session.map! as GoogleMapsNavigationMap;

  /// The app around the drop-in, inside a [RepaintBoundary] keyed [shotKey].
  /// [strings] defaults to the harness's [strings]. When [pushed], the home
  /// page is a "HOME" button that pushes the drop-in.
  Widget app({
    bool pushed = false,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
    bool callbacks = true,
    bool reportButtonEnabled = true,
    bool searchButtonEnabled = true,
    bool routeOverviewButtonEnabled = true,
    bool tripProgressBarEnabled = false,
    NavigationStrings? strings,
    WidgetBuilder? idleBuilder,
  }) => MaterialApp(
    builder: (context, child) => RepaintBoundary(
      key: shotKey,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
    ),
    home: pushed
        ? Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _screen(
                      strings: strings,
                      idleBuilder: idleBuilder,
                      reportButtonEnabled: reportButtonEnabled,
                      searchButtonEnabled: searchButtonEnabled,
                      routeOverviewButtonEnabled: routeOverviewButtonEnabled,
                      tripProgressBarEnabled: tripProgressBarEnabled,
                      callbacks: callbacks,
                    ),
                  ),
                ),
                child: const Text('HOME'),
              ),
            ),
          )
        : _screen(
            strings: strings,
            idleBuilder: idleBuilder,
            reportButtonEnabled: reportButtonEnabled,
            searchButtonEnabled: searchButtonEnabled,
            routeOverviewButtonEnabled: routeOverviewButtonEnabled,
            tripProgressBarEnabled: tripProgressBarEnabled,
            callbacks: callbacks,
          ),
  );

  Widget _screen({
    required NavigationStrings? strings,
    required WidgetBuilder? idleBuilder,
    required bool reportButtonEnabled,
    required bool searchButtonEnabled,
    required bool routeOverviewButtonEnabled,
    required bool tripProgressBarEnabled,
    required bool callbacks,
  }) => StatefulBuilder(
    builder: (context, setState) => GoogleStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      strings: strings ?? this.strings,
      idleBuilder: idleBuilder,
      reportButtonEnabled: reportButtonEnabled,
      searchButtonEnabled: searchButtonEnabled,
      routeOverviewButtonEnabled: routeOverviewButtonEnabled,
      tripProgressBarEnabled: tripProgressBarEnabled,
      audioGuidance: audio,
      onAudioGuidanceChanged: callbacks
          ? (a) {
              audioChanges.add(a);
              setState(() => audio = a);
            }
          : null,
      onReportIncident: callbacks ? reports.add : null,
      searchAlongRoute: callbacks
          ? (q) async {
              searches.add(q);
              return places;
            }
          : null,
      onAddStop: callbacks ? added.add : null,
      onShareTrip: callbacks ? () => shares++ : null,
      onSettings: callbacks ? () => settings++ : null,
    ),
  );

  /// Pumps [app] on a [size] view at device pixel ratio 1, with [insets] as
  /// the view's padding, and creates the map view.
  Future<void> mount(
    WidgetTester tester, {
    bool pushed = false,
    Size size = const Size(400, 800),
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
    bool callbacks = true,
    bool reportButtonEnabled = true,
    bool searchButtonEnabled = true,
    bool routeOverviewButtonEnabled = true,
    bool tripProgressBarEnabled = false,
    FakeViewPadding? insets,
    NavigationStrings strings = const NavigationStrings(),
    WidgetBuilder? idleBuilder,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    if (insets != null) {
      tester.view
        ..padding = insets
        ..viewPadding = insets;
    }
    addTearDown(tester.view.reset);
    this.strings = strings;
    await tester.pumpWidget(
      app(
        pushed: pushed,
        scale: scale,
        direction: direction,
        callbacks: callbacks,
        reportButtonEnabled: reportButtonEnabled,
        searchButtonEnabled: searchButtonEnabled,
        routeOverviewButtonEnabled: routeOverviewButtonEnabled,
        tripProgressBarEnabled: tripProgressBarEnabled,
        strings: strings,
        idleBuilder: idleBuilder,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('HOME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    platform.createView();
    await tester.pump();
    map
      ..labelPainter = ((
        text, {
        required selected,
        required pixelRatio,
        required colors,
      }) async => onePixelPng)
      ..pinPainter = ({
        required focused,
        required pixelRatio,
        required color,
      }) async => onePixelPng;
  }

  /// A fix [s] m along [route], heading along it.
  NavFix fixOn(NavRoute route, double s, {double speed = 10}) => NavFix(
    position: route.pointAt(s),
    accuracy: 5,
    speed: speed,
    heading: route.bearingAt(s),
    time: now,
  );

  /// Runs [seconds] of 16 ms frames; the view ticks the session.
  Future<void> run(
    WidgetTester tester,
    double seconds, {
    NavFix? Function(int second)? fixAt,
  }) async {
    final frames = (seconds * 60).round();
    for (var i = 0; i < frames; i++) {
      if (i % 60 == 0) {
        final fix = fixAt?.call(i ~/ 60);
        if (fix != null) source.add(fix);
      }
      now = now.add(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Previews [routes], starts the first and drives 4 s from [from] m.
  Future<void> drive(
    WidgetTester tester, {
    List<NavRoute>? routes,
    double from = 500,
    PlaceLabel? destination,
  }) async {
    final all = routes ?? [sampleRoute];
    flow.previewRoutes(all, destination: destination);
    await tester.pump();
    flow.start();
    await tester.pump();
    await run(tester, 4, fixAt: (s) => fixOn(all.first, from + 10 * s));
  }

  /// Two 16 ms frames, so the overlays follow a change.
  Future<void> frames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// 40 frames of 16 ms (640 ms): the trip sheet's tap animation or its
  /// release spring settles, and the overlays follow.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Unmounts the drop-in and disposes the flow and the session.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  }
}

/// A widget test with a fresh [DropInHarness], ended after [body].
void dropInTest(
  String description,
  Future<void> Function(WidgetTester tester, DropInHarness h) body, {
  RouteProvider Function()? provider,
  NightMode nightMode = NightMode.alwaysDay,
  bool skip = false,
}) => testWidgets(description, (tester) async {
  final h = DropInHarness(provider: provider?.call(), nightMode: nightMode);
  try {
    await body(tester, h);
  } finally {
    await h.end(tester);
  }
}, skip: skip);
