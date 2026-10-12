import 'dart:async';

import 'package:navigation_engine/navigation_engine.dart';

/// An error of a Goong request that the package reports itself.
///
/// `GoongRouteProvider` throws these. `GoongPlaceSearch` wraps them in a
/// [GoongSearchException], as its [PlaceSearchProvider] contract asks. The
/// subclasses say what went wrong:
///
/// - [GoongCodeException]: Goong answered with an error code, such as
///   `ZERO_RESULTS` or `REQUEST_DENIED`;
/// - [GoongHttpException]: the server answered with an HTTP error and no
///   Goong code (a bad key, a rate limit, a proxy error);
/// - [GoongTimeoutException]: no full answer within the timeout;
/// - [GoongFormatException]: the answer is not the JSON Goong sends.
///
/// The messages never hold the API key. Transport failures (no network,
/// DNS, TLS) are not wrapped by the route provider: they arrive as the
/// `http` client throws them, usually as `http.ClientException`, with the
/// key in their URL and message replaced by `REDACTED`.
sealed class GoongException implements Exception {
  /// An error described by [message].
  const GoongException(this.message);

  /// What went wrong, in words fit for a log.
  final String message;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// Goong answered with an error [code] instead of `OK`.
///
/// Goong answers in two shapes, and both become this exception:
///
/// - Google's: `{"status": "ZERO_RESULTS", "error_message": "…"}`;
/// - an error object: `{"error": {"code": "API_KEY_MISSING", "message":
///   "…"}}` (an error without a code, or a plain string, has the code
///   `ERROR`).
///
/// The usual codes, in Google's vocabulary that Goong follows:
///
/// - `ZERO_RESULTS`: no route between the points, or no place found;
/// - `NOT_FOUND`: a point or a place id could not be found;
/// - `INVALID_REQUEST`: a parameter is missing or not valid;
/// - `OVER_QUERY_LIMIT`, `OVER_DAILY_LIMIT`: the rate limit or quota;
/// - `REQUEST_DENIED`: the key is not allowed to make the request;
/// - `UNKNOWN_ERROR`: a server error; try again;
/// - `API_KEY_MISSING`: no key was sent (a proxy that did not add it?).
///
/// Goong may send others; [code] holds whatever it sent.
final class GoongCodeException extends GoongException {
  /// An error [code] the server answered with [statusCode], with its own
  /// [serverMessage] when it sent one.
  GoongCodeException(this.code, {this.serverMessage, required this.statusCode})
    : super(_describe(code, serverMessage, statusCode));

  /// The Goong code, such as `ZERO_RESULTS`, with the key replaced by
  /// `REDACTED` should the server echo it there.
  final String code;

  /// The server's own message (`error_message`, or the error object's
  /// `message`), with the key replaced by `REDACTED`; null when it sent
  /// none.
  final String? serverMessage;

  /// The HTTP status of the answer: 200 or an error.
  final int statusCode;

  @override
  String get _name => 'GoongCodeException';

  static String _describe(String code, String? serverMessage, int status) {
    final meaning = switch (code) {
      'ZERO_RESULTS' => 'no result for the request',
      'NOT_FOUND' => 'a point or place was not found',
      'INVALID_REQUEST' => 'the server rejected the request',
      'OVER_QUERY_LIMIT' ||
      'OVER_DAILY_LIMIT' => 'the rate limit or quota is reached',
      'REQUEST_DENIED' =>
        'the request was denied (check the key and its restrictions)',
      'UNKNOWN_ERROR' => 'an unexpected server error',
      'MAX_WAYPOINTS_EXCEEDED' => 'too many points',
      'API_KEY_MISSING' => 'no key was sent',
      _ => 'the server reported an error',
    };
    final detail = serverMessage == null || serverMessage.isEmpty
        ? ''
        : ' ($serverMessage)';
    return 'Goong $code: $meaning$detail [HTTP $status]';
  }
}

/// The server answered with HTTP [statusCode] and no Goong code.
///
/// Usual causes: 401 or 403, a key that is missing, not valid or blocked,
/// an unpaid account, or a Maptiles key used for a REST API (which needs
/// the "API key"); 429, the rate limit; 5xx, a server or proxy error.
final class GoongHttpException extends GoongException {
  /// An HTTP error [statusCode], with the response's [reasonPhrase] and
  /// the start of its [body] when they help.
  GoongHttpException(this.statusCode, {String? reasonPhrase, String body = ''})
    : super(_describe(statusCode, reasonPhrase, body));

  /// The HTTP status, such as 403 or 429.
  final int statusCode;

  @override
  String get _name => 'GoongHttpException';

  static String _describe(int status, String? reason, String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Cut on characters (runes), not UTF-16 units: no half emoji.
    final runes = text.runes;
    final excerpt = runes.length > 200
        ? '${String.fromCharCodes(runes.take(200))}…'
        : text;
    final hint = switch (status) {
      401 => ' (the key is missing or not valid)',
      403 => ' (the key is missing, not valid, blocked, or a Maptiles key)',
      429 => ' (rate limit reached)',
      _ => '',
    };
    return 'Goong request failed with HTTP $status'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}'
        '$hint'
        '${excerpt.isEmpty ? '' : ': $excerpt'}';
  }
}

/// No full answer arrived within [timeout]; the request was aborted.
///
/// It is also a [TimeoutException], so code that catches those keeps
/// working.
final class GoongTimeoutException extends GoongException
    implements TimeoutException {
  /// A request that took longer than [timeout].
  GoongTimeoutException(this.timeout)
    : super('Goong request timed out after ${timeout.inMilliseconds} ms');

  /// The time the request was allowed.
  final Duration timeout;

  /// The same as [timeout], for [TimeoutException].
  @override
  Duration get duration => timeout;

  @override
  String get _name => 'GoongTimeoutException';
}

/// The answer is not what Goong sends: not UTF-8, not JSON, or JSON of an
/// unexpected shape. [message] names the field, such as
/// `routes[0].legs[0].steps[2].polyline.points`.
final class GoongFormatException extends GoongException {
  /// A malformed answer, described by [message].
  const GoongFormatException(super.message);

  @override
  String get _name => 'GoongFormatException';
}

/// A `GoongPlaceSearch` request failed: the [PlaceSearchException] its
/// [PlaceSearchProvider] contract promises.
///
/// [message] names the request (`Goong autocomplete failed`, …). [cause]
/// says why: a [GoongException] (match on its type: a
/// [GoongTimeoutException] is also a [TimeoutException]), or the error the
/// `http` client threw, such as an `http.ClientException`, with the key in
/// its URL and message replaced by `REDACTED`. [statusCode] is the HTTP
/// status of a [GoongCodeException] or [GoongHttpException] cause.
final class GoongSearchException extends PlaceSearchException {
  /// The [request] (such as `autocomplete`) failed because of [cause].
  GoongSearchException(String request, Exception cause)
    : super(
        'Goong $request failed',
        statusCode: switch (cause) {
          GoongCodeException(:final statusCode) => statusCode,
          GoongHttpException(:final statusCode) => statusCode,
          _ => null,
        },
        cause: cause,
      );

  /// `GoongSearchException: <message> (<status>); cause: <cause>`.
  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'GoongSearchException: $message$status; cause: $cause';
  }
}
