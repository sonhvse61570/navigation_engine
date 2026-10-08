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
const _trackKey = ValueKey('google_style_trip_progress_track');
const _dotKey = ValueKey('google_style_trip_progress_dot');

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
    VoidCallback? onMuteToggle,
    bool muted = false,
    VoidCallback? onReportIncident,
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
      speedLimitSign: SpeedLimitSign.rectangular,
      headerEnabled: headerEnabled,
      footerEnabled: footerEnabled,
      tripProgressBarEnabled: tripProgressBarEnabled,
      speedometerEnabled: speedometerEnabled,
      speedLimitIconEnabled: speedLimitIconEnabled,
      recenterButtonEnabled: recenterButtonEnabled,
      compassEnabled: compassEnabled,
      routeOverviewButtonEnabled: routeOverviewButtonEnabled,
      onMuteToggle: onMuteToggle,
      muted: muted,
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
  const formatter = EnglishGuidanceFormatter();

  final header = find.byType(GoogleStyleManeuverHeader);
  final footer = find.byType(GoogleStyleTripFooter);
  final bar = find.byType(GoogleStyleTripProgressBar);
  final speedometer = find.byType(GoogleStyleSpeedometer);
  final bubble = find.descendant(
    of: speedometer,
    matching: find.text(formatter.speedUnit),
  );
  final limitSign = find.descendant(
    of: speedometer,
    matching: find.text(strings.speedLimit),
  );
  final recenter = find.byType(GoogleStyleRecenterButton);
  final compass = find.byType(GoogleStyleCompassButton);
  final overview = find.byTooltip(strings.overview);
  final mute = find.byTooltip(strings.mute);
  final unmute = find.byTooltip(strings.unmute);
  final report = find.byTooltip(strings.reportIncident);

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
      expect(mute, findsNothing, reason: 'no callback');
      expect(unmute, findsNothing, reason: 'no callback');
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
      var muteTaps = 0;
      var reportTaps = 0;
      await h.mount(
        tester,
        app: h.app(
          onMuteToggle: () => muteTaps++,
          onReportIncident: () => reportTaps++,
        ),
      );
      await h.drive(tester);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsNothing);
      expect(find.byIcon(Icons.report_outlined), findsOneWidget);
      expect(mute, findsOneWidget);
      expect(report, findsOneWidget);
      await tester.tap(mute);
      await tester.tap(report);
      expect(muteTaps, 1);
      expect(reportTaps, 1);
    });

    _controlsTest('only the one with a callback shows', (tester, h) async {
      await h.mount(tester, app: h.app(onReportIncident: () {}));
      await h.drive(tester);
      expect(report, findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.byIcon(Icons.volume_off), findsNothing);
    });

    _controlsTest('muted swaps the icon and the tooltip', (tester, h) async {
      await h.mount(tester, app: h.app(onMuteToggle: () {}, muted: true));
      await h.drive(tester);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(unmute, findsOneWidget);
      expect(mute, findsNothing);

      await tester.pumpWidget(h.app(onMuteToggle: () {}));
      await tester.pump();
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(mute, findsOneWidget);
    });
  });

  group('GoogleStyleTripProgressBar', () {
    Future<void> pumpBar(WidgetTester tester, double fraction) =>
        tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 200,
                child: GoogleStyleTripProgressBar(fraction: fraction),
              ),
            ),
          ),
        );

    for (final (fraction, expected) in [
      (0.0, 0.0),
      (0.25, 0.25),
      (1.0, 1.0),
      (-0.5, 0.0),
      (1.5, 1.0),
      (double.nan, 0.0),
    ]) {
      testWidgets('fraction $fraction fills $expected of the height', (
        tester,
      ) async {
        await pumpBar(tester, fraction);
        final track = tester.getRect(bar);
        expect(track.height, closeTo(200, 0.01));
        expect(track.width, closeTo(6, 0.01), reason: 'the default width');
        final fill = tester.getRect(find.byKey(_fillKey));
        expect(fill.height, closeTo(expected * 200, 1));
        expect(fill.width, closeTo(6, 0.01));
        expect(fill.bottom, closeTo(track.bottom, 0.01), reason: 'from below');
      });
    }

    for (final (fraction, expected) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)]) {
      testWidgets('the vehicle dot is centred at fraction $fraction', (
        tester,
      ) async {
        await pumpBar(tester, fraction);
        final track = tester.getRect(bar);
        final dot = tester.getRect(find.byKey(_dotKey));
        expect(dot.width, closeTo(12, 0.01), reason: 'width + 6');
        expect(dot.height, closeTo(12, 0.01));
        expect(
          dot.center.dx,
          closeTo(track.center.dx, 0.01),
          reason: 'centred',
        );
        expect(
          dot.center.dy,
          closeTo(track.bottom - expected * track.height, 1),
        );
        final decoration =
            tester.widget<DecoratedBox>(find.byKey(_dotKey)).decoration
                as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.color, GoogleStyleColors.day.surface);
        final border = decoration.border! as Border;
        expect(border.top.color, GoogleStyleColors.day.etaText);
        expect(border.top.width, 2);
      });
    }

    for (final (name, colors) in [
      ('day', GoogleStyleColors.day),
      ('night', GoogleStyleColors.night),
    ]) {
      testWidgets(
        '$name: etaText fills the driven part, alternative the rest',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: 200,
                  child: GoogleStyleTripProgressBar(
                    fraction: 0.5,
                    colors: colors,
                  ),
                ),
              ),
            ),
          );
          Color colorOf(Key key) =>
              (tester.widget<DecoratedBox>(find.byKey(key)).decoration
                      as BoxDecoration)
                  .color!;
          expect(colorOf(_fillKey), colors.etaText);
          expect(colorOf(_trackKey), colors.alternative);
          final decoration =
              tester.widget<DecoratedBox>(find.byKey(_dotKey)).decoration
                  as BoxDecoration;
          expect(decoration.color, colors.surface);
          expect((decoration.border! as Border).top.color, colors.etaText);
        },
      );
    }

    testWidgets('width sets the bar width', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 100,
              child: GoogleStyleTripProgressBar(fraction: 0.5, width: 10),
            ),
          ),
        ),
      );
      expect(tester.getRect(bar).width, closeTo(10, 0.01));
    });

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
      final speed = tester.getRect(speedometer);
      expect(button.center.dx, lessThan(400 / 2), reason: 'left of centre');
      expect(button.left, closeTo(16, 1));
      expect(button.bottom, lessThanOrEqualTo(footerRect.top - 16 + 1));
      expect(button.bottom, lessThanOrEqualTo(speed.top), reason: 'above');
      expect(speed.bottom, closeTo(footerRect.top - 16, 1));
    });

    _controlsTest('the compass, sound and report stack under the header', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        app: h.app(onMuteToggle: () {}, onReportIncident: () {}),
      );
      await h.drive(tester, moved: false);
      final headerRect = tester.getRect(header);
      final c = tester.getRect(compass);
      final m = tester.getRect(find.byType(GoogleStyleRoundButton).at(1));
      final r = tester.getRect(find.byType(GoogleStyleRoundButton).at(2));
      expect(c.top, greaterThanOrEqualTo(headerRect.bottom));
      expect(c.right, closeTo(400 - 16, 1));
      expect(m.top, closeTo(c.bottom + 8, 1));
      expect(r.top, closeTo(m.bottom + 8, 1));
    });

    _controlsTest('320 dp at 2x text with every control: no overflow', (
      tester,
      h,
    ) async {
      await h.mount(
        tester,
        size: const Size(320, 640),
        app: h.app(
          onMuteToggle: () {},
          onReportIncident: () {},
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
        }
      }

      insideScreen([header, footer, bar, speedometer, compass, mute, report]);
      h.session.follow = false;
      await h.run(tester, 0.1);
      expect(tester.takeException(), isNull, reason: 'moved away');
      insideScreen([header, footer, bar, speedometer, recenter, mute, report]);
      await h.run(tester, 2, fixAt: (s) => h.fixOn(540 + 10 * s));
      expect(tester.takeException(), isNull, reason: 'after more frames');
    });
  });
}
