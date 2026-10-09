import 'package:flutter/foundation.dart';
import 'package:navigation_engine/navigation_engine.dart';

/// A kind of place to search for along the route.
enum AlongRouteCategory {
  /// Gas (petrol) stations.
  gas,

  /// Restaurants.
  restaurant,

  /// Coffee shops.
  coffee,

  /// Grocery stores.
  grocery,
}

/// What to search for along [route], from [fromDistance] metres on: a
/// [text], a [category], or both.
@immutable
final class AlongRouteQuery {
  /// Creates a query along [route].
  const AlongRouteQuery({
    this.text,
    this.category,
    required this.route,
    required this.fromDistance,
  });

  /// The words typed, if any.
  final String? text;

  /// The category chosen, if any.
  final AlongRouteCategory? category;

  /// The route being driven.
  final NavRoute route;

  /// How far along [route] the vehicle is, in metres.
  final double fromDistance;
}

/// A place found along the route.
@immutable
final class AlongRoutePlace {
  /// Creates a place [name] at [position], identified by [id].
  const AlongRoutePlace({
    required this.id,
    required this.name,
    required this.position,
    this.detour,
    this.subtitle,
  });

  /// A stable identifier; the map pin's id is `navigation_engine_search_<id>`.
  final String id;

  /// The place's name.
  final String name;

  /// Where the place is.
  final GeoPoint position;

  /// How much longer the trip gets with a stop there, when known.
  final Duration? detour;

  /// A second line, such as the address or the opening hours.
  final String? subtitle;

  @override
  bool operator ==(Object other) =>
      other is AlongRoutePlace &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.detour == detour &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(id, name, position, detour, subtitle);

  @override
  String toString() => 'AlongRoutePlace($id, $name)';
}

/// Searches for places along the route: the app's own search back end.
typedef AlongRouteSearch = Future<List<AlongRoutePlace>> Function(
  AlongRouteQuery query,
);
