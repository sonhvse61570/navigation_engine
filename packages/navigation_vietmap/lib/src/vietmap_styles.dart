/// A Vietmap base map style, served as a MapLibre / Mapbox GL `style.json`.
enum VietmapStyle {
  /// The vector street map: the default, for day.
  tm,

  /// The light vector map.
  lm,

  /// The dark vector map: suggested for night.
  dm,

  /// The hybrid map: satellite imagery with labels. Vietmap may have to
  /// enable it for the key.
  hm,
}

/// Vietmap's map styles, for `MapLibreStyleNavigation(styleString: ...,
/// nightStyleString: ...)` or any MapLibre / Mapbox GL map.
///
/// ```dart
/// MapLibreStyleNavigation(
///   // ...
///   styleString: VietmapStyles.url(VietmapStyle.tm, apiKey: tileKey),
///   nightStyleString: VietmapStyles.url(VietmapStyle.dm, apiKey: tileKey),
///   attributionText: VietmapStyles.attribution,
/// );
/// ```
abstract final class VietmapStyles {
  /// The credit to show on the map, `© VIETMAP`. Vietmap's styles carry no
  /// attribution string of their own, so the map's attribution button
  /// shows none: pass this to the map (`attributionText` in
  /// navigation_maplibre).
  static const String attribution = '© VIETMAP';

  /// The `style.json` URL of [style], with the tile key [apiKey] in its
  /// query (`apikey=`).
  ///
  /// Vietmap copies the key from the style URL into its tile URLs, so the
  /// map needs no header or request transform. Use a tile key ("public
  /// tile" key, restricted to your app), not the services key the REST APIs
  /// take: a tile key ships with the app.
  ///
  /// Throws [ArgumentError] when [apiKey] is empty.
  static String url(VietmapStyle style, {required String apiKey}) {
    if (apiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'is empty');
    }
    return 'https://maps.vietmap.vn/maps/styles/${style.name}/style.json'
        '?apikey=${Uri.encodeComponent(apiKey)}';
  }
}
