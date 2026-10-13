import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'vietmap_exception.dart';
import 'vietmap_http.dart';

/// Place search on [Vietmap](https://maps.vietmap.vn)'s v4 APIs: a
/// [PlaceSearchProvider] for a destination search field.
///
/// - [autocomplete] calls autocomplete v4 (`GET /api/autocomplete/v4`).
///   Its suggestions have a reference id (`ref_id`) and **no position**.
/// - [resolve] calls place v4 (`GET /api/place/v4?refid=…`) for the
///   chosen suggestion's position. Vietmap bills each place call as a
///   transaction: resolve only the suggestion the user picks.
/// - [reverse] calls reverse v4 (`GET /api/reverse/v4?lat=…&lng=…`).
///
/// Vietmap does not bill per session, so the [PlaceSearchSession]s are
/// accepted and ignored. Addresses come in the server's default format,
/// the two-level (ward, city) one of Vietnam's 2025 administrative reform.
///
/// It takes the same options as `VietmapRouteProvider`: keep the services
/// key on a server by pointing [baseUrl] at a proxy and passing
/// `apiKey: null`.
///
/// Failures throw a [VietmapSearchException], a [PlaceSearchException]
/// whose `cause` is the [VietmapException] (or the `http` client's error)
/// that says why.
class VietmapPlaceSearch implements PlaceSearchProvider {
  /// A search on [baseUrl] (by default [defaultBaseUrl]).
  ///
  /// - [apiKey] is sent as the `apikey` query parameter; pass null to send
  ///   none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, to which `autocomplete/v4`,
  ///   `place/v4` and `reverse/v4` are appended, and query parameters,
  ///   which are kept.
  /// - [headers] are added to every request, after `Accept` and
  ///   `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none. The
  ///   default is [defaultUserAgent], except on the web, where it is null
  ///   (no CORS preflight).
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the search creates one and [close] closes it.
  VietmapPlaceSearch({
    required String? apiKey,
    Uri? baseUrl,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = vietmapPlatformUserAgent,
    http.Client? client,
  }) : _http = VietmapHttp(
         owner: 'VietmapPlaceSearch',
         apiKey: apiKey,
         baseUrl: baseUrl,
         headers: headers,
         timeout: timeout,
         userAgent: userAgent,
         client: client,
       );

  /// Vietmap's REST API root, `https://maps.vietmap.vn/api/`.
  static final Uri defaultBaseUrl = vietmapApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = vietmapDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = vietmapUserAgent;

  /// The fewest characters [autocomplete] sends, as Vietmap asks ("send at
  /// least 2 characters", autocomplete v4 documentation); a shorter query
  /// returns no suggestions without a request.
  static const int minQueryLength = 2;

  final VietmapHttp _http;

