import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  group('SpeedLimitSign', () {
    test('has exactly two values', () {
      expect(SpeedLimitSign.values.length, 2);
    });
  });
}
