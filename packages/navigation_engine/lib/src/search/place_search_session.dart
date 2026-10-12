import 'dart:math';

import 'place_search_provider.dart';

/// One search, from the first keystroke to the chosen place.
///
/// Create a session when the user starts typing, pass it to every
/// [PlaceSearchProvider.autocomplete] call and to the
/// [PlaceSearchProvider.resolve] of the chosen suggestion, then drop it and
/// create a new one for the next search. Providers that bill per session
/// send its [token] with each request; the others ignore it.
///
/// A session is an opaque token holder: two sessions are never equal.
final class PlaceSearchSession {
  /// A new session with a fresh random [token].
  PlaceSearchSession() : token = _newToken();

  /// A random UUID (version 4), such as
  /// `3b241101-e2bb-4255-8caf-4136c566a962`. Providers read it; apps need
  /// not.
  ///
  /// It comes from `Random.secure()`. On a platform without a secure
  /// source (where it throws, as under dart2js on node) the tokens come
  /// instead from a `Random` seeded with the clock when the first session
  /// is created: still unique within the app, but
  /// predictable, and two devices that start in the same microsecond would
  /// share them. That is a deliberate downgrade: a session token only
  /// groups requests for billing, it is no secret, so search keeps working
  /// rather than throwing.
  final String token;

  @override
  String toString() => 'PlaceSearchSession($token)';

  static Random? _random;

  static String _newToken() {
    final random = _random ??= _secureRandom();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }

  // A secure source where the platform has one, else the documented
  // downgrade (see [token]). Any error, not only `UnsupportedError`: under
  // dart2js on node, `Random.secure()` throws a plain JavaScript error.
  static Random _secureRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random(DateTime.now().microsecondsSinceEpoch);
    }
  }
}
