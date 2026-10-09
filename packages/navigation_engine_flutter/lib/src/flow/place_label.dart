import 'package:flutter/foundation.dart';

/// A place's name and address, as a navigation UI shows a destination (in
/// the arrival header, for example). Compared by value.
@immutable
final class PlaceLabel {
  /// Creates a label for a place called [name], at [address] when known.
  const PlaceLabel({required this.name, this.address});

  /// The place's name, such as "Landmark 81".
  final String name;

  /// The place's address; null when unknown.
  final String? address;

  @override
  bool operator ==(Object other) =>
      other is PlaceLabel && other.name == name && other.address == address;

  @override
  int get hashCode => Object.hash(name, address);

  @override
  String toString() =>
      address == null ? 'PlaceLabel($name)' : 'PlaceLabel($name, $address)';
}
