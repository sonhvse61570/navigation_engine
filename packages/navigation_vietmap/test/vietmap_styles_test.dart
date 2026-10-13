import 'package:navigation_vietmap/navigation_vietmap.dart';
import 'package:test/test.dart';

void main() {
  test('each style\'s style.json, with the tile key in the query', () {
    expect(
      {
        for (final s in VietmapStyle.values)
          s: VietmapStyles.url(s, apiKey: 'tile-key'),
      },
      {
        VietmapStyle.tm:
            'https://maps.vietmap.vn/maps/styles/tm/style.json?apikey=tile-key',
        VietmapStyle.lm:
            'https://maps.vietmap.vn/maps/styles/lm/style.json?apikey=tile-key',
        VietmapStyle.dm:
            'https://maps.vietmap.vn/maps/styles/dm/style.json?apikey=tile-key',
        VietmapStyle.hm:
            'https://maps.vietmap.vn/maps/styles/hm/style.json?apikey=tile-key',
      },
    );
  });

  test('the key is encoded', () {
    final url = Uri.parse(VietmapStyles.url(VietmapStyle.dm, apiKey: 'a b&c'));
    expect(url.queryParameters, {'apikey': 'a b&c'});
  });

  test('an empty key throws', () {
    expect(
      () => VietmapStyles.url(VietmapStyle.tm, apiKey: ''),
      throwsArgumentError,
    );
  });

  test('the attribution', () {
    expect(VietmapStyles.attribution, '© VIETMAP');
  });
}
