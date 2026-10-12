import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'goong_exception.dart';
import 'goong_http.dart';

/// Place search on [Goong](https://goong.io)'s v2 APIs: a
/// [PlaceSearchProvider] for a destination search field.
///
/// - [autocomplete] calls autocomplete v2 (`GET /v2/place/autocomplete`).
///   Its suggestions have a `place_id` and **no position**.
/// - [resolve] calls place detail v2 (`GET /v2/place/detail?place_id=…`)
///   for the chosen suggestion's position.
/// - [reverse] calls geocode v2 (`GET /v2/geocode?latlng=…`).
///
/// **Sessions.** Goong bills an autocomplete session (any number of
/// autocomplete calls, then at most one place detail call, all with the
/// same `sessiontoken`) as one request. Pass the same
/// [PlaceSearchSession] to every [autocomplete] call of a search and to
/// the [resolve] of the chosen suggestion: its token is sent as
/// `sessiontoken`. A successful [resolve] ends the session: Goong bills a
/// reused token per request, so this search sends that session's token no
/// more. Start a new [PlaceSearchSession] for the next search.
///
/// It takes the same options as `GoongRouteProvider`: keep the API key on
/// a server by pointing [baseUrl] at a proxy and passing `apiKey: null`.
///
/// Failures throw a [GoongSearchException], a [PlaceSearchException] whose
/// `cause` is the [GoongException] (or the `http` client's error) that
/// says why.
class GoongPlaceSearch implements PlaceSearchProvider {
  /// A search on [baseUrl] (by default [defaultBaseUrl]).
  ///
  /// - [apiKey] is sent as the `api_key` query parameter; pass null to send
  ///   none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, to which `v2/place/autocomplete`,
  ///   `v2/place/detail` and `v2/geocode` are appended, and query
  ///   parameters, which are kept.
  /// - [headers] are added to every request, after `Accept` and
  ///   `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none. The
  ///   default is [defaultUserAgent], except on the web, where it is null
  ///   (no CORS preflight).
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the search creates one and [close] closes it.
  GoongPlaceSearch({
    required String? apiKey,
    Uri? baseUrl,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = goongPlatformUserAgent,
    http.Client? client,
  }) : _http = GoongHttp(
         owner: 'GoongPlaceSearch',
         apiKey: apiKey,
         baseUrl: baseUrl,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       );

  /// Goong's REST API root, `https://rsapi.goong.io/`.
  static final Uri defaultBaseUrl = goongApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = goongDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = goongUserAgent;

  final GoongHttp _http;

  /// The sessions a [resolve] of this search has ended.
  final Expando<bool> _ended = Expando('ended sessions');

