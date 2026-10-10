import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_geolocator_example/main.dart';

void main() {
  testWidgets('shows the empty state before the source starts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FixesScreen()));
    expect(find.text('No fix yet'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });
}
