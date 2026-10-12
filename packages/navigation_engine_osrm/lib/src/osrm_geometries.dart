/// How OSRM encodes the route geometry in its answer (`geometries=`).
enum OsrmGeometries {
  /// GeoJSON `LineString` coordinates: plain, but about three times larger
  /// on the wire.
  geojson,

  /// An encoded polyline with six decimals: compact, and as precise as
  /// OSRM's own coordinates.
  polyline6,
}
