import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/flow_harness.dart';

void main() {
  /// Starts [route] and drives 2 s from 300 m.
  Future<void> drive(WidgetTester tester, FlowHarness h, NavRoute route) async {
    h.flow.previewRoutes([route]);
    h.flow.start();
    await h.run(tester, 2, fixAt: (s) => h.fixOn(route, 300.0 + 10 * s));
  }

  flowTest('previewStep moves the camera once to the step, follow off', (
    tester,
    h,
  ) async {
    final route = northRoute();
    await drive(tester, h, route);
    final before = h.recording.cameraMoves.length;
    h.flow.previewStep(2);
    await tester.pump();
    expect(h.flow.previewedStep.value, 2);
    expect(h.session.follow, isFalse);
    expect(h.recording.cameraMoves, hasLength(before + 1));
    final step = route.steps[2];
    final target = h.recording.cameraMoves.last;
    expect(
      distanceBetween(target.position, route.pointAt(step.distance)),
      lessThan(0.01),
    );
    expect(target.bearing, closeTo(route.bearingAt(step.distance), 1e-9));
    expect(target.zoom, NavigationFlowController.stepPreviewZoom);
    expect(target.zoom, 17);
    expect(target.tilt, 45);
    // Frames go on without moving the camera while it previews.
    await h.run(tester, 1, fixAt: (s) => h.fixOn(route, 330.0 + 10 * s));
    expect(h.recording.cameraMoves, hasLength(before + 1));
  });

  flowTest('the preview ends 10 s after the last interaction', (
    tester,
    h,
  ) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.flow.previewStep(1);
    await tester.pump(const Duration(seconds: 9));
    expect(h.flow.previewedStep.value, 1);
    // Another preview is an interaction: the 10 s start again.
    h.flow.previewStep(2);
    await tester.pump(const Duration(seconds: 9));
    expect(h.flow.previewedStep.value, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue);
  });

  flowTest('Re-center (follow back on) ends the preview', (tester, h) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.flow.previewStep(1);
    await tester.pump();
    h.session.follow = true;
    await tester.pump();
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue);
  });

  flowTest('endStepPreview turns follow back on; without a preview it '
      'leaves follow alone', (tester, h) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.session.follow = false; // the user panned the map
    h.flow.endStepPreview();
    expect(h.session.follow, isFalse);
    h.flow.previewStep(1);
    h.flow.endStepPreview();
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue);
  });

  flowTest(
    'a reroute ends the preview',
    (tester, h) async {
      final route = northRoute();
      h.flow.previewRoutes([route]);
      h.flow.start();
      await h.run(tester, 1, fixAt: (s) => h.offRoute(route, s));
      h.flow.previewStep(3);
      await h.run(tester, 6, fixAt: (s) => h.offRoute(route, s + 1));
      await h.run(tester, 0.5);
      expect(
        (h.flow.state.value as FlowNavigating).route,
        isNot(same(route)),
        reason: 'rerouted',
      );
      expect(h.flow.previewedStep.value, isNull);
      expect(h.session.follow, isTrue);
    },
    provider: () => CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to]),
      ],
    ),
  );

  flowTest('endStepPreview(refollow: false) ends the preview and its timer '
      'without following', (tester, h) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.flow.previewStep(1);
    await tester.pump();
    // The user touched the map while it previewed.
    h.flow.endStepPreview(refollow: false);
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isFalse);
    await tester.pump(const Duration(seconds: 11));
    expect(h.session.follow, isFalse, reason: 'the timer was cancelled');
  });

  flowTest('arrival ends the preview', (tester, h) async {
    final route = northRoute();
    h.flow.previewRoutes([route]);
    h.flow.start();
    await h.run(tester, 1, fixAt: (s) => h.fixOn(route, route.length - 60));
    h.flow.previewStep(3);
    await h.arriveOn(tester, route);
    expect(h.flow.state.value, isA<FlowArrived>());
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue);
  });

  flowTest('stop and backToOverview end the preview', (tester, h) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.flow.previewStep(1);
    h.flow.backToOverview();
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isFalse, reason: 'the overview does not follow');
    h.flow.start();
    h.flow.previewStep(1);
    h.flow.stop();
    expect(h.flow.previewedStep.value, isNull);
    expect(h.session.follow, isTrue, reason: 'stop ends it as arrival does');
  });

  flowTest('a follow change queued before the preview began does not end '
      'it', (tester, h) async {
    final route = northRoute();
    h.flow.previewRoutes([route]);
    // start() turns follow on; its change is delivered after this frame,
    // when the preview has already turned follow off.
    h.flow.start();
    h.flow.previewStep(1);
    await tester.pump();
    await tester.pump();
    expect(h.flow.previewedStep.value, 1);
    expect(h.session.follow, isFalse);
  });

  flowTest('a session without a map still previews the step', (
    tester,
    h,
  ) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.session.map = null;
    h.flow.previewStep(2);
    expect(h.flow.previewedStep.value, 2);
    expect(h.session.follow, isFalse);
    await tester.pump(const Duration(seconds: 11));
    expect(h.flow.previewedStep.value, isNull, reason: 'the timer still runs');
  });

  flowTest('previewStep needs navigating and a valid index', (tester, h) async {
    final route = northRoute();
    expect(() => h.flow.previewStep(0), throwsStateError);
    h.flow.previewRoutes([route]);
    expect(() => h.flow.previewStep(0), throwsStateError);
    h.flow.start();
    expect(() => h.flow.previewStep(-1), throwsRangeError);
    expect(() => h.flow.previewStep(route.steps.length), throwsRangeError);
    expect(h.flow.previewedStep.value, isNull);
  });

  flowTest('a failing camera move is reported, not thrown', (tester, h) async {
    final original = FlutterError.onError;
    final errors = collectFlutterErrors();
    final route = northRoute();
    await drive(tester, h, route);
    h.recording.cameraError = StateError('no map');
    h.flow.previewStep(1);
    await tester.pump();
    // Restore before the expects, so a failing expect is not hidden by the
    // binding's check of the error handler.
    FlutterError.onError = original;
    expect(h.flow.previewedStep.value, 1);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<StateError>());
  });

  flowTest('dispose cancels a pending preview timer', (tester, h) async {
    final route = northRoute();
    await drive(tester, h, route);
    h.flow.previewStep(1);
    expect(h.flow.previewedStep.value, 1);
    // flowTest disposes the flow here; a timer still pending would fail the
    // test.
  });
}
