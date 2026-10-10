import 'dart:async';

/// An error of an OSRM request that `OsrmRouteProvider` reports itself.
///
/// The subclasses say what went wrong:
///
/// - [OsrmCodeException]: the server answered with an OSRM error code, such
///   as `NoRoute` or `NoSegment`;
/// - [OsrmHttpException]: the server answered with an HTTP error and no
///   OSRM code (a proxy error or a rate limit, say);
/// - [OsrmTimeoutException]: no full answer within the timeout;
/// - [OsrmFormatException]: the answer is not the JSON OSRM sends.
///
/// Transport failures (no network, DNS, TLS) are not wrapped: they arrive
/// as the `http` client throws them, usually as `http.ClientException`.
sealed class OsrmException implements Exception {
  /// An error described by [message].
  const OsrmException(this.message);

  /// What went wrong, in words fit for a log.
  final String message;

  @override
  String toString() => '$_name: $message';

  String get _name;
}

/// The server answered with an OSRM error [code] instead of `Ok`.
///
/// The codes of the route service, from the OSRM HTTP API documentation:
///
/// - `NoRoute`: there is no route between the points (an island, a road
///   closed to the profile).
/// - `NoSegment`: a point is not near a road the profile can use.
/// - `TooBig`: the request is too big for the server, for example more
///   alternatives than it allows.
/// - `InvalidUrl`, `InvalidService`, `InvalidVersion`, `InvalidOptions`,
///   `InvalidQuery`, `InvalidValue`: the server rejected the request.
/// - `NotImplemented`: the server does not support the request.
///
/// Servers may add codes; [code] holds whatever the server sent.
final class OsrmCodeException extends OsrmException {
  /// An error [code] the server answered with [statusCode], with its own
  /// [serverMessage] when it sent one.
  OsrmCodeException(this.code, {this.serverMessage, required this.statusCode})
    : super(_describe(code, serverMessage, statusCode));

  /// The OSRM code, such as `NoRoute`.
  final String code;

  /// The server's own `message`, when it sent one.
  final String? serverMessage;

  /// The HTTP status of the answer: 400 for most errors, 200 on some
  /// servers.
  final int statusCode;

  @override
  String get _name => 'OsrmCodeException';

  static String _describe(String code, String? serverMessage, int status) {
    final meaning = switch (code) {
      'NoRoute' => 'no route between the points',
      'NoSegment' => 'a point is not near a road the profile can use',
      'TooBig' => 'the request is too big for the server',
      'InvalidUrl' ||
      'InvalidService' ||
      'InvalidVersion' ||
      'InvalidOptions' ||
      'InvalidQuery' ||
      'InvalidValue' => 'the server rejected the request',
      'NotImplemented' => 'the server does not support the request',
      _ => 'the server reported an error',
    };
    final detail = serverMessage == null || serverMessage.isEmpty
        ? ''
        : ' ($serverMessage)';
    return 'OSRM $code: $meaning$detail [HTTP $status]';
  }
}

/// The server answered with HTTP [statusCode] and no OSRM error code: a
/// proxy or gateway error, or a rate limit (429) on the demo server.
final class OsrmHttpException extends OsrmException {
  /// An HTTP error [statusCode], with the response's [reasonPhrase] and
  /// the start of its [body] when they help.
  OsrmHttpException(this.statusCode, {String? reasonPhrase, String body = ''})
    : super(_describe(statusCode, reasonPhrase, body));

  /// The HTTP status, such as 502 or 429.
  final int statusCode;

  @override
  String get _name => 'OsrmHttpException';

  static String _describe(int status, String? reason, String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Cut on characters (runes), not UTF-16 units: no half emoji.
    final runes = text.runes;
    final excerpt = runes.length > 200
        ? '${String.fromCharCodes(runes.take(200))}…'
        : text;
    return 'OSRM request failed with HTTP $status'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}'
        '${excerpt.isEmpty ? '' : ': $excerpt'}';
  }
}

/// No full answer arrived within [timeout]; the request was aborted.
///
/// It is also a [TimeoutException], so code that catches those keeps
/// working.
final class OsrmTimeoutException extends OsrmException
    implements TimeoutException {
  /// A request that took longer than [timeout].
  OsrmTimeoutException(this.timeout)
    : super(
        'OSRM request timed out after '
        '${timeout.inMilliseconds} ms',
      );

  /// The time the request was allowed.
  final Duration timeout;

  /// The same as [timeout], for [TimeoutException].
  @override
  Duration get duration => timeout;

  @override
  String get _name => 'OsrmTimeoutException';
}

/// The answer is not what OSRM sends: not UTF-8, not JSON, or JSON of an
/// unexpected shape. [message] names the field, such as
/// `routes[0].legs[0].steps[2].maneuver.location`.
final class OsrmFormatException extends OsrmException {
  /// A malformed answer, described by [message].
  const OsrmFormatException(super.message);

  @override
  String get _name => 'OsrmFormatException';
}
