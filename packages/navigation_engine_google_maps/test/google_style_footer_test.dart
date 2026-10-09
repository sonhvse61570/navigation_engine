import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

void main() {
  group('GoogleStyleRecenterButton', () {
    testWidgets('shows the label and calls back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(GoogleStyleRecenterButton(onPressed: () => taps++)),
      );
      expect(find.text('Re-center'), findsOneWidget);
      await tester.tap(find.text('Re-center'));
      expect(taps, 1);
    });
  });
}
