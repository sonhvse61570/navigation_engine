/// A latitude/longitude pair in degrees (WGS 84).
final class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  /// Degrees north of the equator.
  final double lat;

  /// Degrees east of Greenwich.
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}
