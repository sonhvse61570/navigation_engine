import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

class OneRoute extends RouteProvider {
  OneRoute(this.result);
  final NavRoute result;
  double? heading;

  @override
  Future<NavRoute> route(GeoPoint from, GeoPoint to, {double? heading}) async {
    this.heading = heading;
    return result;
  }
}

void main() {
  test('routes() defaults to the single best route', () async {
    const a = GeoPoint(10.77, 106.69);
    final r = NavRoute.fromPoints([a, offsetPoint(a, 0, 100)]);
    final provider = OneRoute(r);
    final routes = await provider.routes(a, a, heading: 90);
    expect(routes, [same(r)]);
    expect(provider.heading, 90);
  });
}
