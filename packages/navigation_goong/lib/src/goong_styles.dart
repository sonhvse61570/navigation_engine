/// A Goong base map style, served as a MapLibre / Mapbox GL style JSON.
///
/// Goong's help centre documents [map], [highlight] and [satellite]. Its
/// older mobile documentation also listed [dark], [navigationDay] and
/// [navigationNight]; they **may not exist** any more ([mayNotExist]):
/// check that they load with your key before you ship them.
enum GoongStyle {
  /// The full map, with every icon (`goong_map_web`): the default, for day.
  map('goong_map_web'),

  /// The map with fewer icons (`goong_map_highlight`).
  highlight('goong_map_highlight'),

  /// Satellite imagery (`goong_satellite`).
  satellite('goong_satellite'),

  /// The dark map (`goong_map_dark`), for night. May not exist.
  dark('goong_map_dark', mayNotExist: true),

  /// The navigation map for day (`navigation_day`). May not exist.
  navigationDay('navigation_day', mayNotExist: true),

  /// The navigation map for night (`navigation_night`). May not exist.
  navigationNight('navigation_night', mayNotExist: true);

  const GoongStyle(this.asset, {this.mayNotExist = false});

  /// The style's file name on Goong's tile server, without `.json`.
  final String asset;

  /// True for a style that only Goong's older documentation lists: it may
  /// no longer be served.
  final bool mayNotExist;
}

/// Goong's map styles, for `MapLibreStyleNavigation(styleString: ...,
/// nightStyleString: ...)` or any MapLibre / Mapbox GL map.
///
/// ```dart
/// MapLibreStyleNavigation(
///   // ...
///   styleString: GoongStyles.url(GoongStyle.map, mapTilesKey: tilesKey),
///   // The same style at night: try GoongStyle.dark once it loads with
///   // your key (it may not exist any more).
///   nightStyleString: GoongStyles.url(GoongStyle.map, mapTilesKey: tilesKey),
///   attributionText: GoongStyles.attribution,
/// );
/// ```
abstract final class GoongStyles {
  /// The credit to show on the map, `© Goong`. Goong publishes no
  /// attribution requirement; this is a courtesy credit, shown with
  /// `attributionText` in navigation_maplibre.
  static const String attribution = '© Goong';

  /// The style JSON URL of [style], with the Maptiles key [mapTilesKey] in
  /// its query (`api_key=`).
  ///
  /// Use Goong's "Maptiles key", not the "API key" the REST APIs take: the
  /// Maptiles key ships with the app, so restrict it to your app in Goong's
  /// console.
  ///
  /// Throws [ArgumentError] when [mapTilesKey] is empty.
  static String url(GoongStyle style, {required String mapTilesKey}) {
    if (mapTilesKey.isEmpty) {
      throw ArgumentError.value(mapTilesKey, 'mapTilesKey', 'is empty');
    }
    return 'https://tiles.goong.io/assets/${style.asset}.json'
        '?api_key=${Uri.encodeComponent(mapTilesKey)}';
  }
}
