import 'dart:async';

import 'package:navigation_engine/navigation_engine.dart';

/// An error of a Google request that this package reports itself.
///
/// `GoogleRoutesRouteProvider` throws these. `GooglePlacesSearch` wraps
/// them in a [GooglePlacesSearchException], as its [PlaceSearchProvider]
/// contract asks. The subclasses say what went wrong:
///
/// - [GoogleRoutesStatusException]: Google answered with an error status,
///   such as `INVALID_ARGUMENT` or `RESOURCE_EXHAUSTED` (an RPC error), or
///   the Geocoding API's `REQUEST_DENIED`;
/// - [GoogleRoutesHttpException]: the server answered with HTTP 401 or 403
///   (the key), or with an HTTP error that is not Google's (a proxy error);
/// - [GoogleRoutesNoRouteException]: there is no route between the points;
/// - [GoogleRoutesTimeoutException]: no full answer within the timeout;
/// - [GoogleRoutesFormatException]: the answer is not the JSON Google
///   sends.
///
/// The messages never hold the API key. Transport failures (no network,
/// DNS, TLS) are not wrapped by the route provider: they arrive as the
/// `http` client throws them, usually as `http.ClientException`, with the
/// key in their URL and message replaced by `REDACTED`.
sealed class GoogleRoutesException implements Exception {
  /// An error described by [message].
  const GoogleRoutesException(this.message);

  /// What went wrong, in words fit for a log.
  final String message;

  /// The HTTP status of the answer; null when there was none, or when it
  /// could not be read.
  int? get statusCode => null;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// Google answered with an error [status].
///
/// Two shapes carry one:
///
/// - the Google RPC error of the Routes and Places APIs,
///   `{"error": {"code": 400, "message": "…", "status": "INVALID_ARGUMENT"}}`,
///   with an HTTP error status other than 401 and 403 (those are a
///   [GoogleRoutesHttpException]). Usual statuses: `INVALID_ARGUMENT`
///   (400, a bad request, or a key that is not valid: "API key not
///   valid"), `NOT_FOUND` (404),
///   `RESOURCE_EXHAUSTED` (429, a quota), `INTERNAL` and `UNAVAILABLE`
///   (5xx).
/// - the `status` of a Geocoding answer, with HTTP 200:
///   `REQUEST_DENIED`, `OVER_QUERY_LIMIT`, `INVALID_REQUEST`,
///   `UNKNOWN_ERROR`, …
final class GoogleRoutesStatusException extends GoogleRoutesException {
  /// An error [status] the server answered with [statusCode], with its own
  /// [serverMessage] when it sent one.
  GoogleRoutesStatusException(
    this.status, {
    this.serverMessage,
    required this.statusCode,
  }) : super(_describe(status, serverMessage, statusCode));

  /// Google's status, such as `INVALID_ARGUMENT`, with the key replaced by
  /// `REDACTED` should the server echo it there.
  final String status;

  /// The server's own `message` (or Geocoding `error_message`), with the
  /// key replaced by `REDACTED`; null when it sent none.
  final String? serverMessage;

  /// The HTTP status of the answer.
  @override
  final int statusCode;

  @override
  String get _name => 'GoogleRoutesStatusException';

  static String _describe(String status, String? serverMessage, int code) {
    final meaning = switch (status) {
      'INVALID_ARGUMENT' ||
      'FAILED_PRECONDITION' ||
      'OUT_OF_RANGE' ||
      'INVALID_REQUEST' => 'the server rejected the request',
      'NOT_FOUND' => 'not found',
      'RESOURCE_EXHAUSTED' ||
      'OVER_QUERY_LIMIT' ||
      'OVER_DAILY_LIMIT' => 'quota or rate limit reached',
      'REQUEST_DENIED' =>
        'the request was denied: check the key and its '
            'restrictions',
      'INTERNAL' ||
      'UNAVAILABLE' ||
      'DEADLINE_EXCEEDED' ||
      'UNKNOWN' ||
      'UNKNOWN_ERROR' => 'a server error; retrying may succeed',
      _ => 'the server reported an error',
    };
    final detail = serverMessage == null || serverMessage.isEmpty
        ? ''
        : ' ($serverMessage)';
    return 'Google $status: $meaning$detail [HTTP $code]';
  }
}

/// The server answered with HTTP [statusCode]: a 401 or 403 (always this
/// exception, whatever the body), or an error without a Google error body.
///
/// Usual causes: 403 `PERMISSION_DENIED`, a key that is missing or may not
/// call the API (the API is not enabled for its project, its API or
/// application restrictions refuse the request, or billing is off); 401
/// `UNAUTHENTICATED`, a request without valid credentials (Google answers
/// a key that is not valid with 400 `INVALID_ARGUMENT`, "API key not
/// valid", a [GoogleRoutesStatusException]); 429, a quota; 5xx, a server
/// or proxy error.
final class GoogleRoutesHttpException extends GoogleRoutesException {
  /// An HTTP error [statusCode], with Google's [status] and [serverMessage]
  /// when the body is a Google error, else the response's [reasonPhrase]
  /// and the start of its [body] when they help.
  GoogleRoutesHttpException(
    this.statusCode, {
    this.status,
    this.serverMessage,
    String? reasonPhrase,
    String body = '',
  }) : super(_describe(statusCode, status, serverMessage, reasonPhrase, body));

