import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'support/flow_harness.dart';

/// A map that records the pins it is asked to draw.
class _PinsMap extends PlainMap implements SearchPinsMap {
  List<AlongRoutePlace>? places;
  String? focusedId;
  void Function(AlongRoutePlace place)? onTap;

  @override
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  }) async {
    this.places = places;
    this.focusedId = focusedId;
    this.onTap = onTap;
  }

  @override
  void clearSearchPins() {
    places = null;
    focusedId = null;
    onTap = null;
  }
}

const _fuel = AlongRoutePlace(
  id: 'fuel',
  name: 'Fuel',
  position: GeoPoint(10.0, 106.0),
);
const _cafe = AlongRoutePlace(
  id: 'cafe',
  name: 'Cafe',
  position: GeoPoint(10.001, 106.001),
);

// The behaviour behind the interface (pins shown with the results, moved
// with the focus, cleared on close or at the end, and a map without the
// interface) is covered through the real screen, in the search pins group
// of google_style_flow_scaffold_test.dart. This file only checks that a
// caller reaches a map through the interface.
void main() {
  group('SearchPinsMap', () {
    test('a caller reaches the pins through the interface', () async {
      final NavigationMap map = _PinsMap();
      final picked = <AlongRoutePlace>[];
      expect(map, isA<SearchPinsMap>());
      if (map case final SearchPinsMap pins) {
        await pins.showSearchPins(
          [_fuel, _cafe],
          focusedId: 'cafe',
          onTap: picked.add,
        );
      }
      final fake = map as _PinsMap;
      expect(fake.places, [_fuel, _cafe]);
      expect(fake.focusedId, 'cafe');
      fake.onTap!(_fuel);
      expect(picked, [_fuel]);
    });
  });
}
