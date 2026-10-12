import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'vietmap_exception.dart';

/// Vietmap's REST API root, `https://maps.vietmap.vn/api/`.
final Uri vietmapApi = Uri.parse('https://maps.vietmap.vn/api/');

/// The default timeout of every request: 12 seconds.
const Duration vietmapDefaultTimeout = Duration(seconds: 12);

/// The default `User-Agent` off the web, which names this package.
const String vietmapUserAgent = 'navigation_engine_vietmap/0.1.0';

/// [vietmapUserAgent], or null on the web: a browser that honours the
/// header treats it as not CORS-safelisted and sends a preflight.
const String? vietmapPlatformUserAgent =
    bool.fromEnvironment('dart.library.js_interop') ? null : vietmapUserAgent;

/// The requests both public classes make: the key, the base URL, the
/// headers, the timeout, the status and JSON checks. Not exported.
final class VietmapHttp {
  /// A connection for [owner] (named in [StateError]s).
  VietmapHttp({
    required this.owner,
    required String? apiKey,
    required Uri? baseUrl,
    required Map<String, String> headers,
    required this.timeout,
    required this.userAgent,
    required http.Client? client,
  }) : _apiKey = apiKey,
       baseUrl = baseUrl ?? vietmapApi,
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
  /// after the key, and returns the decoded JSON of a 200 answer.
  ///
  /// Every server string an exception quotes (the code, the messages, the
  /// reason phrase, the body) has the key scrubbed.
  ///
  /// Throws [VietmapCodeException] for a body whose `code` is not `OK`,
  /// [VietmapHttpException] for another HTTP error, [VietmapTimeoutException]
  /// after [timeout], and [VietmapFormatException] for a body that is not
  /// UTF-8 JSON (for one that is not JSON, a fixed message and, as its
  /// cause, a `FormatException` that keeps only the parser's offset: no
  /// text of the body, so no fragment of the key). Transport errors pass through, the key in their URL and
  /// their message redacted.
  Future<Object?> get(List<String> path, List<(String, String)> params) async {
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
        throw VietmapTimeoutException(timeout);
      },
    );

    // Decoded once: UTF-8, then JSON.
    final text = _text(response);
    Object? json;
    FormatException? jsonError;
    if (text != null) {
      try {
        json = jsonDecode(text);
      } on FormatException catch (e) {
        // Only the offset is kept: on the web the parser's message quotes
        // the body around the error, where part of the key could be.
        jsonError = FormatException('invalid JSON', null, e.offset);
      }
    }
    final status = response.statusCode;
    final code = json is Map<String, Object?> ? json['code'] : null;
    if (status != 200) {
      if (code is String && code != 'OK') {
        throw VietmapCodeException(
          _scrubbed(code)!,
          serverMessage: _scrubbed(
            _serverMessage(json! as Map<String, Object?>),
          ),
          statusCode: status,
        );
      }
      throw VietmapHttpException(
        status,
        reasonPhrase: _scrubbed(response.reasonPhrase),
        body: _scrubbed(text) ?? '',
      );
    }
    if (text == null) {
      throw const VietmapFormatException('the body is not UTF-8');
    }
    if (jsonError != null) {
      // A fixed message: see [jsonError].
      throw VietmapFormatException('invalid JSON', cause: jsonError);
    }
    if (code != null) {
      if (code is! String) {
        throw VietmapFormatException(
          'code: expected a string, got ${kindOf(code)}',
        );
      }
      if (code != 'OK') {
        throw VietmapCodeException(
          _scrubbed(code)!,
          serverMessage: _scrubbed(
            _serverMessage(json! as Map<String, Object?>),
          ),
          statusCode: status,
        );
      }
    }
    return json;
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e, stack) {
      final uri = e.uri;
      final params = uri == null || !uri.hasQuery
          ? const <String, List<String>>{}
          : uri.queryParametersAll;
      final inUri = _apiKey != null && params.containsKey('apikey');
      final message = _scrubbed(e.message)!;
      if (!inUri && message == e.message) rethrow;
      Error.throwWithStackTrace(
        http.ClientException(
          message,
          inUri
              ? uri!.replace(
                  queryParameters: {
                    ...params,
                    'apikey': const ['REDACTED'],
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
    // Built by hand: Vietmap's documentation writes `,` as it is (in
    // `point=lat,lng`), and a space is sent as %20, not `+`.
    final query = [
      if (baseUrl.query.isNotEmpty) baseUrl.query,
      if (_apiKey case final key?) 'apikey=${_encode(key)}',
      for (final (name, value) in params) '$name=${_encode(value)}',
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

  /// The server's `messages` (a string, or strings joined with `; `), or
  /// its `message`.
  static String? _serverMessage(Map<String, Object?> body) =>
      switch (body['messages'] ?? body['message']) {
        final String m => m,
        final List<Object?> list => list.whereType<String>().join('; '),
        _ => null,
      };

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

/// `lat,lng` (or one of them) with six decimals, without `-0.000000`.
String fixed6(double v) {
  final s = v.toStringAsFixed(6);
  return s == '-0.000000' ? '0.000000' : s;
}

/// Throws [ArgumentError] named [name] when [p] is not finite.
void checkFinite(GeoPoint p, String name) {
  if (!p.lat.isFinite || !p.lng.isFinite) {
    throw ArgumentError.value(p, name, 'is not finite');
  }
}

// Typed reads that name the field when the JSON is not what Vietmap sends.

/// [json] as an object, or a [VietmapFormatException] naming [path].
Map<String, Object?> readMap(Object? json, String path) =>
    json is Map<String, Object?>
    ? json
    : throw VietmapFormatException(
        '$path: expected an object, got ${kindOf(json)}',
      );

/// [json] as an array, or a [VietmapFormatException] naming [path].
List<Object?> readList(Object? json, String path) => json is List<Object?>
    ? json
    : throw VietmapFormatException(
        '$path: expected an array, got ${kindOf(json)}',
      );

/// [json] as a finite number, or a [VietmapFormatException] naming [path].
double readNumber(Object? json, String path) => json is num && json.isFinite
    ? json.toDouble()
    : throw VietmapFormatException(
        '$path: expected a number, got ${json is num ? json : kindOf(json)}',
      );

/// [json] as a string, or a [VietmapFormatException] naming [path].
String readString(Object? json, String path) => json is String
    ? json
    : throw VietmapFormatException(
        '$path: expected a string, got ${kindOf(json)}',
      );

/// [json] as a string, null when absent.
String? readOptionalString(Object? json, String path) =>
    json == null ? null : readString(json, path);
