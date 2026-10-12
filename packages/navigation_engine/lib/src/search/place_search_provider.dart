import '../geo/geo_point.dart';
import 'place.dart';
import 'place_search_session.dart';

/// Finds places by name and by position (Vietmap, Goong, your own back
/// end…), for a destination search field.
///
/// A typical search: [autocomplete] while the user types, [resolve] on the
/// chosen [PlaceSuggestion], both with the same [PlaceSearchSession]; and
/// [reverse] for a point the user pins on the map. Methods throw a
/// [PlaceSearchException] when the provider fails.
abstract interface class PlaceSearchProvider {
  /// The suggestions for [query], best first; empty when nothing matches.
  /// [near] biases them towards a position, such as the vehicle's, when
  /// the provider supports it. [session] groups the calls of one search
  /// (see [PlaceSearchSession]).
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    GeoPoint? near,
    PlaceSearchSession? session,
  });

  /// The [Place] of [suggestion], with its position: a request to the
  /// provider when the suggestion has none, or when the provider has more
  /// to tell. Pass the [session] of the [autocomplete] calls that found it.
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    PlaceSearchSession? session,
  });

  /// The place at [point], such as its address; null when the provider
  /// knows none there.
  Future<Place?> reverse(GeoPoint point);
}

/// A [PlaceSearchProvider] failed: the request failed, or the provider
/// answered with an error or with something it could not read.
///
/// Providers may extend it for their own errors.
class PlaceSearchException implements Exception {
  /// An error described by [message], with the HTTP [statusCode] and the
  /// underlying [cause] when there are.
  PlaceSearchException(this.message, {this.statusCode, this.cause});

  /// What went wrong, in words fit for a log.
  final String message;

  /// The HTTP status of the provider's answer, when there was one.
  final int? statusCode;

  /// The error that caused this one, such as a `FormatException` or a
  /// network error, when there is one.
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    final because = cause == null ? '' : '; cause: $cause';
    return 'PlaceSearchException: $message$status$because';
  }
}
