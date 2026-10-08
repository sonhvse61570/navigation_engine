import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  group('NavigationStrings', () {
    test('default constructor creates English strings', () {
      const strings = NavigationStrings();
      expect(strings.start, 'Start');
      expect(strings.resume, 'Resume');
      expect(strings.steps, 'Steps');
    });

    test('via function works in English', () {
      const strings = NavigationStrings();
      expect(strings.via('A, B'), 'via A, B');
    });

    test('vietnamese constructor creates Vietnamese strings', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.start, 'Bắt đầu');
      expect(strings.resume, 'Tiếp tục');
      expect(strings.steps, 'Các bước');
    });

    test('vietnamese via function works', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.via('A'), 'qua A');
    });

    test('custom override works', () {
      const strings = NavigationStrings(start: 'Go');
      expect(strings.start, 'Go');
      expect(strings.resume, 'Resume');
    });

    test('the new English fields', () {
      const strings = NavigationStrings();
      expect(strings.mute, 'Mute');
      expect(strings.unmute, 'Unmute');
      expect(strings.reportIncident, 'Report');
      expect(strings.compass, 'Compass');
      expect(strings.northUp, 'North up');
      expect(strings.headingUp, 'Heading up');
    });

    test('the new Vietnamese fields', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.mute, 'Tắt tiếng');
      expect(strings.unmute, 'Bật tiếng');
      expect(strings.reportIncident, 'Báo cáo');
      expect(strings.compass, 'La bàn');
      expect(strings.northUp, 'Hướng bắc');
      expect(strings.headingUp, 'Theo hướng đi');
    });
  });
}
