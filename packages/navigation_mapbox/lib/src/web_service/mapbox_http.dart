import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'mapbox_directions_exception.dart';

/// Mapbox's API root, `https://api.mapbox.com`.
final Uri mapboxApi = Uri.parse('https://api.mapbox.com');

/// The default timeout of every request: 12 seconds.
const Duration mapboxDefaultTimeout = Duration(seconds: 12);

/// The default `User-Agent` off the web, which names this package.
const String mapboxUserAgent = 'navigation_mapbox/0.1.0';

/// [mapboxUserAgent], or null on the web: a browser that honours the
/// header treats it as not CORS-safelisted and sends a preflight.
const String? mapboxPlatformUserAgent =
    bool.fromEnvironment('dart.library.js_interop') ? null : mapboxUserAgent;

/// The requests both public classes make: the token, the base URL, the
/// headers, the timeout, the status and JSON checks, and the token scrub.
/// Not exported.
final class MapboxHttp {
  /// A connection for [owner] (named in [StateError]s).
  MapboxHttp({
    required this.owner,
    required String? accessToken,
    required Uri? baseUrl,
    required Map<String, String> headers,
    required this.timeout,
    required this.userAgent,
    required http.Client? client,
  }) : _token = accessToken,
       baseUrl = baseUrl ?? mapboxApi,
       headers = Map.unmodifiable(headers),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The class that uses it, for error messages.
  final String owner;

  /// The API root, with any path prefix and query parameters.
  final Uri baseUrl;

  /// Headers added to every request, after `Accept` and `User-Agent`.
  final Map<String, String> headers;

  /// How long a request may take, its body included.
  final Duration timeout;

  /// The `User-Agent` header, or null to send none.
  final String? userAgent;

  final String? _token;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  /// Throws [StateError] after [close].
  void checkOpen() {
    if (_closed) throw StateError('$owner is closed');
  }

  /// Closes the client when this created it. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  /// GETs [path] (appended to [baseUrl]'s path, each segment encoded) with
  /// [params], in order, then the token, and returns the JSON object of a
  /// 200 answer. The values of [params] are percent-encoded, except `,`
  /// and `;`, which Mapbox's documentation writes as they are.
  ///
  /// Every server string an exception quotes (the code, the server
  /// message, the reason phrase, the body) has the token scrubbed. Throws
  /// [MapboxDirectionsCodeException] for an HTTP error other than 401 and
  /// 403 whose body has a `code`; [MapboxDirectionsHttpException] for
  /// another HTTP error (a 401 or 403 always);
  /// [MapboxDirectionsTimeoutException] after [timeout]; and
  /// [MapboxDirectionsFormatException] for a 200 answer that is not a UTF-8
  /// JSON object (for one that is not JSON, a fixed message and, as its
  /// cause, a `FormatException` that keeps only the parser's offset: no
  /// text of the body, so no fragment of the token). Transport errors pass through, the token in their URL
  /// and message redacted.
  Future<Map<String, Object?>> get(
    List<String> path,
    List<(String, String)> params,
  ) async {
    checkOpen();
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      _uri(path, params),
      abortTrigger: abort.future,
    )..headers['Accept'] = 'application/json';
    if (userAgent case final agent?) request.headers['User-Agent'] = agent;
    request.headers.addAll(headers);

    // onTimeout rather than catching TimeoutException: a TimeoutException
    // the client itself throws passes through as it is.
    final response = await _send(request).timeout(
      timeout,
      onTimeout: () {
        abort.complete();
        throw MapboxDirectionsTimeoutException(timeout);
      },
    );