  /// The API root, with any path prefix and query parameters.
  Uri get baseUrl => _http.baseUrl;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included.
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The suggestions for [query] (trimmed; up to 10, best first), with no
  /// position: [resolve] gives it.
  ///
  /// [near] is sent as `focus`, which ranks nearby places first. [session]
  /// is ignored. A query shorter than [minQueryLength] characters returns
  /// an empty list without a request.
  ///
  /// A suggestion's title is the place's name, else its address, else its
  /// full display; its subtitle is the rest of the display (the ward and
  /// city, say), or null when nothing is left.
  ///
  /// Throws [ArgumentError] for a [near] that is not finite, [StateError]
  /// after [close], and a [VietmapSearchException] when the request fails.
  @override
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    GeoPoint? near,
    PlaceSearchSession? session,
  }) async {
    _http.checkOpen();
    if (near != null) checkFinite(near, 'near');
    final text = query.trim();
    if (text.runes.length < minQueryLength) return const [];
    final json = await _get('autocomplete', [
      ('text', text),
      if (near != null) ('focus', '${fixed6(near.lat)},${fixed6(near.lng)}'),
    ]);
    return _guard('autocomplete', () {
      final items = _array(json);
      return [
        for (var i = 0; i < items.length; i++)
          _suggestion(items[i], 'autocomplete[$i]'),
      ];
    });
  }

  /// The place of [suggestion], from place v4: its position, its name (the
  /// place's name, else its address, else its display, else the
  /// suggestion's title) and its full display as the address.
  ///
  /// [session] is ignored. Throws [ArgumentError] for a suggestion without
  /// an id, [StateError] after [close], and a [VietmapSearchException] when
  /// the request fails.
  @override
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    PlaceSearchSession? session,
  }) async {
    _http.checkOpen();
    if (suggestion.id.isEmpty) {
      throw ArgumentError.value(suggestion, 'suggestion', 'has no id');
    }
    final json = await _get('place', [('refid', suggestion.id)]);
    return _guard('place', () {
      if (json is! Map<String, Object?>) {
        throw VietmapFormatException(
          'the answer is not a JSON object: got ${kindOf(json)}',
        );
      }
      return _place(json, 'place', id: suggestion.id, title: suggestion.title);
    });
  }

  /// The place nearest to [point], from reverse v4; null when Vietmap knows
  /// none there.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [VietmapSearchException] when the request fails.
  @override
  Future<Place?> reverse(GeoPoint point) async {
    _http.checkOpen();
    checkFinite(point, 'point');
    final json = await _get('reverse', [
      ('lat', fixed6(point.lat)),
      ('lng', fixed6(point.lng)),
    ]);
    return _guard('reverse', () {
      final items = _array(json);
      if (items.isEmpty) return null;
      final item = readMap(items.first, 'reverse[0]');
      final id = readOptionalString(item['ref_id'], 'reverse[0].ref_id');
      return _place(item, 'reverse[0]', id: id ?? '', title: '');
    });
  }

  /// Releases the HTTP client when the search created it; an injected
  /// client is left open. The search throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  /// The JSON of `{request}/v4`, its failures wrapped.
  Future<Object?> _get(String request, List<(String, String)> params) async {
    try {
      return await _http.get([request, 'v4'], params);
    } on Exception catch (e) {
      throw VietmapSearchException(request, e);
    }
  }

  /// The result of [parse], a [VietmapFormatException] wrapped.
  static T _guard<T>(String request, T Function() parse) {
    try {
      return parse();
    } on VietmapFormatException catch (e) {
      throw VietmapSearchException(request, e);
    }
  }

  static List<Object?> _array(Object? json) => json is List<Object?>
      ? json
      : throw VietmapFormatException(
          'the answer is not a JSON array: got ${kindOf(json)}',
        );

  static PlaceSuggestion _suggestion(Object? json, String path) {
    final item = readMap(json, path);
    final id = readString(item['ref_id'], '$path.ref_id');
    final (title, display) = _titleAndDisplay(item, path);
    final String? subtitle;
    if (display.isEmpty || display == title) {
      subtitle = null;
    } else if (display.startsWith('$title,')) {
      final rest = display.substring(title.length + 1).trim();
      subtitle = rest.isEmpty ? null : rest;
    } else {
      subtitle = display;
    }
    return PlaceSuggestion(id: id, title: title, subtitle: subtitle);
  }

  static Place _place(
    Map<String, Object?> item,
    String path, {
    required String id,
    required String title,
  }) {
    final lat = readNumber(item['lat'], '$path.lat');
    final lng = readNumber(item['lng'], '$path.lng');
    if (lat.abs() > 90) {
      throw VietmapFormatException('$path.lat: out of range ($lat)');
    }
    if (lng.abs() > 180) {
      throw VietmapFormatException('$path.lng: out of range ($lng)');
    }
    final (name, display) = _titleAndDisplay(item, path);
    return Place(
      id: id,
      name: name.isEmpty ? title : name,
      address: display.isEmpty ? null : display,
      position: GeoPoint(lat, lng),
    );
  }

  /// The name, else the address, else the display; and the display.
  static (String, String) _titleAndDisplay(
    Map<String, Object?> item,
    String path,
  ) {
    final name = readOptionalString(item['name'], '$path.name') ?? '';
    final address = readOptionalString(item['address'], '$path.address') ?? '';
    final display = readOptionalString(item['display'], '$path.display') ?? '';
    final title = name.isNotEmpty
        ? name
        : address.isNotEmpty
        ? address
        : display;
    return (title, display);
  }
}
