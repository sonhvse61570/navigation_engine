import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine/testing.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

import 'support/fake_google_maps_platform.dart';

class _FakeFixSource implements FixSource {
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
  void add(NavFix fix) => _controller.add(fix);
}

const _needleKey = ValueKey('google_style_compass_needle');
const _fillKey = ValueKey('google_style_trip_progress_fill');

/// The rotation of the transform [finder] finds, in degrees.
double _degrees(WidgetTester tester, Finder finder) {
  final m = tester.widget<Transform>(finder).transform;
  return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
}

/// The smallest signed difference of two angles, in degrees.
double _diff(double a, double b) => ((a - b + 540) % 360) - 180;

/// A session and a flow on a fake clock, the fake Google platform, and the
/// drop-in with every control setting, on a 400x800 surface.
class _Harness {
  _Harness() {
    platform = FakeGoogleMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
    session = NavigationSession(fixes: source, clock: () => now);
    flow = NavigationFlowController(
      session: session,
      nightMode: NightMode.alwaysDay,
      clock: () => now,
    );
  }

  late final FakeGoogleMapsPlatform platform;
  final source = _FakeFixSource();
  late final NavigationSession session;
  late final NavigationFlowController flow;
  DateTime now = DateTime.utc(2026, 10, 7, 13);
  final formatter = const EnglishGuidanceFormatter();
  final strings = const NavigationStrings();

  Widget app({
    bool headerEnabled = true,
    bool footerEnabled = true,
    bool tripProgressBarEnabled = true,
    bool speedometerEnabled = true,
    bool speedLimitIconEnabled = true,
    bool recenterButtonEnabled = true,
    bool compassEnabled = true,
    bool routeOverviewButtonEnabled = true,
    ValueChanged<AudioGuidance>? onAudioGuidanceChanged,
    AudioGuidance audioGuidance = AudioGuidance.sound,
    ValueChanged<IncidentType>? onReportIncident,
    TextScaler? textScaler,
    double bottomInset = 0,
  }) => MaterialApp(
    builder: textScaler == null && bottomInset == 0
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
              padding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: child!,
          ),
    home: GoogleStyleNavigation(
      session: session,
      flow: flow,
      initialCenter: sampleRoute.points.first,
      speedLimitSignStyle: SpeedLimitSignStyle.us,
      headerEnabled: headerEnabled,
      footerEnabled: footerEnabled,
      tripProgressBarEnabled: tripProgressBarEnabled,
      speedometerEnabled: speedometerEnabled,
      speedLimitIconEnabled: speedLimitIconEnabled,
      recenterButtonEnabled: recenterButtonEnabled,
      compassEnabled: compassEnabled,
      routeOverviewButtonEnabled: routeOverviewButtonEnabled,
      audioGuidance: audioGuidance,
      onAudioGuidanceChanged: onAudioGuidanceChanged,
      onReportIncident: onReportIncident,
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    Widget? app,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app ?? this.app());
    platform.createView();
    await tester.pump();
  }

  NavFix fixOn(num s) => NavFix(
    position: sampleRoute.pointAt(s.toDouble()),
    accuracy: 5,
    speed: 10,
    heading: sampleRoute.bearingAt(s.toDouble()),
    time: now,
  );

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

  /// Previews the route, starts it and drives 4 s from 500 m; with
  /// [moved], the user has then moved the map, so the recenter button shows.
  Future<void> drive(
    WidgetTester tester, {
    bool moved = true,
    double from = 500,
  }) async {
    flow.previewRoutes([sampleRoute]);
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await run(tester, 4, fixAt: (s) => fixOn(from + 10 * s));
    if (moved) {
      session.follow = false;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
    session.dispose();
  }
}

void _controlsTest(
  String description,
  Future<void> Function(WidgetTester tester, _Harness h) body,
) {
  testWidgets(description, (tester) async {
    final h = _Harness();
    try {
      await body(tester, h);
    } finally {
      await h.end(tester);
    }
  });
}