    // Decoded once: UTF-8, then JSON.
    final text = _text(response);
    Object? json;
    // The parser's error, without its text: V8's message quotes the body
    // around the error, a fragment of which may be the token. Only the
    // offset is kept.
    FormatException? jsonError;
    if (text != null) {
      try {
        json = jsonDecode(text);
      } on FormatException catch (e) {
        jsonError = FormatException('invalid JSON', null, e.offset);
      }
    }
    final status = response.statusCode;
    if (status != 200) {
      // 401 and 403 are about the token or the account, whatever code the
      // body names: the HTTP exception, whose hint says so.
      if (json case {
        'code': final String code,
      } when status != 401 && status != 403) {
        throw codeException(json as Map<String, Object?>, code, status);
      }
      throw MapboxDirectionsHttpException(
        status,
        reasonPhrase: scrubbed(response.reasonPhrase),
        body: scrubbed(text) ?? '',
      );
    }
    if (json is Map<String, Object?>) return json;
    if (jsonError != null) {
      // A fixed message: see [jsonError].
      throw MapboxDirectionsFormatException(
        'the answer is not a JSON object: invalid JSON',
        cause: jsonError,
      );
    }
    final why = text == null ? 'the body is not UTF-8' : 'got ${kindOf(json)}';
    throw MapboxDirectionsFormatException(
      'the answer is not a JSON object: $why',
    );
  }

  /// The [MapboxDirectionsCodeException] of [body], whose `code` is [code]
  /// and whose HTTP status was [status], its strings scrubbed.
  MapboxDirectionsCodeException codeException(
    Map<String, Object?> body,
    String code,
    int status,
  ) => MapboxDirectionsCodeException(
    scrubbed(code)!,
    serverMessage: switch (body['message']) {
      final String m => scrubbed(m),
      _ => null,
    },
    statusCode: status,
  );

  /// [text] with the token replaced by `REDACTED`: as it is, and in the
  /// percent-encoded forms a server or proxy may echo (either hex case,
  /// `%20` or `+` for a space). Unchanged without a token.
  String? scrubbed(String? text) {
    final token = _token;
    if (text == null || token == null || token.isEmpty) return text;
    var out = text;
    final encoded =
        {
            Uri.encodeComponent(token),
            _encode(token),
            Uri.encodeQueryComponent(token),
          }.where((form) => form != token).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final form in encoded) {
      out = out.replaceAll(
        RegExp(RegExp.escape(form), caseSensitive: false),
        'REDACTED',
      );
    }
    return out.replaceAll(token, 'REDACTED');
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e, stack) {
      final uri = e.uri;
      final params = uri == null || !uri.hasQuery
          ? const <String, List<String>>{}
          : uri.queryParametersAll;
      final inUri = _token != null && params.containsKey('access_token');
      final message = scrubbed(e.message)!;
      if (!inUri && message == e.message) rethrow;
      Error.throwWithStackTrace(
        http.ClientException(
          message,
          inUri
              ? uri!.replace(
                  queryParameters: {
                    ...params,
                    'access_token': const ['REDACTED'],
                  },
                )
              : uri,
        ),
        stack,
      );
    }
  }

  Uri _uri(List<String> path, List<(String, String)> params) {
    // Built by hand: Mapbox's documentation writes `,` and `;` as they are
    // (`proximity=lon,lat`, `bearings=90,45;`), and a space is sent as
    // %20, not `+`.
    final query = [
      if (baseUrl.query.isNotEmpty) baseUrl.query,
      for (final (name, value) in params) '$name=${_encode(value)}',
      if (_token case final token?)
        'access_token=${Uri.encodeComponent(token)}',
    ].join('&');
    return baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
        ...path,
      ],
      query: query,
    );
  }

  static String _encode(String value) =>
      Uri.encodeComponent(value).replaceAll('%2C', ',').replaceAll('%3B', ';');

  /// The body as UTF-8, or null when it is not.
  static String? _text(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return null;
    }
  }
}

/// What kind of JSON value [json] is, for error messages.
String kindOf(Object? json) => switch (json) {
  Map<Object?, Object?>() => 'an object',
  List<Object?>() => 'an array',
  String() => 'a string',
  num() => 'a number',
  bool() => 'a boolean',
  null => 'null',
  _ => 'a ${json.runtimeType}',
};

/// Throws [ArgumentError] named [name] when [p] is not finite.
void checkFinite(GeoPoint p, String name) {
  if (!p.lat.isFinite || !p.lng.isFinite) {
    throw ArgumentError.value(p, name, 'is not finite');
  }
}

/// `lon,lat`, each with its full precision (see [coordinate]).
String lonLat(GeoPoint p) => '${coordinate(p.lng)},${coordinate(p.lat)}';

/// [v] in decimal with every digit the double has: the shortest form that
/// reads back as [v], without an exponent (`0.0000001`, not `1e-7`),
/// without `.0` for a whole number, and `0` for -0. The same on the VM and
/// on the web.
String coordinate(double v) {
  if (v == 0) return '0';
  var s = v.toString();
  if (s.contains('e')) {
    // Only for |v| < 1e-6 among coordinates: 20 decimals are enough.
    s = v.toStringAsFixed(20).replaceFirst(RegExp(r'0+$'), '');
  }
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

// Typed reads that name the field when the JSON is not what Mapbox sends.

/// [json] as an object, or a [MapboxDirectionsFormatException] naming
/// [path].
Map<String, Object?> readMap(Object? json, String path) =>
    json is Map<String, Object?>
    ? json
    : throw MapboxDirectionsFormatException(
        '$path: expected an object, got ${kindOf(json)}',
      );

/// [json] as an array, or a [MapboxDirectionsFormatException] naming
/// [path].
List<Object?> readList(Object? json, String path) => json is List<Object?>
    ? json
    : throw MapboxDirectionsFormatException(
        '$path: expected an array, got ${kindOf(json)}',
      );

/// [json] as a finite number, or a [MapboxDirectionsFormatException]
/// naming [path].
double readNumber(Object? json, String path) => json is num && json.isFinite
    ? json.toDouble()
    : throw MapboxDirectionsFormatException(
        '$path: expected a number, got ${json is num ? json : kindOf(json)}',
      );

/// [json] as a string, or a [MapboxDirectionsFormatException] naming
/// [path].
String readString(Object? json, String path) => json is String
    ? json
    : throw MapboxDirectionsFormatException(
        '$path: expected a string, got ${kindOf(json)}',
      );

/// [json] as a string, null when absent.
String? readOptionalString(Object? json, String path) =>
    json == null ? null : readString(json, path);

/// A GeoJSON `[longitude, latitude]` pair at [path], range-checked.
GeoPoint readLngLat(Object? json, String path) {
  final pair = readList(json, path);
  if (pair.length < 2) {
    throw MapboxDirectionsFormatException(
      '$path: expected [longitude, latitude]',
    );
  }
  final lng = readNumber(pair[0], '$path[0]');
  final lat = readNumber(pair[1], '$path[1]');
  if (lng.abs() > 180) {
    throw MapboxDirectionsFormatException('$path[0]: out of range ($lng)');
  }
  if (lat.abs() > 90) {
    throw MapboxDirectionsFormatException('$path[1]: out of range ($lat)');
  }
  return GeoPoint(lat, lng);
}