  /// The API root, with any path prefix and query parameters.
  Uri get baseUrl => _http.baseUrl;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included.
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The suggestions for [query] (trimmed), best first, with no position:
  /// [resolve] gives it.
  ///
  /// [near] is sent as `location`, which ranks nearby places first.
  /// [session]'s token is sent as `sessiontoken`, unless a [resolve] ended
  /// it. An empty query returns an empty list without a request, and so
  /// does Goong's `ZERO_RESULTS`.
  ///
  /// A suggestion's title is the prediction's main text, else its
  /// description; its subtitle is the secondary text, else the rest of the
  /// description, or null when nothing is left.
  ///
  /// Throws [ArgumentError] for a [near] that is not finite, [StateError]
  /// after [close], and a [GoongSearchException] when the request fails.
  @override
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    GeoPoint? near,
    PlaceSearchSession? session,
  }) async {
    _http.checkOpen();
    if (near != null) checkFinite(near, 'near');
    final text = query.trim();
    if (text.isEmpty) return const [];
    final json = await _get(
      'autocomplete',
      ['place', 'autocomplete'],
      [
        ('input', text),
        if (near != null) ('location', latLng(near)),
        if (_token(session) case final token?) ('sessiontoken', token),
      ],
      allowed: const {'ZERO_RESULTS'},
    );
    return _guard('autocomplete', () {
      final body = _object(json);
      final raw = body['predictions'];
      if (raw == null && body['status'] == 'ZERO_RESULTS') return const [];
      final items = readList(raw, 'predictions');
      return [
        for (var i = 0; i < items.length; i++)
          _suggestion(items[i], 'predictions[$i]'),
      ];
    });
  }

  /// The place of [suggestion], from place detail v2: its position, its
  /// name (else the suggestion's title) and its formatted address.
  ///
  /// [session]'s token is sent as `sessiontoken`, unless a [resolve]
  /// already ended it; once this call succeeds, the session is ended.
  ///
  /// Throws [ArgumentError] for a suggestion without an id, [StateError]
  /// after [close], and a [GoongSearchException] when the request fails
  /// (`ZERO_RESULTS` or `NOT_FOUND` included: there is no place).
  @override
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    PlaceSearchSession? session,
  }) async {
    _http.checkOpen();
    if (suggestion.id.isEmpty) {
      throw ArgumentError.value(suggestion, 'suggestion', 'has no id');
    }
    final json = await _get(
      'place detail',
      ['place', 'detail'],
      [
        ('place_id', suggestion.id),
        if (_token(session) case final token?) ('sessiontoken', token),
      ],
    );
    final place = _guard('place detail', () {
      final result = readMap(_object(json)['result'], 'result');
      final id = readOptionalString(result['place_id'], 'result.place_id');
      final name = readOptionalString(result['name'], 'result.name') ?? '';
      final address = readOptionalString(
        result['formatted_address'],
        'result.formatted_address',
      );
      return Place(
        id: id == null || id.isEmpty ? suggestion.id : id,
        name: name.isNotEmpty ? name : suggestion.title,
        address: address == null || address.isEmpty ? null : address,
        position: readLocation(result, 'result'),
      );
    });
    if (session != null) _ended[session] = true;
    return place;
  }

  /// The place nearest to [point], from geocode v2 (`latlng`); null when
  /// Goong knows none there.
  ///
  /// The place's name is its `name`, else its `address`, else its formatted
  /// address; its address is the formatted address.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [GoongSearchException] when the request fails.
  @override
  Future<Place?> reverse(GeoPoint point) async {
    _http.checkOpen();
    checkFinite(point, 'point');
    final json = await _get(
      'geocode',
      ['geocode'],
      [('latlng', latLng(point))],
      allowed: const {'ZERO_RESULTS'},
    );
    return _guard('geocode', () {
      final body = _object(json);
      final raw = body['results'];
      if (raw == null && body['status'] == 'ZERO_RESULTS') return null;
      final items = readList(raw, 'results');
      if (items.isEmpty) return null;
      const at = 'results[0]';
      final item = readMap(items.first, at);
      final id = readOptionalString(item['place_id'], '$at.place_id') ?? '';
      final name = readOptionalString(item['name'], '$at.name') ?? '';
      final short = readOptionalString(item['address'], '$at.address') ?? '';
      final formatted =
          readOptionalString(
            item['formatted_address'],
            '$at.formatted_address',
          ) ??
          '';
      return Place(
        id: id,
        name: name.isNotEmpty
            ? name
            : short.isNotEmpty
            ? short
            : formatted,
        address: formatted.isEmpty ? null : formatted,
        position: readLocation(item, at),
      );
    });
  }

  /// Releases the HTTP client when the search created it; an injected
  /// client is left open. The search throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  /// [session]'s token, or null for no session or one a [resolve] ended.
  String? _token(PlaceSearchSession? session) =>
      session == null || (_ended[session] ?? false) ? null : session.token;

  /// The JSON of `v2/{path}`, its failures wrapped.
  Future<Object?> _get(
    String request,
    List<String> path,
    List<(String, String)> params, {
    Set<String> allowed = const {},
  }) async {
    try {
      return await _http.get(['v2', ...path], params, allowed: allowed);
    } on Exception catch (e) {
      throw GoongSearchException(request, e);
    }
  }

  /// The result of [parse], a [GoongFormatException] wrapped.
  static T _guard<T>(String request, T Function() parse) {
    try {
      return parse();
    } on GoongFormatException catch (e) {
      throw GoongSearchException(request, e);
    }
  }

  static Map<String, Object?> _object(Object? json) =>
      json is Map<String, Object?>
      ? json
      : throw GoongFormatException(
          'the answer is not a JSON object: got ${kindOf(json)}',
        );

  static PlaceSuggestion _suggestion(Object? json, String path) {
    final item = readMap(json, path);
    final id = readString(item['place_id'], '$path.place_id');
    final description =
        readOptionalString(item['description'], '$path.description') ?? '';
    final rawFormatting = item['structured_formatting'];
    final formatting = rawFormatting == null
        ? const <String, Object?>{}
        : readMap(rawFormatting, '$path.structured_formatting');
    final main =
        readOptionalString(
          formatting['main_text'],
          '$path.structured_formatting.main_text',
        ) ??
        '';
    final secondary =
        readOptionalString(
          formatting['secondary_text'],
          '$path.structured_formatting.secondary_text',
        ) ??
        '';
    final title = main.isNotEmpty ? main : description;
    final String? subtitle;
    if (secondary.isNotEmpty) {
      subtitle = secondary;
    } else if (description.isEmpty || description == title) {
      subtitle = null;
    } else if (description.startsWith('$title,')) {
      final rest = description.substring(title.length + 1).trim();
      subtitle = rest.isEmpty ? null : rest;
    } else {
      subtitle = description;
    }
    return PlaceSuggestion(id: id, title: title, subtitle: subtitle);
  }
}
