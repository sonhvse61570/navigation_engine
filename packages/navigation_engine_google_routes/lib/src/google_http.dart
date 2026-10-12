import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'google_routes_exception.dart';

/// The Routes API's root, `https://routes.googleapis.com`.
final Uri googleRoutesApi = Uri.parse('https://routes.googleapis.com');

/// The Places API (New)'s root, `https://places.googleapis.com`.
final Uri googlePlacesApi = Uri.parse('https://places.googleapis.com');

/// The Geocoding API's root, `https://maps.googleapis.com`.
final Uri googleGeocodingApi = Uri.parse('https://maps.googleapis.com');

/// The default timeout of every request: 12 seconds.
const Duration googleDefaultTimeout = Duration(seconds: 12);

/// The default `User-Agent` off the web, which names this package.
const String googleUserAgent = 'navigation_engine_google_routes/0.1.0';

/// [googleUserAgent], or null on the web: a browser that honours the
/// header treats it as not CORS-safelisted and sends a preflight.
const String? googlePlatformUserAgent =
    bool.fromEnvironment('dart.library.js_interop') ? null : googleUserAgent;

/// The requests both public classes make: the key, the headers, the
/// timeout, the status and JSON checks, and the key scrub. Not exported.
final class GoogleHttp {
  /// A connection for [owner] (named in [StateError]s).
  GoogleHttp({
    required this.owner,
    required String? apiKey,
    required Map<String, String> headers,
    required this.timeout,
    required this.userAgent,
    required http.Client? client,
  }) : _key = apiKey,
       headers = Map.unmodifiable(headers),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The class that uses it, for error messages.
  final String owner;

  /// Headers added to every request, after the package's own.
  final Map<String, String> headers;

  /// How long a request may take, its body included.
  final Duration timeout;

  /// The `User-Agent` header, or null to send none.
  final String? userAgent;

  final String? _key;
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

  /// The `key` query parameter, for the Geocoding API (which takes the key
  /// in the URL); empty without a key.
  List<(String, String)> get keyParam => [
    if (_key case final key?) ('key', key),
  ];

  /// Sends [method] to [path] (appended to [base]'s path, each segment
  /// encoded) with [params] (after [base]'s own query), [body] as JSON
  /// when given, and returns the JSON object of a 200 answer.
  ///
  /// The key is sent in the `X-Goog-Api-Key` header, unless [keyInQuery]
  /// (the caller then puts [keyParam] in [params]); [fieldMask] is sent as
  /// `X-Goog-FieldMask`. Every server string an exception quotes has the
  /// key scrubbed. Throws [GoogleRoutesHttpException] for a 401 or 403, or
  /// an HTTP error whose body is not a Google error;
  /// [GoogleRoutesStatusException] for another HTTP error with a Google
  /// error body; [GoogleRoutesTimeoutException] after [timeout]; and
  /// [GoogleRoutesFormatException] for a 200 answer that is not a UTF-8
  /// JSON object (for one that is not JSON, a fixed message and, as its
  /// cause, a `FormatException` that keeps only the parser's offset: no
  /// text of the body, so no fragment of the key). Transport errors pass through, the key in their URL and
  /// message redacted.
  Future<Map<String, Object?>> send(
    String method,
    Uri base,
    List<String> path, {
    List<(String, String)> params = const [],
    Object? body,
    String? fieldMask,
    bool keyInQuery = false,
  }) async {
    checkOpen();
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      _uri(base, path, params),
      abortTrigger: abort.future,
    )..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    if (userAgent case final agent?) request.headers['User-Agent'] = agent;
    if (!keyInQuery) {
      if (_key case final key?) request.headers['X-Goog-Api-Key'] = key;
    }
    if (fieldMask != null) request.headers['X-Goog-FieldMask'] = fieldMask;
    request.headers.addAll(headers);

    // onTimeout rather than catching TimeoutException: a TimeoutException
    // the client itself throws passes through as it is.
    final response = await _send(request).timeout(
      timeout,
      onTimeout: () {
        abort.complete();
        throw GoogleRoutesTimeoutException(timeout);
      },
    );

