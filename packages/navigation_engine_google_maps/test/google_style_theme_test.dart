import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

void main() {
  group('GoogleStyleColors', () {
    test('day colors have exact values', () {
      expect(GoogleStyleColors.day.guidance, const Color(0xFF1E8E3E));
      expect(GoogleStyleColors.day.guidanceSecondary, const Color(0xFF137333));
      expect(GoogleStyleColors.day.etaText, const Color(0xFF188038));
      expect(GoogleStyleColors.day.alternative, const Color(0xFF9AA0A6));
    });

    test('night colors have exact values', () {
      expect(GoogleStyleColors.night.guidance, const Color(0xFF0D652D));
      expect(
        GoogleStyleColors.night.guidanceSecondary,
        const Color(0xFF0A4D22),
      );
      expect(GoogleStyleColors.night.etaText, const Color(0xFF81C995));
      expect(GoogleStyleColors.night.alternative, const Color(0xFF5F6368));
    });
  });

  group('GoogleStyleStrings', () {
    test('default constructor creates English strings', () {
      const strings = GoogleStyleStrings();
      expect(strings.start, 'Start');
      expect(strings.resume, 'Resume');
      expect(strings.steps, 'Steps');
    });

    test('via function works in English', () {
      const strings = GoogleStyleStrings();
      expect(strings.via('A, B'), 'via A, B');
    });

    test('vietnamese constructor creates Vietnamese strings', () {
      const strings = GoogleStyleStrings.vietnamese();
      expect(strings.start, 'Bắt đầu');
      expect(strings.resume, 'Tiếp tục');
      expect(strings.steps, 'Các bước');
    });

    test('vietnamese via function works', () {
      const strings = GoogleStyleStrings.vietnamese();
      expect(strings.via('A'), 'qua A');
    });

    test('custom override works', () {
      const strings = GoogleStyleStrings(start: 'Go');
      expect(strings.start, 'Go');
      expect(strings.resume, 'Resume');
    });
  });

  group('SpeedLimitSign', () {
    test('has exactly two values', () {
      expect(SpeedLimitSign.values.length, 2);
    });
  });
}