void main() {
  const strings = NavigationStrings();

  final header = find.byType(GoogleStyleManeuverHeader);
  final footer = find.byType(GoogleStyleTripSheet);
  final bar = find.byType(GoogleStyleTripProgressBar);
  final speedometer = find.byType(GoogleStyleSpeedCluster);
  final bubble = find.byKey(const ValueKey('google_style_speedometer'));
  final limitSign = find.descendant(
    of: speedometer,
    matching: find.text(strings.speedLimit),
  );
  final recenter = find.byType(GoogleStyleRecenterButton);
  final compass = find.byType(GoogleStyleCompassButton);
  final overview = find.byTooltip(strings.routeOptions);
  final sound = find.byTooltip(strings.sound);
  final report = find.byType(GoogleStyleReportButton);

  group('toggles', () {
    _controlsTest('by default every control shows', (tester, h) async {
      await h.mount(tester);
      await h.drive(tester, moved: false);
      expect(header, findsOneWidget);
      expect(footer, findsOneWidget);
      expect(bar, findsOneWidget);
      expect(bubble, findsOneWidget);
      expect(limitSign, findsOneWidget, reason: 'the sample route has limits');
      expect(compass, findsOneWidget, reason: 'following');
      expect(recenter, findsNothing, reason: 'following');
      expect(overview, findsOneWidget);
      h.session.follow = false;
      await h.run(tester, 0.1);
      expect(recenter, findsOneWidget, reason: 'moved away');
      expect(
        speedometer,
        findsNothing,
        reason: 'Re-center replaces the speed (D4)',
      );
      expect(sound, findsNothing, reason: 'no callback');
      expect(report, findsNothing, reason: 'no callback');
    });

    final cases = <String, ({Finder gone, Map<String, bool> flags})>{
      'headerEnabled': (gone: header, flags: {'headerEnabled': false}),
      'footerEnabled': (gone: footer, flags: {'footerEnabled': false}),
      'tripProgressBarEnabled': (
        gone: bar,
        flags: {'tripProgressBarEnabled': false},
      ),
      'speedometerEnabled': (
        gone: bubble,
        flags: {'speedometerEnabled': false},
      ),
      'speedLimitIconEnabled': (
        gone: limitSign,
        flags: {'speedLimitIconEnabled': false},
      ),
      'recenterButtonEnabled': (
        gone: recenter,
        flags: {'recenterButtonEnabled': false},
      ),
      'compassEnabled': (gone: compass, flags: {'compassEnabled': false}),
      'routeOverviewButtonEnabled': (
        gone: overview,
        flags: {'routeOverviewButtonEnabled': false},
      ),
    };
    for (final entry in cases.entries) {
      _controlsTest('${entry.key}: false hides it', (tester, h) async {
        final flags = entry.value.flags;
        await h.mount(
          tester,
          app: h.app(
            headerEnabled: flags['headerEnabled'] ?? true,
            footerEnabled: flags['footerEnabled'] ?? true,
            tripProgressBarEnabled: flags['tripProgressBarEnabled'] ?? true,
            speedometerEnabled: flags['speedometerEnabled'] ?? true,
            speedLimitIconEnabled: flags['speedLimitIconEnabled'] ?? true,
            recenterButtonEnabled: flags['recenterButtonEnabled'] ?? true,
            compassEnabled: flags['compassEnabled'] ?? true,
            routeOverviewButtonEnabled:
                flags['routeOverviewButtonEnabled'] ?? true,
          ),
        );
        // Recenter shows once the map was moved, the compass while following.
        await h.drive(tester, moved: entry.key == 'recenterButtonEnabled');
        expect(entry.value.gone, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    _controlsTest('the other controls stay when one is hidden', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        app: h.app(speedometerEnabled: false, footerEnabled: false),
      );
      await h.drive(tester, moved: false);
      expect(bubble, findsNothing);
      expect(limitSign, findsOneWidget, reason: 'only the speed is off');
      expect(footer, findsNothing);
      expect(header, findsOneWidget);
      expect(bar, findsOneWidget);
      expect(compass, findsOneWidget);
      h.session.follow = false;
      await h.run(tester, 0.1);
      expect(recenter, findsOneWidget);
    });

    _controlsTest('no speed slot when both speed pieces are off', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        app: h.app(speedometerEnabled: false, speedLimitIconEnabled: false),
      );
      await h.drive(tester);
      expect(speedometer, findsNothing);
      expect(footer, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _controlsTest('footerEnabled: false keeps the panel in the overview', (
      tester,
      h,
    ) async {
      await h.mount(tester, app: h.app(footerEnabled: false));
      await h.drive(tester);
      expect(footer, findsNothing);
      h.flow.backToOverview();
      await tester.pump();
      expect(find.byType(GoogleStyleOverviewPanel), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    _controlsTest('recenterButtonEnabled: false leaves no button', (
      tester,
      h,
    ) async {
      await h.mount(tester, app: h.app(recenterButtonEnabled: false));
      await h.drive(tester, moved: false);
      h.session.follow = false;
      await h.run(tester, 0.1);
      expect(recenter, findsNothing);
      expect(h.session.follow, isFalse);
    });
  });

  group('sound and report', () {
    _controlsTest('appear only with their callbacks and call them', (
      tester,
      h,
    ) async {
      final audio = <AudioGuidance>[];
      final reports = <IncidentType>[];
      await h.mount(
        tester,
        app: h.app(
          onAudioGuidanceChanged: audio.add,
          onReportIncident: reports.add,
        ),
      );
      await h.drive(tester, moved: false);
      expect(sound, findsOneWidget);
      expect(report, findsOneWidget);
      await tester.tap(sound);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('google_style_sound_option_muted')),
      );
      await tester.pump();
      expect(audio, [AudioGuidance.muted]);
      await tester.tap(report);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.byKey(const ValueKey('google_style_report_tile_crash')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(reports, [IncidentType.crash]);
    });

    _controlsTest('only the one with a callback shows', (tester, h) async {
      await h.mount(tester, app: h.app(onReportIncident: (_) {}));
      await h.drive(tester);
      expect(report, findsOneWidget);
      expect(sound, findsNothing);
    });

    _controlsTest('the sound icon follows audioGuidance', (tester, h) async {
      await h.mount(
        tester,
        app: h.app(
          onAudioGuidanceChanged: (_) {},
          audioGuidance: AudioGuidance.muted,
        ),
      );
      await h.drive(tester);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byTooltip(strings.muted), findsOneWidget);
      await tester.pumpWidget(h.app(onAudioGuidanceChanged: (_) {}));
      await tester.pump();
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });
  });

  group('GoogleStyleTripProgressBar', () {
    _controlsTest('in the screen it follows the trip fraction', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      await h.run(tester, 3, fixAt: (s) => h.fixOn(540 + 10 * s));
      final fraction = h.flow.tripProgress.value!.fraction;
      expect(fraction, greaterThan(0));
      final track = tester.getRect(bar);
      final fill = tester.getRect(find.byKey(_fillKey));
      expect(fill.height / track.height, closeTo(fraction, 0.01));
      // On the start edge, between the header and the footer.
      expect(track.left, lessThan(16));
      expect(track.top, greaterThanOrEqualTo(tester.getRect(header).bottom));
      expect(track.bottom, lessThanOrEqualTo(tester.getRect(footer).top));
    });
  });

  group('GoogleStyleRoundButton', () {
    testWidgets('shows its icon and tooltip and calls onPressed', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: GoogleStyleRoundButton(
              icon: const Icon(Icons.volume_up),
              tooltip: 'Sound',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byTooltip('Sound'), findsOneWidget);
      final size = tester.getSize(find.byType(GoogleStyleRoundButton));
      expect(size.width, size.height);
      expect(size.width, greaterThanOrEqualTo(48));
      await tester.tap(find.byType(GoogleStyleRoundButton));
      expect(taps, 1);
    });
  });

  group('GoogleStyleCompassButton', () {
    Future<void> pumpCompass(
      WidgetTester tester, {
      required double bearing,
      bool headingUp = true,
      VoidCallback? onPressed,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GoogleStyleCompassButton(
            bearing: bearing,
            headingUp: headingUp,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    );

    for (final bearing in [0.0, 90.0, 180.0, 300.0]) {
      testWidgets('bearing $bearing turns the needle by -bearing', (
        tester,
      ) async {
        await pumpCompass(tester, bearing: bearing);
        final angle = _degrees(tester, find.byKey(_needleKey));
        expect(_diff(angle, -bearing).abs(), lessThan(0.01));
      });
    }

    testWidgets('the tooltip names what a tap switches to', (tester) async {
      await pumpCompass(tester, bearing: 0);
      expect(find.byTooltip(strings.northUp), findsOneWidget);
      await pumpCompass(tester, bearing: 0, headingUp: false);
      expect(find.byTooltip(strings.headingUp), findsOneWidget);
    });

    testWidgets('screen readers get one label: the tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCompass(tester, bearing: 0);
      final node = tester.getSemantics(find.byType(IconButton));
      expect(node.label, isEmpty);
      expect(node.tooltip, strings.northUp);
      expect(find.bySemanticsLabel(strings.compass), findsNothing);
      handle.dispose();
    });

    testWidgets('a tap calls onPressed', (tester) async {
      var taps = 0;
      await pumpCompass(tester, bearing: 10, onPressed: () => taps++);
      await tester.tap(compass);
      expect(taps, 1);
    });

    _controlsTest('a tap flips the camera between heading up and north up', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, moved: false);
      expect(h.session.camera.headingUp, isTrue);
      expect(find.byTooltip(strings.northUp), findsOneWidget);

      await tester.tap(compass);
      await tester.pump();
      expect(h.session.camera.headingUp, isFalse);
      expect(find.byTooltip(strings.headingUp), findsOneWidget);
      expect(_degrees(tester, find.byKey(_needleKey)).abs(), lessThan(0.01));

      await tester.tap(compass);
      await tester.pump();
      expect(h.session.camera.headingUp, isTrue);
      expect(find.byTooltip(strings.northUp), findsOneWidget);
    });

    _controlsTest('the needle follows the camera bearing frame by frame', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      // Through the left turn near 2000 m: the bearing changes by ~90 deg.
      await h.drive(tester, moved: false, from: 1950);
      Finder needle() => find.byKey(_needleKey);
      var last = _degrees(tester, needle());
      var changes = 0;
      for (var s = 0; s < 14; s++) {
        h.source.add(h.fixOn(1990 + 10.0 * s));
        for (var i = 0; i < 60; i++) {
          h.now = h.now.add(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
          final shown = _degrees(tester, needle());
          if (_diff(shown, last).abs() > 0.001) {
            // It only moves for a change of at least 1 degree.
            expect(_diff(shown, last).abs(), greaterThanOrEqualTo(1 - 1e-6));
            changes++;
            last = shown;
          }
          final frame = h.session.frame!;
          expect(
            _diff(shown, -frame.bearing).abs(),
            lessThan(1 + 1e-6),
            reason: 'within 1 degree of the camera at every frame',
          );
        }
      }
      expect(changes, greaterThan(2), reason: 'the bearing turned');
      expect(changes, lessThan(14 * 60), reason: 'not on every frame');
    });

    _controlsTest('north up keeps the needle up while the vehicle turns', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      h.session.camera.headingUp = false;
      await h.drive(tester, moved: false, from: 1950);
      for (var s = 0; s < 6; s++) {
        await h.run(tester, 1, fixAt: (_) => h.fixOn(1990 + 10.0 * s));
      }
      expect(_degrees(tester, find.byKey(_needleKey)).abs(), lessThan(0.01));
    });

    _controlsTest('it follows a headingUp change made without frames', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, moved: false, from: 1950);
      for (var s = 0; s < 6; s++) {
        await h.run(tester, 1, fixAt: (_) => h.fixOn(1990 + 10.0 * s));
      }
      final turned = _degrees(tester, find.byKey(_needleKey));
      expect(turned.abs(), greaterThan(1), reason: 'heading up, turned');
      var frames = 0;
      final sub = h.session.frames.listen((_) => frames++);
      addTearDown(sub.cancel);
      // The app switches the camera; no time passes, so the session sends
      // no frame.
      h.session.camera.headingUp = false;
      await tester.pump();
      await tester.pump();
      expect(frames, 0, reason: 'no frame flowed');
      expect(_degrees(tester, find.byKey(_needleKey)).abs(), lessThan(0.01));
      expect(find.byTooltip(strings.headingUp), findsOneWidget);
    });

    _controlsTest('it stops listening when it leaves the screen', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, moved: false);
      expect(compass, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // A frame after the screen is gone must not reach a dead state; the
      // camera switch would make a live compass rebuild.
      h.session.camera.headingUp = false;
      h.source.add(h.fixOn(600));
      h.session.tick(0.016);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('compass visibility', () {
    _controlsTest('shown while following, hidden once the map is moved', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester, moved: false);
      expect(h.session.follow, isTrue);
      expect(compass, findsOneWidget);
      expect(recenter, findsNothing);

      // A drag on the map: the map view stops following.
      await tester.drag(
        find.byType(GoogleMapsNavigationView),
        const Offset(0, 60),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.session.follow, isFalse);
      expect(compass, findsNothing);
      expect(recenter, findsOneWidget);

      await tester.tap(recenter);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.session.follow, isTrue);
      expect(compass, findsOneWidget);
      expect(recenter, findsNothing);
    });
  });

  group('safe area', () {
    _controlsTest('footerEnabled: false keeps the bottom inset', (
      tester,
      h,
    ) async {
      await h.mount(tester, app: h.app(footerEnabled: false, bottomInset: 34));
      await h.drive(tester, moved: false);
      expect(footer, findsNothing);
      final speed = tester.getRect(speedometer);
      expect(speed.bottom, closeTo(800 - 34 - 16, 1));
      expect(speed.bottom, lessThanOrEqualTo(800 - 34 - 16 + 1));
      // The edge bar stops above the inset too.
      expect(tester.getRect(bar).bottom, lessThanOrEqualTo(800 - 34 - 16 + 1));
    });

    _controlsTest('with the footer, it already sits above the inset', (
      tester,
      h,
    ) async {
      await h.mount(tester, app: h.app(bottomInset: 34));
      await h.drive(tester, moved: false);
      expect(tester.getRect(footer).bottom, closeTo(800, 1));
      expect(
        tester.getRect(speedometer).bottom,
        closeTo(tester.getRect(footer).top - 16, 1),
      );
    });
  });

  group('layout', () {
    _controlsTest('recenter sits at the bottom start, above the footer', (
      tester,
      h,
    ) async {
      await h.mount(tester);
      await h.drive(tester);
      final button = tester.getRect(recenter);
      final footerRect = tester.getRect(footer);
      expect(button.center.dx, lessThan(400 / 2), reason: 'left of centre');
      expect(button.left, closeTo(16, 1));
      expect(
        button.bottom,
        closeTo(footerRect.top - 16, 1),
        reason: 'in the speed slot (D4)',
      );
      expect(speedometer, findsNothing);
    });

    _controlsTest('a speedometer that shows nothing leaves no space', (
      tester,
      h,
    ) async {
      // The limit sign alone, on a route without speed limits: the piece
      // shows nothing.
      await h.mount(tester, app: h.app(speedometerEnabled: false));
      final noLimits = NavRoute.fromPoints(sampleRoute.points);
      h.flow.previewRoutes([noLimits]);
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      await h.run(tester, 4, fixAt: (s) => h.fixOn(500 + 10 * s));
      expect(tester.getSize(speedometer), Size.zero);
      h.session.follow = false;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final button = tester.getRect(recenter);
      expect(button.bottom, closeTo(tester.getRect(footer).top - 16, 1));
    });

    // The Google look fix round 2: one end column anchored above the
    // footer: the report, the compass, sound, then route options.
    _controlsTest('the end column above the footer: report, compass, sound, '
        'route options', (tester, h) async {
      await h.mount(
        tester,
        app: h.app(onAudioGuidanceChanged: (_) {}, onReportIncident: (_) {}),
      );
      await h.drive(tester, moved: false);
      final headerRect = tester.getRect(header);
      final c = tester.getRect(compass);
      final s = tester.getRect(sound);
      final r = tester.getRect(report);
      final o = tester.getRect(overview);
      expect(r.top, greaterThanOrEqualTo(headerRect.bottom));
      expect(c.top, closeTo(r.bottom + 16, 1));
      expect(s.top, closeTo(c.bottom + 16, 1));
      expect(o.top, closeTo(s.bottom + 16, 1));
      for (final rect in [r, c, s, o]) {
        expect(rect.right, closeTo(400 - 16, 1));
      }
      expect(o.bottom, closeTo(tester.getRect(footer).top - 16, 1));
    });

    _controlsTest('320 dp at 2x text with every control: no overflow', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        size: const Size(320, 640),
        app: h.app(
          onAudioGuidanceChanged: (_) {},
          onReportIncident: (_) {},
          textScaler: const TextScaler.linear(2),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'idle');
      await h.drive(tester, moved: false);
      expect(tester.takeException(), isNull, reason: 'navigating');
      void insideScreen(List<Finder> finders) {
        for (final finder in finders) {
          expect(finder, findsWidgets);
          final rect = tester.getRect(finder.first);
          expect(rect.left, greaterThanOrEqualTo(0), reason: '$finder $rect');
          expect(rect.right, lessThanOrEqualTo(320), reason: '$finder $rect');
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$finder $rect');
          expect(rect.bottom, lessThanOrEqualTo(640), reason: '$finder $rect');
        }
      }

      // Vertically: the controls keep clear of the header and the footer,
      // and of each other.
      void apart(Finder a, List<Finder> others) {
        final rect = tester.getRect(a);
        for (final other in others) {
          final o = tester.getRect(other.first);
          expect(rect.overlaps(o), isFalse, reason: '$a $rect / $other $o');
        }
      }

      // Deviation (B4, N22): for its first 5 s the report pill is too wide
      // beside the speed at 2x, so it is lifted above it and leaves no room
      // for even the compass. The pill is checked now, the compass once the
      // pill is a circle (D3).
      insideScreen([header, footer, bar, speedometer, report]);
      apart(report, [footer, speedometer]);
      await h.run(tester, 2, fixAt: (s) => h.fixOn(530 + 5 * s));
      expect(tester.takeException(), isNull, reason: 'the pill collapsed');
      insideScreen([header, footer, bar, speedometer, compass, report]);
      apart(speedometer, [header, footer]);
      apart(report, [footer, speedometer]);
      apart(compass, [header, footer, speedometer, report]);
      apart(bar, [header, footer]);
      h.session.follow = false;
      await h.run(tester, 0.1);
      expect(tester.takeException(), isNull, reason: 'moved away');
      insideScreen([header, footer, bar, recenter, report]);
      apart(recenter, [header, footer, report]);
      expect(speedometer, findsNothing);
      await h.run(tester, 2, fixAt: (s) => h.fixOn(540 + 10 * s));
      expect(tester.takeException(), isNull, reason: 'after more frames');
    });
  });
}
