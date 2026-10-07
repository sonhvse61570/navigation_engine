import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  group('geojson', () {
    test('line collection: lng/lat order, empty below two points', () {
      final fc = lineFeatureCollection(const [
        GeoPoint(10, 106),
        GeoPoint(11, 107),
      ]);
      final f = (fc['features']! as List).single as Map;
      expect((f['geometry'] as Map)['coordinates'], [
        [106.0, 10.0],
        [107.0, 11.0],
      ]);
      expect(
        lineFeatureCollection(const [GeoPoint(10, 106)])['features'],
        isEmpty,
      );
    });

    test('point collection carries the bearing; empty for null', () {
      final fc = pointFeatureCollection(const GeoPoint(10, 106), bearing: 30);
      final f = (fc['features']! as List).single as Map;
      expect((f['geometry'] as Map)['coordinates'], [106.0, 10.0]);
      expect((f['properties'] as Map)['bearing'], 30);
      expect(pointFeatureCollection(null)['features'], isEmpty);
    });
  });
}
