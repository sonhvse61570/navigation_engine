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

    test('copyWith changes only the given fields', () {
      const vi = NavigationStrings.vietnamese();
      final copy = vi.copyWith(start: 'Đi', via: (s) => 'ngang $s');
      expect(copy.start, 'Đi');
      expect(copy.via('A'), 'ngang A');
      expect(copy.resume, vi.resume);
      expect(copy.headingUp, vi.headingUp);
      expect(copy.speedLimit, vi.speedLimit);
      final same = vi.copyWith();
      for (final (name, read) in <(String, String Function(NavigationStrings))>[
        ('start', (s) => s.start),
        ('resume', (s) => s.resume),
        ('steps', (s) => s.steps),
        ('recenter', (s) => s.recenter),
        ('rerouting', (s) => s.rerouting),
        ('arrived', (s) => s.arrived),
        ('done', (s) => s.done),
        ('retry', (s) => s.retry),
        ('cancel', (s) => s.cancel),
        ('then', (s) => s.then),
        ('findingRoutes', (s) => s.findingRoutes),
        ('noRoute', (s) => s.noRoute),
        ('overview', (s) => s.overview),
        ('exitNavigation', (s) => s.exitNavigation),
        ('fastest', (s) => s.fastest),
        ('speedLimit', (s) => s.speedLimit),
        ('mute', (s) => s.mute),
        ('unmute', (s) => s.unmute),
        ('reportIncident', (s) => s.reportIncident),
        ('compass', (s) => s.compass),
        ('northUp', (s) => s.northUp),
        ('headingUp', (s) => s.headingUp),
        ('via', (s) => s.via('A')),
      ]) {
        expect(read(same), read(vi), reason: name);
      }
      // Each field can be set on its own.
      expect(vi.copyWith(compass: 'C').compass, 'C');
      expect(vi.copyWith(compass: 'C').northUp, vi.northUp);
      expect(vi.copyWith(northUp: 'N').northUp, 'N');
      expect(vi.copyWith(mute: 'M').mute, 'M');
      expect(vi.copyWith(exitNavigation: 'X').exitNavigation, 'X');
    });
  });
}
