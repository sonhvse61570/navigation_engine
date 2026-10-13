import 'package:navigation_goong/navigation_goong.dart';
import 'package:test/test.dart';

void main() {
  test("each style's JSON, with the Maptiles key in the query", () {
    expect(
      {
        for (final s in GoongStyle.values)
          s: GoongStyles.url(s, mapTilesKey: 'tiles-key'),
      },
      {
        GoongStyle.map:
            'https://tiles.goong.io/assets/goong_map_web.json?api_key=tiles-key',
        GoongStyle.highlight:
            'https://tiles.goong.io/assets/goong_map_highlight.json'
            '?api_key=tiles-key',
        GoongStyle.satellite:
            'https://tiles.goong.io/assets/goong_satellite.json'
            '?api_key=tiles-key',
        GoongStyle.dark:
            'https://tiles.goong.io/assets/goong_map_dark.json'
            '?api_key=tiles-key',
        GoongStyle.navigationDay:
            'https://tiles.goong.io/assets/navigation_day.json'
            '?api_key=tiles-key',
        GoongStyle.navigationNight:
            'https://tiles.goong.io/assets/navigation_night.json'
            '?api_key=tiles-key',
      },
    );
  });

  test('the key is encoded', () {
    final url = Uri.parse(
      GoongStyles.url(GoongStyle.dark, mapTilesKey: 'a b&c=d'),
    );
    expect(url.queryParameters, {'api_key': 'a b&c=d'});
    expect(url.query, 'api_key=a%20b%26c%3Dd');
  });

  test('an empty key throws', () {
    expect(
      () => GoongStyles.url(GoongStyle.map, mapTilesKey: ''),
      throwsArgumentError,
    );
  });

  test('the styles that may not exist any more are marked', () {
    expect(
      [
        for (final s in GoongStyle.values)
          if (s.mayNotExist) s,
      ],
      [GoongStyle.dark, GoongStyle.navigationDay, GoongStyle.navigationNight],
    );
  });

  test('the attribution', () {
    expect(GoongStyles.attribution, '© Goong');
  });
}