  /// The HTTP status, such as 403 or 502.
  @override
  final int statusCode;

  /// Google's status when the body is a Google error, such as
  /// `PERMISSION_DENIED`, its key scrubbed; null otherwise.
  final String? status;

  /// Google's `message` when the body is a Google error, its key scrubbed;
  /// null otherwise.
  final String? serverMessage;

  @override
  String get _name => 'GoogleRoutesHttpException';

  static String _describe(
    int code,
    String? status,
    String? serverMessage,
    String? reason,
    String body,
  ) {
    final String excerpt;
    if (status != null) {
      excerpt = serverMessage == null || serverMessage.isEmpty
          ? status
          : '$status: $serverMessage';
    } else {
      final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
      // Cut on characters (runes), not UTF-16 units: no half emoji.
      final runes = text.runes;
      excerpt = runes.length > 200
          ? '${String.fromCharCodes(runes.take(200))}…'
          : text;
    }
    final hint = switch (code) {
      400 => ' (the request is not valid)',
      401 => ' (the request is not authenticated)',
      403 =>
        " (the key is missing or not allowed: check that the API is enabled "
            "for the key's project, the key's API and application "
            'restrictions, and billing)',
      404 => ' (not found)',
      429 => ' (quota or rate limit reached)',
      _ => '',
    };
    return 'Google request failed with HTTP $code'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}'
        '$hint'
        '${excerpt.isEmpty ? '' : ': $excerpt'}';
  }
}

/// Google found no route between the points: its answer had no `routes`
/// (an empty `{}`, as Routes v2 answers then).
final class GoogleRoutesNoRouteException extends GoogleRoutesException {
  /// No route.
  const GoogleRoutesNoRouteException()
    : super('Google found no route between the points');

  /// 200: Google answers "no route" with success.
  @override
  int get statusCode => 200;

  @override
  String get _name => 'GoogleRoutesNoRouteException';
}

/// No full answer arrived within [timeout]; the request was aborted.
///
/// It is also a [TimeoutException], so code that catches those keeps
/// working.
final class GoogleRoutesTimeoutException extends GoogleRoutesException
    implements TimeoutException {
  /// A request that took longer than [timeout].
  GoogleRoutesTimeoutException(this.timeout)
    : super('Google request timed out after ${timeout.inMilliseconds} ms');

  /// The time the request was allowed.
  final Duration timeout;

  /// The same as [timeout], for [TimeoutException].
  @override
  Duration get duration => timeout;

  @override
  String get _name => 'GoogleRoutesTimeoutException';
}

/// The answer is not what Google sends: not UTF-8, not JSON, or JSON of an
/// unexpected shape. [message] names the field, such as
/// `routes[0].legs[0].steps[2].staticDuration`.
final class GoogleRoutesFormatException extends GoogleRoutesException {
  /// A malformed answer, described by [message], because of [cause] when
  /// there is one.
  const GoogleRoutesFormatException(super.message, {this.cause});

  /// The error that found the problem, when there is one, such as the
  /// polyline decoder's `FormatException`.
  final Object? cause;

  @override
  String get _name => 'GoogleRoutesFormatException';
}

/// A `GooglePlacesSearch` request failed: the [PlaceSearchException] its
/// [PlaceSearchProvider] contract promises.
///
/// [message] names the request (`Google autocomplete failed`, `Google
/// place details failed`, `Google reverse geocoding failed`). [cause] says
/// why: a [GoogleRoutesException] (match on its type: a
/// [GoogleRoutesTimeoutException] is also a [TimeoutException]), or the
/// error the `http` client threw, such as an `http.ClientException`, with
/// the key in its URL and message replaced by `REDACTED`. [statusCode] is
/// the HTTP status of a [GoogleRoutesStatusException] or
/// [GoogleRoutesHttpException] cause.
final class GooglePlacesSearchException extends PlaceSearchException {
  /// The [request] (such as `autocomplete`) failed because of [cause].
  GooglePlacesSearchException(String request, Exception cause)
    : super(
        'Google $request failed',
        statusCode: switch (cause) {
          GoogleRoutesStatusException(:final statusCode) => statusCode,
          GoogleRoutesHttpException(:final statusCode) => statusCode,
          _ => null,
        },
        cause: cause,
      );

  /// `GooglePlacesSearchException: <message> (<status>); cause: <cause>`.
  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'GooglePlacesSearchException: $message$status; cause: $cause';
  }
}
