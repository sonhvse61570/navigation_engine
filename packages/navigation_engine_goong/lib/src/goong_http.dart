import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'goong_exception.dart';

/// Goong's REST API root, `https://rsapi.goong.io/`.
final Uri goongApi = Uri.parse('https://rsapi.goong.io/');

/// The default timeout of every request: 12 seconds.
const Duration goongDefaultTimeout = Duration(seconds: 12);

/// The default `User-Agent` off the web, which names this package.
const String goongUserAgent = 'navigation_engine_goong/0.1.0';

/// [goongUserAgent], or null on the web: a browser that honours the header
/// treats it as not CORS-safelisted and sends a preflight.
const String? goongPlatformUserAgent =
    bool.fromEnvironment('dart.library.js_interop') ? null : goongUserAgent;

/// The requests both public classes make: the key, the base URL, the
/// headers, the timeout, the status and JSON checks. Not exported.
final class GoongHttp {
  /// A connection for [owner] (named in [StateError]s).
  GoongHttp({
    required this.owner,
    required String? apiKey,
    required Uri? baseUrl,
    required Map<String, String> headers,
    required this.timeout,
    required this.userAgent,
    required http.Client? client,
  }) : _apiKey = apiKey,
       baseUrl = baseUrl ?? goongApi,
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

  final String? _apiKey;
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

