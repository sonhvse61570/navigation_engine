import 'dart:async';

import 'package:navigation_engine/navigation_engine.dart';

/// An error of a Mapbox request that this package reports itself.
///
/// `MapboxDirectionsRouteProvider` throws these. `MapboxSearch` wraps them
/// in a [MapboxSearchException], as its [PlaceSearchProvider] contract
/// asks. The subclasses say what went wrong:
///
/// - [MapboxDirectionsCodeException]: Mapbox answered with an error
///   `code`, such as `NoRoute`, `NoSegment` or `InvalidInput`;
/// - [MapboxDirectionsHttpException]: the server answered with an HTTP
///   error and no code (a bad token, a rate limit, a proxy error);
/// - [MapboxDirectionsTimeoutException]: no full answer within the
///   timeout;
/// - [MapboxDirectionsFormatException]: the answer is not the JSON Mapbox
///   sends.
///
/// The messages never hold the access token. Transport failures (no
/// network, DNS, TLS) are not wrapped by the route provider: they arrive as
/// the `http` client throws them, usually as `http.ClientException`, with
/// the token in their URL and message replaced by `REDACTED`.
sealed class MapboxDirectionsException implements Exception {
  /// An error described by [message].
  const MapboxDirectionsException(this.message);

  /// What went wrong, in words fit for a log.
  final String message;

  /// The HTTP status of the answer: that of a
  /// [MapboxDirectionsCodeException] or [MapboxDirectionsHttpException];
  /// null for the others (no answer, or one that could not be read).
  int? get statusCode => null;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// Mapbox answered with an error [code] instead of `Ok`.
///
/// The codes of the Directions API, from its documentation:
///
/// - `NoRoute` (HTTP 200): there is no route between the points.
/// - `NoSegment` (HTTP 200): a point is not near a road the profile can
///   use.
/// - `ProfileNotFound` (HTTP 404): the profile does not exist.
/// - `InvalidInput` (HTTP 422): the request is not valid;
///   [serverMessage] says why.
///
/// Mapbox may send others; [code] holds whatever it sent.
final class MapboxDirectionsCodeException extends MapboxDirectionsException {
  /// An error [code] the server answered with [statusCode], with its own
  /// [serverMessage] when it sent one.
  MapboxDirectionsCodeException(
    this.code, {
    this.serverMessage,
    required this.statusCode,
  }) : super(_describe(code, serverMessage, statusCode));

  /// The Mapbox code, such as `NoRoute`, with the token replaced by
  /// `REDACTED` should the server echo it there.
  final String code;

  /// The server's own `message`, with the token replaced by `REDACTED`;
  /// null when it sent none.
  final String? serverMessage;

  /// The HTTP status of the answer: 200 for `NoRoute` and `NoSegment`, an
  /// error status for the others.
  @override
  final int statusCode;

  @override
  String get _name => 'MapboxDirectionsCodeException';

  static String _describe(String code, String? serverMessage, int status) {
    final meaning = switch (code) {
      'NoRoute' => 'no route between the points',
      'NoSegment' => 'a point is not near a road the profile can use',
      'ProfileNotFound' => 'the profile does not exist',
      'InvalidInput' => 'the server rejected the request',
      _ => 'the server reported an error',
    };
    final detail = serverMessage == null || serverMessage.isEmpty
        ? ''
        : ' ($serverMessage)';
    return 'Mapbox $code: $meaning$detail [HTTP $status]';
  }
}

/// The server answered with HTTP [statusCode] and no Mapbox code.
///
/// Usual causes: 401, a token that is missing or not valid; 403, a token
/// whose URL restrictions refuse the request, or an account problem; 429,
/// the rate limit; 5xx, a server or proxy error.
final class MapboxDirectionsHttpException extends MapboxDirectionsException {
  /// An HTTP error [statusCode], with the response's [reasonPhrase] and
  /// the start of its [body] when they help.
  MapboxDirectionsHttpException(
    this.statusCode, {
    String? reasonPhrase,
    String body = '',
  }) : super(_describe(statusCode, reasonPhrase, body));

  /// The HTTP status, such as 401 or 429.
  @override
  final int statusCode;

  @override
  String get _name => 'MapboxDirectionsHttpException';

  static String _describe(int status, String? reason, String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Cut on characters (runes), not UTF-16 units: no half emoji.
    final runes = text.runes;
    final excerpt = runes.length > 200
        ? '${String.fromCharCodes(runes.take(200))}…'
        : text;
    final hint = switch (status) {
      401 => ' (the access token is missing or not valid)',
      403 =>
        ' (the token is not allowed: check its URL restrictions and the '
            'account)',
      422 => ' (the request is not valid)',
      429 => ' (rate limit reached)',
      _ => '',
    };
    return 'Mapbox request failed with HTTP $status'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}'
        '$hint'
        '${excerpt.isEmpty ? '' : ': $excerpt'}';
  }
}

/// No full answer arrived within [timeout]; the request was aborted.
///
/// It is also a [TimeoutException], so code that catches those keeps
/// working.
final class MapboxDirectionsTimeoutException extends MapboxDirectionsException
    implements TimeoutException {
  /// A request that took longer than [timeout].
  MapboxDirectionsTimeoutException(this.timeout)
    : super('Mapbox request timed out after ${timeout.inMilliseconds} ms');

  /// The time the request was allowed.
  final Duration timeout;

  /// The same as [timeout], for [TimeoutException].
  @override
  Duration get duration => timeout;

  @override
  String get _name => 'MapboxDirectionsTimeoutException';
}

/// The answer is not what Mapbox sends: not UTF-8, not JSON, or JSON of an
/// unexpected shape. [message] names the field, such as
/// `routes[0].legs[0].steps[2].maneuver.location`.
final class MapboxDirectionsFormatException extends MapboxDirectionsException {
  /// A malformed answer, described by [message], because of [cause] when
  /// there is one.
  const MapboxDirectionsFormatException(super.message, {this.cause});

  /// The error that found the problem, when there is one: for a route, the
  /// `OsrmFormatException` of the OSRM parser that reads it; for an answer
  /// that is not JSON, a `FormatException` that keeps only the parser's
  /// offset.
  final Object? cause;

  @override
  String get _name => 'MapboxDirectionsFormatException';
}

/// A `MapboxSearch` request failed: the [PlaceSearchException] its
/// [PlaceSearchProvider] contract promises.
///
/// [message] names the request (`Mapbox suggest failed`, …). [cause] says
/// why: a [MapboxDirectionsException] (match on its type: a
/// [MapboxDirectionsTimeoutException] is also a [TimeoutException]), or
/// the error the `http` client threw, such as an `http.ClientException`,
/// with the token in its URL and message replaced by `REDACTED`.
/// [statusCode] is the HTTP status of a [MapboxDirectionsCodeException] or
/// [MapboxDirectionsHttpException] cause.
final class MapboxSearchException extends PlaceSearchException {
  /// The [request] (such as `suggest`) failed because of [cause].
  MapboxSearchException(String request, Exception cause)
    : super(
        'Mapbox $request failed',
        statusCode: switch (cause) {
          MapboxDirectionsCodeException(:final statusCode) => statusCode,
          MapboxDirectionsHttpException(:final statusCode) => statusCode,
          _ => null,
        },
        cause: cause,
      );

  /// `MapboxSearchException: <message> (<status>); cause: <cause>`.
  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'MapboxSearchException: $message$status; cause: $cause';
  }
}
