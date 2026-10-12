import 'package:navigation_engine/navigation_engine.dart';
import 'package:test/test.dart';

/// A tiny in-memory provider: suggestions without a position need a
/// [resolve], and every call records the session it was given.
class FakePlaceSearch implements PlaceSearchProvider {
  final sessions = <PlaceSearchSession?>[];
  GeoPoint? lastNear;

  static const _cafe = Place(
    id: 'cafe',
    name: 'Cafe',
    address: '1 Le Loi',
    position: GeoPoint(10.77, 106.70),
  );

  @override
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    GeoPoint? near,
    PlaceSearchSession? session,
  }) async {
    sessions.add(session);
    lastNear = near;
    if (query.isEmpty) return const [];
    return const [
      PlaceSuggestion(id: 'cafe', title: 'Cafe', subtitle: '1 Le Loi'),
      PlaceSuggestion(
        id: 'park',
        title: 'Park',
        position: GeoPoint(10.78, 106.69),
      ),
    ];
  }

  @override
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    PlaceSearchSession? session,
  }) async {
    sessions.add(session);
    if (suggestion.id == 'cafe') return _cafe;
    final position = suggestion.position;
    if (position == null) {
      throw PlaceSearchException('unknown place ${suggestion.id}');
    }
    return Place(id: suggestion.id, name: suggestion.title, position: position);
  }

  @override
  Future<Place?> reverse(GeoPoint point) async =>
      point == _cafe.position ? _cafe : null;
}

