import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/flow_harness.dart';

void main() {
  const label = PlaceLabel(name: 'Landmark 81', address: '720A Dien Bien Phu');

  test('PlaceLabel compares by value', () {
    expect(
      const PlaceLabel(name: 'A', address: 'B'),
      const PlaceLabel(name: 'A', address: 'B'),
    );
    expect(
      const PlaceLabel(name: 'A', address: 'B').hashCode,
      const PlaceLabel(name: 'A', address: 'B').hashCode,
    );
    expect(
      const PlaceLabel(name: 'A'),
      isNot(const PlaceLabel(name: 'A', address: 'B')),
    );
    expect(const PlaceLabel(name: 'A', address: 'B').toString(), contains('A'));
  });

  test('the states default to no destination', () {
    final route = northRoute();
    expect(FlowOverview([route], 0).destination, isNull);
    expect(FlowNavigating(route).destination, isNull);
    expect(FlowArrived(route).destination, isNull);
  });

  flowTest('previewRoutes carries the label through select, start and '
      'arrival', (tester, h) async {
    final route = northRoute();
    h.flow.previewRoutes([route, branchRoute(1500)], destination: label);
    expect((h.flow.state.value as FlowOverview).destination, label);
    h.flow.select(1);
    expect((h.flow.state.value as FlowOverview).destination, label);
    h.flow.select(0);
    h.flow.start();
    expect((h.flow.state.value as FlowNavigating).destination, label);
    await h.arriveOn(tester, route);
    expect(h.flow.state.value, isA<FlowArrived>());
    expect((h.flow.state.value as FlowArrived).destination, label);
  });

  late CountingRouteProvider provider;
  flowTest(
    'preview carries the label, and retry keeps it',
    (tester, h) async {
      final route = northRoute();
      provider.handler = (_, _) => Future.error(Exception('offline'));
      await h.flow.preview(
        to: route.points.last,
        from: route.points.first,
        destination: label,
      );
      expect(h.flow.state.value, isA<FlowError>());
      provider.handler = (_, _) async => [route];
      await h.flow.retry();
      expect((h.flow.state.value as FlowOverview).destination, label);
    },
    provider: () =>
        provider = CountingRouteProvider((_, _) async => const <NavRoute>[]),
  );

  flowTest('backToOverview and Resume keep the label', (tester, h) async {
    final route = northRoute();
    h.flow.previewRoutes([route], destination: label);
    h.flow.start();
    await h.run(tester, 2, fixAt: (s) => h.fixOn(route, 300.0 + 10 * s));
    h.flow.backToOverview();
    expect((h.flow.state.value as FlowOverview).destination, label);
    h.flow.start();
    expect((h.flow.state.value as FlowNavigating).destination, label);
  });

  flowTest(
    'a reroute keeps the label',
    (tester, h) async {
      final route = northRoute();
      h.flow.previewRoutes([route], destination: label);
      h.flow.start();
      await h.run(tester, 6, fixAt: (s) => h.offRoute(route, s));
      await h.run(tester, 0.5);
      final state = h.flow.state.value as FlowNavigating;
      expect(state.route, isNot(same(route)));
      expect(state.destination, label);
    },
    provider: () => CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to]),
      ],
    ),
  );

  flowTest('a new trip without a label has none; stop forgets the old', (
    tester,
    h,
  ) async {
    final route = northRoute();
    h.flow.previewRoutes([route], destination: label);
    h.flow.start();
    h.flow.stop();
    h.flow.previewRoutes([route]);
    expect((h.flow.state.value as FlowOverview).destination, isNull);
    h.flow.start();
    expect((h.flow.state.value as FlowNavigating).destination, isNull);
  });

  flowTest(
    'after stop, a requested preview without a label has none',
    (tester, h) async {
      final route = northRoute();
      final to = route.points.last;
      await h.flow.preview(
        to: to,
        from: route.points.first,
        destination: label,
      );
      expect((h.flow.state.value as FlowOverview).destination, label);
      h.flow.start();
      h.flow.stop();
      await h.flow.preview(to: to, from: route.points.first);
      expect((h.flow.state.value as FlowOverview).destination, isNull);
    },
    provider: () => CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to]),
      ],
    ),
  );

  flowTest('Resume after arriving in the trip overview goes straight to the '
      'arrival, with the label', (tester, h) async {
    final route = northRoute();
    h.flow.previewRoutes([route], destination: label);
    h.flow.start();
    h.flow.backToOverview();
    await h.arriveOn(tester, route);
    expect(h.session.guidanceState!.arrived, isTrue);
    expect(h.flow.state.value, isA<FlowOverview>());
    h.flow.start();
    final arrived = h.flow.state.value as FlowArrived;
    expect(arrived.destination, label);
  });

  late CountingRouteProvider failingPreview;
  flowTest(
    'a reroute while a request from the trip overview has failed keeps the '
    'label for the overview it returns to',
    (tester, h) async {
      final route = northRoute();
      h.flow.previewRoutes([route], destination: label);
      h.flow.start();
      h.flow.backToOverview();
      await h.flow.preview(to: route.points.first, from: route.points.last);
      final error = h.flow.state.value as FlowError;
      expect(error.previous, isA<FlowOverview>());
      // The vehicle leaves the route meanwhile: the session reroutes.
      await h.run(tester, 6, fixAt: (s) => h.offRoute(route, s));
      await h.run(tester, 0.5);
      expect(failingPreview.reroutes, 1);
      expect(h.flow.state.value, same(error), reason: 'the error stays');
      h.flow.cancel();
      final overview = h.flow.state.value as FlowOverview;
      expect(overview.route, isNot(same(route)), reason: 'the new route');
      expect(overview.destination, label);
      expect(h.flow.isTripOverview, isTrue);
    },
    provider: () => failingPreview = CountingRouteProvider(
      (from, to) async => [
        NavRoute.fromPoints([from, to]),
      ],
      routesHandler: (_, _) async => throw StateError('offline'),
    ),
  );
}