  /// GETs [path] (appended to [baseUrl]'s path) with [params], in order,
  /// then the key, and returns the decoded JSON of a 200 answer.
  ///
  /// A `status` in [allowed] (such as `ZERO_RESULTS` for a search) is not an
  /// error. Every server string an exception quotes (the code, the server
  /// message, the reason phrase, the body) has the key scrubbed. Throws [GoongCodeException] for a body with another `status`
  /// than `OK`, or an `error`; [GoongHttpException] for another HTTP error;
  /// [GoongTimeoutException] after [timeout]; and [GoongFormatException]
  /// for a body that is not UTF-8 JSON. Transport errors pass through, the
  /// key in their URL and message redacted.
  Future<Object?> get(
    List<String> path,
    List<(String, String)> params, {
    Set<String> allowed = const {},
  }) async {
    checkOpen();
    final uri = _uri(path, params);
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      uri,
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
        throw GoongTimeoutException(timeout);
      },
    );

    // Decoded once: UTF-8, then JSON.
    final text = _text(response);
    Object? json;
    String? jsonError;
    if (text != null) {
      try {
        json = jsonDecode(text);
      } on FormatException catch (e) {
        jsonError = e.message;
      }
    }
    final status = response.statusCode;
    if (status != 200) {
      if (json is Map<String, Object?>) {
        if (_error(json) case (final code, final message)?) {
          throw GoongCodeException(
            _scrubbed(code)!,
            serverMessage: _scrubbed(message),
            statusCode: status,
          );
        }
      }
      throw GoongHttpException(
        status,
        reasonPhrase: _scrubbed(response.reasonPhrase),
        body: _scrubbed(text) ?? '',
      );
    }
    if (text == null) {
      throw const GoongFormatException('the body is not UTF-8');
    }
    if (jsonError != null) {
      throw GoongFormatException('invalid JSON ($jsonError)');
    }
    if (json is Map<String, Object?>) {
      final statusField = json['status'];
      if (statusField != null && statusField is! String) {
        throw GoongFormatException(
          'status: expected a string, got ${kindOf(statusField)}',
        );
      }
      if (_error(json) case (final code, final message)?
          when !allowed.contains(code)) {
        throw GoongCodeException(
          _scrubbed(code)!,
          serverMessage: _scrubbed(message),
          statusCode: status,
        );
      }
    }
    return json;
  }

  /// The code and message of an error body: a `status` other than `OK`
  /// (with `error_message`), or an `error` object (`code`, `message`) or
  /// string. Null for a body that reports no error.
  static (String, String?)? _error(Map<String, Object?> body) {
    final status = body['status'];
    if (status is String && status != 'OK') {
      return (status, _string(body['error_message'] ?? body['message']));
    }
    return switch (body['error']) {
      final Map<String, Object?> error => (
        switch (error['code'] ?? error['status']) {
          final String code when code.isNotEmpty => code,
          final num code => '$code',
          _ => 'ERROR',
        },
        _string(error['message']),
      ),
      final String message => ('ERROR', message),
      _ => null,
    };
  }

  static String? _string(Object? json) => json is String ? json : null;

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e, stack) {
      final uri = e.uri;
      final params = uri == null || !uri.hasQuery
          ? const <String, List<String>>{}
          : uri.queryParametersAll;
      final inUri = _apiKey != null && params.containsKey('api_key');
      final message = _scrubbed(e.message)!;
      if (!inUri && message == e.message) rethrow;
      Error.throwWithStackTrace(
        http.ClientException(
          message,
          inUri
              ? uri!.replace(
                  queryParameters: {
                    ...params,
                    'api_key': const ['REDACTED'],
                  },
                )
              : uri,
        ),
        stack,
      );
    }
  }

  /// [text] with the key replaced by `REDACTED`: as it is, and in the
  /// percent-encoded forms a server or proxy may echo (either hex case,
  /// `%20` or `+` for a space). Unchanged without a key.
  String? _scrubbed(String? text) {
    final key = _apiKey;
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

  Uri _uri(List<String> path, List<(String, String)> params) {
    // Built by hand: Goong's documentation writes `,` as it is (in
    // `origin=lat,lng`), and a space is sent as %20, not `+`.
    final query = [
      if (baseUrl.query.isNotEmpty) baseUrl.query,
      for (final (name, value) in params) '$name=${_encode(value)}',
      if (_apiKey case final key?) 'api_key=${_encode(key)}',
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

/// `lat,lng` with six decimals each, without `-0.000000`.
String latLng(GeoPoint p) => '${_fixed6(p.lat)},${_fixed6(p.lng)}';

String _fixed6(double v) {
  final s = v.toStringAsFixed(6);
  return s == '-0.000000' ? '0.000000' : s;
}

/// Throws [ArgumentError] named [name] when [p] is not finite.
void checkFinite(GeoPoint p, String name) {
  if (!p.lat.isFinite || !p.lng.isFinite) {
    throw ArgumentError.value(p, name, 'is not finite');
  }
}

// Typed reads that name the field when the JSON is not what Goong sends.

/// [json] as an object, or a [GoongFormatException] naming [path].
Map<String, Object?> readMap(Object? json, String path) =>
    json is Map<String, Object?>
    ? json
    : throw GoongFormatException(
        '$path: expected an object, got ${kindOf(json)}',
      );

/// [json] as an array, or a [GoongFormatException] naming [path].
List<Object?> readList(Object? json, String path) => json is List<Object?>
    ? json
    : throw GoongFormatException(
        '$path: expected an array, got ${kindOf(json)}',
      );

/// [json] as a finite number, or a [GoongFormatException] naming [path].
double readNumber(Object? json, String path) => json is num && json.isFinite
    ? json.toDouble()
    : throw GoongFormatException(
        '$path: expected a number, got ${json is num ? json : kindOf(json)}',
      );

/// [json] as a string, or a [GoongFormatException] naming [path].
String readString(Object? json, String path) => json is String
    ? json
    : throw GoongFormatException(
        '$path: expected a string, got ${kindOf(json)}',
      );

/// [json] as a string, null when absent.
String? readOptionalString(Object? json, String path) =>
    json == null ? null : readString(json, path);

/// The `geometry.location` of [item] (at [path]), range-checked.
GeoPoint readLocation(Map<String, Object?> item, String path) {
  final geometry = readMap(item['geometry'], '$path.geometry');
  final location = readMap(geometry['location'], '$path.geometry.location');
  final at = '$path.geometry.location';
  final lat = readNumber(location['lat'], '$at.lat');
  final lng = readNumber(location['lng'], '$at.lng');
  if (lat.abs() > 90) {
    throw GoongFormatException('$at.lat: out of range ($lat)');
  }
  if (lng.abs() > 180) {
    throw GoongFormatException('$at.lng: out of range ($lng)');
  }
  return GeoPoint(lat, lng);
}
