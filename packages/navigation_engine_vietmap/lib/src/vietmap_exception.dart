import 'dart:async';

import 'package:navigation_engine/navigation_engine.dart';

/// An error of a Vietmap request that the package reports itself.
///
/// `VietmapRouteProvider` throws these. `VietmapPlaceSearch` wraps them in
/// a [VietmapSearchException], as its [PlaceSearchProvider] contract asks.
/// The subclasses say what went wrong:
///
/// - [VietmapCodeException]: Vietmap answered with an error code, such as
///   `ZERO_RESULTS` or `OVER_DAILY_LIMIT`;
/// - [VietmapHttpException]: the server answered with an HTTP error and no
///   Vietmap code (a bad key, a rate limit, a proxy error);
/// - [VietmapTimeoutException]: no full answer within the timeout;
/// - [VietmapFormatException]: the answer is not the JSON Vietmap sends.
///
/// The messages never hold the API key. Transport failures (no network,
/// DNS, TLS) are not wrapped by the route provider: they arrive as the
/// `http` client throws them, usually as `http.ClientException`, with the
/// key in their URL and their message replaced by `REDACTED`.
sealed class VietmapException implements Exception {
  /// An error described by [message].
  const VietmapException(this.message);

  /// What went wrong, in words fit for a log.
  final String message;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// Vietmap answered with an error [code] instead of `OK`.
///
/// The codes of route v4, from Vietmap's documentation:
///
/// - `ZERO_RESULTS`: there is no route between the points.
/// - `INVALID_REQUEST`: a parameter is not valid; [serverMessage] says
///   which.
/// - `OVER_DAILY_LIMIT`: the key's daily quota is used up until it resets.
/// - `MAX_POINTS_EXCEED`: more points than the plan allows.
/// - `ERROR_UNKNOWN`: an unexpected server error.
///
/// Vietmap may add codes; [code] holds whatever it sent.
final class VietmapCodeException extends VietmapException {
  /// An error [code] the server answered with [statusCode], with its own
  /// [serverMessage] when it sent one.
  VietmapCodeException(
    this.code, {
    this.serverMessage,
    required this.statusCode,
  }) : super(_describe(code, serverMessage, statusCode));

  /// The Vietmap code, such as `ZERO_RESULTS`, with the key replaced by
  /// `REDACTED` should the server echo it there.
  final String code;

  /// The server's own `messages`, when it sent any (joined with `; `).
  final String? serverMessage;

  /// The HTTP status of the answer. Route v4 sends its codes in the body;
  /// the status may be 200 or an error.
  final int statusCode;

  @override
  String get _name => 'VietmapCodeException';

  static String _describe(String code, String? serverMessage, int status) {
    final meaning = switch (code) {
      'ZERO_RESULTS' => 'no route between the points',
      'INVALID_REQUEST' => 'the server rejected the request',
      'OVER_DAILY_LIMIT' => "the key's daily limit is reached",
      'MAX_POINTS_EXCEED' => 'too many points for the plan',
      'ERROR_UNKNOWN' => 'an unexpected server error',
      _ => 'the server reported an error',
    };
    final detail = serverMessage == null || serverMessage.isEmpty
        ? ''
        : ' ($serverMessage)';
    return 'Vietmap $code: $meaning$detail [HTTP $status]';
  }
}

/// The server answered with HTTP [statusCode] and no Vietmap error code.
///
/// Usual causes: 401 or 403, a key that is missing or not valid; 423, a
/// tile key used for a REST API, which needs a services key; 429, the rate
/// limit; 5xx, a server or proxy error.
final class VietmapHttpException extends VietmapException {
  /// An HTTP error [statusCode], with the response's [reasonPhrase] and
  /// the start of its [body] when they help.
  VietmapHttpException(
    this.statusCode, {
    String? reasonPhrase,
    String body = '',
  }) : super(_describe(statusCode, reasonPhrase, body));

  /// The HTTP status, such as 401 or 429.
  final int statusCode;

  @override
  String get _name => 'VietmapHttpException';

  static String _describe(int status, String? reason, String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Cut on characters (runes), not UTF-16 units: no half emoji.
    final runes = text.runes;
    final excerpt = runes.length > 200
        ? '${String.fromCharCodes(runes.take(200))}…'
        : text;
    final hint = switch (status) {
      401 || 403 => ' (the key is missing or not valid)',
      423 => ' (a tile key? REST APIs need a services key)',
      429 => ' (rate limit reached)',
      _ => '',
    };
    return 'Vietmap request failed with HTTP $status'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}'
        '$hint'
        '${excerpt.isEmpty ? '' : ': $excerpt'}';
  }
}

/// No full answer arrived within [timeout]; the request was aborted.
///
/// It is also a [TimeoutException], so code that catches those keeps
/// working.
final class VietmapTimeoutException extends VietmapException
    implements TimeoutException {
  /// A request that took longer than [timeout].
  VietmapTimeoutException(this.timeout)
    : super(
        'Vietmap request timed out after '
        '${timeout.inMilliseconds} ms',
      );

  /// The time the request was allowed.
  final Duration timeout;

  /// The same as [timeout], for [TimeoutException].
  @override
  Duration get duration => timeout;

  @override
  String get _name => 'VietmapTimeoutException';
}

/// The answer is not what Vietmap sends: not UTF-8, not JSON, or JSON of an
/// unexpected shape. [message] names the field, such as
/// `paths[0].instructions[2].interval`.
final class VietmapFormatException extends VietmapException {
  /// A malformed answer, described by [message].
  const VietmapFormatException(super.message);

  @override
  String get _name => 'VietmapFormatException';
}

/// A `VietmapPlaceSearch` request failed: the [PlaceSearchException] its
/// [PlaceSearchProvider] contract promises.
///
/// [message] names the request (`Vietmap autocomplete failed`, …). [cause]
/// says why: a [VietmapException] (match on its type: a
/// [VietmapTimeoutException] is also a [TimeoutException]), or the error
/// the `http` client threw, such as an `http.ClientException`, with the key
/// in its URL and its message replaced by `REDACTED`. [statusCode] is the
/// HTTP status of a [VietmapCodeException] or [VietmapHttpException] cause.
final class VietmapSearchException extends PlaceSearchException {
  /// The [request] (such as `autocomplete`) failed because of [cause].
  VietmapSearchException(String request, Exception cause)
    : super(
        'Vietmap $request failed',
        statusCode: switch (cause) {
          VietmapCodeException(:final statusCode) => statusCode,
          VietmapHttpException(:final statusCode) => statusCode,
          _ => null,
        },
        cause: cause,
      );

  /// `VietmapSearchException: <message> (<status>); cause: <cause>`.
  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'VietmapSearchException: $message$status; cause: $cause';
  }
}