void main() {
  group('PlaceSearchProvider (through a fake)', () {
    test('autocomplete, then resolve, share one session', () async {
      final search = FakePlaceSearch();
      final session = PlaceSearchSession();
      const near = GeoPoint(10.7, 106.6);
      final suggestions = await search.autocomplete(
        'ca',
        near: near,
        session: session,
      );
      expect(suggestions.map((s) => s.id), ['cafe', 'park']);
      expect(suggestions.first.position, isNull, reason: 'needs a resolve');
      expect(search.lastNear, near);

      final place = await search.resolve(suggestions.first, session: session);
      expect(place.name, 'Cafe');
      expect(place.address, '1 Le Loi');
      expect(place.position, const GeoPoint(10.77, 106.70));
      expect(search.sessions, [same(session), same(session)]);
    });

    test('the session is optional', () async {
      final search = FakePlaceSearch();
      final suggestions = await search.autocomplete('pa');
      final place = await search.resolve(suggestions.last);
      expect(place.position, const GeoPoint(10.78, 106.69));
      expect(search.sessions, [null, null]);
    });

    test('reverse finds a place, or null', () async {
      final search = FakePlaceSearch();
      expect((await search.reverse(const GeoPoint(10.77, 106.70)))?.id, 'cafe');
      expect(await search.reverse(const GeoPoint(0, 0)), isNull);
    });

    test('errors are PlaceSearchExceptions', () async {
      final search = FakePlaceSearch();
      await expectLater(
        search.resolve(const PlaceSuggestion(id: 'x', title: 'X')),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.message,
            'message',
            'unknown place x',
          ),
        ),
      );
    });
  });

  group('PlaceSuggestion', () {
    test('equal fields are equal', () {
      const a = PlaceSuggestion(
        id: '1',
        title: 'A',
        subtitle: 'street',
        position: GeoPoint(1, 2),
      );
      const b = PlaceSuggestion(
        id: '1',
        title: 'A',
        subtitle: 'street',
        position: GeoPoint(1, 2),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('any different field makes them differ', () {
      const a = PlaceSuggestion(
        id: '1',
        title: 'A',
        subtitle: 'street',
        position: GeoPoint(1, 2),
      );
      expect(a, isNot(const PlaceSuggestion(id: '2', title: 'A')));
      for (final other in const [
        PlaceSuggestion(
          id: '2',
          title: 'A',
          subtitle: 'street',
          position: GeoPoint(1, 2),
        ),
        PlaceSuggestion(
          id: '1',
          title: 'B',
          subtitle: 'street',
          position: GeoPoint(1, 2),
        ),
        PlaceSuggestion(id: '1', title: 'A', position: GeoPoint(1, 2)),
        PlaceSuggestion(id: '1', title: 'A', subtitle: 'street'),
        PlaceSuggestion(
          id: '1',
          title: 'A',
          subtitle: 'street',
          position: GeoPoint(1, 3),
        ),
      ]) {
        expect(a, isNot(other));
      }
    });

    test('subtitle and position default to null', () {
      const s = PlaceSuggestion(id: '1', title: 'A');
      expect(s.subtitle, isNull);
      expect(s.position, isNull);
    });

    test('toString names the fields', () {
      expect(
        const PlaceSuggestion(id: '1', title: 'A').toString(),
        allOf(contains('PlaceSuggestion'), contains('1'), contains('A')),
      );
    });
  });

  group('Place', () {
    test('equal fields are equal', () {
      const a = Place(
        id: '1',
        name: 'A',
        address: 'street',
        position: GeoPoint(1, 2),
      );
      const b = Place(
        id: '1',
        name: 'A',
        address: 'street',
        position: GeoPoint(1, 2),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('any different field makes them differ', () {
      const a = Place(
        id: '1',
        name: 'A',
        address: 'street',
        position: GeoPoint(1, 2),
      );
      for (final other in const [
        Place(id: '2', name: 'A', address: 'street', position: GeoPoint(1, 2)),
        Place(id: '1', name: 'B', address: 'street', position: GeoPoint(1, 2)),
        Place(id: '1', name: 'A', position: GeoPoint(1, 2)),
        Place(id: '1', name: 'A', address: 'street', position: GeoPoint(2, 2)),
      ]) {
        expect(a, isNot(other));
      }
    });

    test('address defaults to null', () {
      expect(
        const Place(id: '1', name: 'A', position: GeoPoint(1, 2)).address,
        isNull,
      );
    });

    test('toString names the fields', () {
      expect(
        const Place(id: '1', name: 'A', position: GeoPoint(1, 2)).toString(),
        allOf(contains('Place'), contains('A'), contains('GeoPoint(1.0, 2.0)')),
      );
    });
  });

  group('PlaceSearchSession', () {
    test('each session has its own token', () {
      final tokens = {
        for (var i = 0; i < 1000; i++) PlaceSearchSession().token,
      };
      expect(tokens, hasLength(1000));
    });

    test('the token looks like a random UUID', () {
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (var i = 0; i < 100; i++) {
        expect(PlaceSearchSession().token, matches(uuid));
      }
    });

    test('a session keeps its token', () {
      final session = PlaceSearchSession();
      expect(session.token, session.token);
    });

    test('two sessions are never equal', () {
      final a = PlaceSearchSession();
      expect(a, a);
      expect(a, isNot(PlaceSearchSession()));
    });
  });

  group('PlaceSearchException', () {
    test('carries the message, the status and the cause', () {
      final cause = FormatException('bad json');
      final e = PlaceSearchException(
        'the server failed',
        statusCode: 500,
        cause: cause,
      );
      expect(e, isA<Exception>());
      expect(e.message, 'the server failed');
      expect(e.statusCode, 500);
      expect(e.cause, same(cause));
      expect(
        e.toString(),
        'PlaceSearchException: the server failed (500); '
        'cause: FormatException: bad json',
      );
    });

    test('toString shows the cause without a status', () {
      final e = PlaceSearchException('no answer', cause: 'socket closed');
      expect(
        e.toString(),
        'PlaceSearchException: no answer; cause: socket closed',
      );
    });

    test('status and cause are optional', () {
      final e = PlaceSearchException('no answer');
      expect(e.statusCode, isNull);
      expect(e.cause, isNull);
      expect(e.toString(), 'PlaceSearchException: no answer');
    });

    test('providers can extend it', () {
      expect(_QuotaException(), isA<PlaceSearchException>());
    });
  });
}

class _QuotaException extends PlaceSearchException {
  _QuotaException() : super('over quota', statusCode: 429);
}
