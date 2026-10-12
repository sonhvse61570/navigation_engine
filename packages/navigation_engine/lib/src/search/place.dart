import '../geo/geo_point.dart';
import 'place_search_provider.dart';

/// One answer of [PlaceSearchProvider.autocomplete]: what a search field
/// lists while the user types.
///
/// Some providers return no coordinates with their suggestions: then
/// [position] is null, and [PlaceSearchProvider.resolve] turns the
/// suggestion into a [Place] that has one.
final class PlaceSuggestion {
  /// A suggestion [id] shown as [title], with an optional [subtitle] and
  /// [position].
  const PlaceSuggestion({
    required this.id,
    required this.title,
    this.subtitle,
    this.position,
  });

  /// The provider's id of the suggestion (a place id, a reference id…),
  /// read back by [PlaceSearchProvider.resolve].
  final String id;

  /// The main line, such as the place's name.
  final String title;

  /// The second line, such as the address; null when the provider gives
  /// none.
  final String? subtitle;

  /// Where the place is; null when the provider needs a
  /// [PlaceSearchProvider.resolve] call to tell.
  final GeoPoint? position;

  @override
  bool operator ==(Object other) =>
      other is PlaceSuggestion &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, title, subtitle, position);

  @override
  String toString() =>
      'PlaceSuggestion(id: $id, title: $title, subtitle: $subtitle, '
      'position: $position)';
}

/// A place with a known [position]: what [PlaceSearchProvider.resolve] and
/// [PlaceSearchProvider.reverse] return, such as a destination to route to.
final class Place {
  /// A place [id] named [name] at [position], with an optional [address].
  const Place({
    required this.id,
    required this.name,
    this.address,
    required this.position,
  });

  /// The provider's id of the place.
  final String id;

  /// The place's name, or its address when it has no name of its own.
  final String name;

  /// The place's address; null when the provider gives none.
  final String? address;

  /// Where the place is.
  final GeoPoint position;

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, name, address, position);

  @override
  String toString() =>
      'Place(id: $id, name: $name, address: $address, position: $position)';
}