    // Decoded once: UTF-8, then JSON.
    final text = _text(response);
    Object? json;
    // The parser's error, without its text: V8's message quotes the body
    // around the error, a fragment of which may be the key. Only the
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
      if (json case {
        'error':
            {'status': final String rpcStatus} &&
            final Map<Object?, Object?> error,
      }) {
        final message = switch (error['message']) {
          final String m => scrubbed(m),
          _ => null,
        };
        // 401 and 403 are about the key, the project or billing, whatever
        // the status: the HTTP exception, whose hint says so.
        if (status == 401 || status == 403) {
          throw GoogleRoutesHttpException(
            status,
            status: scrubbed(rpcStatus),
            serverMessage: message,
            reasonPhrase: scrubbed(response.reasonPhrase),
          );
        }
        throw GoogleRoutesStatusException(
          scrubbed(rpcStatus)!,
          serverMessage: message,
          statusCode: status,
        );
      }
      throw GoogleRoutesHttpException(
        status,
        reasonPhrase: scrubbed(response.reasonPhrase),
        body: scrubbed(text) ?? '',
      );
    }
    if (json is Map<String, Object?>) return json;
    if (jsonError != null) {
      // A fixed message: see [jsonError].
      throw GoogleRoutesFormatException(
        'the answer is not a JSON object: invalid JSON',
        cause: jsonError,
      );
    }
    final why = text == null ? 'the body is not UTF-8' : 'got ${kindOf(json)}';
    throw GoogleRoutesFormatException('the answer is not a JSON object: $why');
  }

  /// [text] with the key replaced by `REDACTED`: as it is, and in the
  /// percent-encoded forms a server or proxy may echo (either hex case,
  /// `%20` or `+` for a space). Unchanged without a key.
  String? scrubbed(String? text) {
    final key = _key;
    if (text == null || key == null || key.isEmpty) return text;
    var out = text;
    final encoded =
        {
            Uri.encodeComponent(key),
            _encode(key),
            Uri.encodeQueryComponent(key),
          }.where((form) => form != key).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final form in encoded) {
      out = out.replaceAll(
        RegExp(RegExp.escape(form), caseSensitive: false),
        'REDACTED',
      );
    }
    return out.replaceAll(key, 'REDACTED');
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e, stack) {
      final uri = e.uri;
      final params = uri == null || !uri.hasQuery
          ? const <String, List<String>>{}
          : uri.queryParametersAll;
      final inUri = _key != null && params.containsKey('key');
      final message = scrubbed(e.message)!;
      if (!inUri && message == e.message) rethrow;
      Error.throwWithStackTrace(
        http.ClientException(
          message,
          inUri
              ? uri!.replace(
                  queryParameters: {
                    ...params,
                    'key': const ['REDACTED'],
                  },
                )
              : uri,
        ),
        stack,
      );
    }
  }

  static Uri _uri(Uri base, List<String> path, List<(String, String)> params) {
    // Built by hand: Google's documentation writes `,` as it is
    // (`latlng=lat,lng`), and a space is sent as %20, not `+`.
    final query = [
      if (base.query.isNotEmpty) base.query,
      for (final (name, value) in params) '$name=${_encode(value)}',
    ].join('&');
    return base.replace(
      pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), ...path],
      query: query.isEmpty ? null : query,
    );
  }

  static String _encode(String value) =>
      Uri.encodeComponent(value).replaceAll('%2C', ',');

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

// Typed reads that name the field when the JSON is not what Google sends.

/// [json] as an object, or a [GoogleRoutesFormatException] naming [path].
Map<String, Object?> readMap(Object? json, String path) =>
    json is Map<String, Object?>
    ? json
    : throw GoogleRoutesFormatException(
        '$path: expected an object, got ${kindOf(json)}',
      );

/// [json] as an object, null when absent.
Map<String, Object?>? readOptionalMap(Object? json, String path) =>
    json == null ? null : readMap(json, path);

/// [json] as an array, or a [GoogleRoutesFormatException] naming [path].
List<Object?> readList(Object? json, String path) => json is List<Object?>
    ? json
    : throw GoogleRoutesFormatException(
        '$path: expected an array, got ${kindOf(json)}',
      );

/// [json] as a finite number, or a [GoogleRoutesFormatException] naming
/// [path].
double readNumber(Object? json, String path) => json is num && json.isFinite
    ? json.toDouble()
    : throw GoogleRoutesFormatException(
        '$path: expected a number, got ${json is num ? json : kindOf(json)}',
      );

/// [json] as a string, or a [GoogleRoutesFormatException] naming [path].
String readString(Object? json, String path) => json is String
    ? json
    : throw GoogleRoutesFormatException(
        '$path: expected a string, got ${kindOf(json)}',
      );

/// [json] as a string, null when absent.
String? readOptionalString(Object? json, String path) =>
    json == null ? null : readString(json, path);

/// The position of [json] at [path], an object whose [latName] and
/// [lngName] are degrees, range-checked.
GeoPoint readPosition(
  Object? json,
  String path, {
  String latName = 'latitude',
  String lngName = 'longitude',
}) {
  final map = readMap(json, path);
  final lat = readNumber(map[latName], '$path.$latName');
  final lng = readNumber(map[lngName], '$path.$lngName');
  if (lat.abs() > 90) {
    throw GoogleRoutesFormatException('$path.$latName: out of range ($lat)');
  }
  if (lng.abs() > 180) {
    throw GoogleRoutesFormatException('$path.$lngName: out of range ($lng)');
  }
  return GeoPoint(lat, lng);
}
