import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'mapbox_directions_exception.dart';
import 'mapbox_http.dart';

/// Place search on Mapbox's [Search Box API](https://docs.mapbox.com/api/search/search-box/):
/// a [PlaceSearchProvider] for a destination search field.
///
/// - [autocomplete] calls `/search/searchbox/v1/suggest`. Its suggestions
///   have a `mapbox_id` and **no position**.
/// - [resolve] calls `/search/searchbox/v1/retrieve/{mapbox_id}` for the
///   chosen suggestion's position.
/// - [reverse] calls `/search/searchbox/v1/reverse`.
///
/// **Sessions.** Mapbox bills `/suggest` and `/retrieve` per session: any
/// number of `/suggest` calls (up to 50) then one `/retrieve`, with the
/// same `session_token`, are one session. Pass the same
/// [PlaceSearchSession] to every [autocomplete] call of a search and to
/// the [resolve] of the chosen suggestion: its token is sent as
/// `session_token`. Mapbox requires a token on both, so a call without a
/// session gets a fresh token of its own, and is billed as a session of
/// its own. [reverse] is billed per request and takes no session.
///
/// It takes the same options as `MapboxDirectionsRouteProvider`, and its
/// own [proximity], [country], [language] and [limit].
///
/// Failures throw a [MapboxSearchException], a [PlaceSearchException]
/// whose `cause` is the [MapboxDirectionsException] (or the `http`
/// client's error) that says why.
class MapboxSearch implements PlaceSearchProvider {
  /// A search on [baseUrl] (by default [defaultBaseUrl]).
  ///
  /// - [accessToken] is sent as the `access_token` query parameter; pass
  ///   null to send none, for a proxy that adds it.
  /// - [baseUrl] may carry a path prefix, to which `search/searchbox/v1/...`
  ///   is appended, and query parameters, which are kept.
  /// - [proximity] biases the suggestions towards a position when
  ///   [autocomplete] is given no `near`.
  /// - [country] limits the results to countries: ISO 3166 alpha-2 codes,
  ///   comma-separated, such as `vn` or `vn,la`.
  /// - [language] is the results' language, an ISO 639-1 code such as
  ///   `vi`.
  /// - [limit] is the most suggestions [autocomplete] asks for, 1 to 10
  ///   (Mapbox's default when null).
  /// - [headers] are added to every request, after `Accept` and
  ///   `User-Agent`, which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none. The
  ///   default is [defaultUserAgent], except on the web, where it is null
  ///   (no CORS preflight).
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the search creates one and [close] closes it.
  ///
  /// Throws [ArgumentError] for a [limit] outside 1 to 10, or a
  /// [proximity] that is not finite.
  MapboxSearch({
    required String? accessToken,
    Uri? baseUrl,
    this.proximity,
    this.country,
    this.language,
    this.limit,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = mapboxPlatformUserAgent,
    http.Client? client,
  }) : _http = _checked(
         limit,
         proximity,
         () => MapboxHttp(
           owner: 'MapboxSearch',
           accessToken: accessToken,
           baseUrl: baseUrl,
           headers: headers,
           timeout: timeout,
           userAgent: userAgent,
           client: client,
         ),
       );

  /// [connect]'s connection, once [limit] and [proximity] are checked: the
  /// check comes first, so a constructor that throws creates no client.
  static MapboxHttp _checked(
    int? limit,
    GeoPoint? proximity,
    MapboxHttp Function() connect,
  ) {
    if (limit case final limit? when limit < 1 || limit > 10) {
      throw ArgumentError.value(limit, 'limit', 'must be 1 to 10');
    }
    if (proximity case final p?) checkFinite(p, 'proximity');
    return connect();
  }

  /// Mapbox's API root, `https://api.mapbox.com`.
  static final Uri defaultBaseUrl = mapboxApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = mapboxDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = mapboxUserAgent;

  /// The `feature_type`s of suggestions that are not one place (a
  /// category, such as "park"): [autocomplete] leaves them out, since
  /// [resolve] could not give them a position.
  static const Set<String> notPlaces = {'category'};

  /// The position suggestions are biased towards when [autocomplete] is
  /// given no `near`; null for none.
  final GeoPoint? proximity;

  /// The countries the results are limited to (`country=`), or null.
  final String? country;

  /// The results' language (`language=`), or null for Mapbox's default.
  final String? language;

  /// The most suggestions [autocomplete] asks for (`limit=`), or null for
  /// Mapbox's default.
  final int? limit;

  final MapboxHttp _http;

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
  /// [near] (else [proximity]) is sent as `proximity`, `lon,lat`, which
  /// ranks nearby places first. [session]'s token is sent as
  /// `session_token`; without a session, a fresh token. An empty query
  /// returns an empty list without a request.
  ///
  /// A suggestion's id is its `mapbox_id`, its title its `name`, and its
  /// subtitle its `place_formatted`, or null when that is empty.
  /// Category suggestions ([notPlaces]) are left out.
  ///
  /// Throws [ArgumentError] for a [near] that is not finite, [StateError]
  /// after [close], and a [MapboxSearchException] when the request fails.
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
    final bias = near ?? proximity;
    final json = await _get(
      'suggest',
      ['suggest'],
      [
        ('q', text),
        ('session_token', _token(session)),
        if (bias != null) ('proximity', lonLat(bias)),
        ..._options,
        if (limit case final limit?) ('limit', '$limit'),
      ],
    );
    return _guard('suggest', () {
      final items = readList(json['suggestions'], 'suggestions');
      return [
        for (var i = 0; i < items.length; i++)
          ?_suggestion(items[i], 'suggestions[$i]'),
      ];
    });
  }

  /// The place of [suggestion], from `/retrieve/{mapbox_id}`: its
  /// position (the feature's point), its name (else the suggestion's
  /// title), its `full_address` (else its `place_formatted`) and its
  /// `mapbox_id` (else the suggestion's id).
  ///
  /// [session]'s token is sent as `session_token`, which ends the session
  /// for Mapbox's billing; without a session, a fresh token.
  ///
  /// Throws [ArgumentError] for a suggestion without an id, [StateError]
  /// after [close], and a [MapboxSearchException] when the request fails
  /// or Mapbox sends no feature.
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
      'retrieve',
      ['retrieve', suggestion.id],
      [
        ('session_token', _token(session)),
        if (language case final language?) ('language', language),
      ],
    );
    return _guard('retrieve', () {
      final features = readList(json['features'], 'features');
      if (features.isEmpty) {
        throw const MapboxDirectionsFormatException(
          'features: no feature for the id',
        );
      }
      return _place(features.first, 'features[0]', fallback: suggestion);
    });
  }

  /// The place at [point], from `/reverse` (`longitude`, `latitude`, and
  /// `limit=1`): the first feature Mapbox returns, named by its `name`
  /// (else its address); null when there is none.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [MapboxSearchException] when the request fails.
  @override
  Future<Place?> reverse(GeoPoint point) async {
    _http.checkOpen();
    checkFinite(point, 'point');
    final json = await _get(
      'reverse',
      ['reverse'],
      [
        ('longitude', coordinate(point.lng)),
        ('latitude', coordinate(point.lat)),
        ..._options,
        ('limit', '1'),
      ],
    );
    return _guard('reverse', () {
      final features = readList(json['features'], 'features');
      if (features.isEmpty) return null;
      return _place(features.first, 'features[0]');
    });
  }

  /// Releases the HTTP client when the search created it; an injected
  /// client is left open. The search throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  /// `country` and `language`, when set.
  List<(String, String)> get _options => [
    if (country case final country?) ('country', country),
    if (language case final language?) ('language', language),
  ];

  /// [session]'s token, or a fresh one: Mapbox requires one.
  static String _token(PlaceSearchSession? session) =>
      (session ?? PlaceSearchSession()).token;

  /// The JSON of `search/searchbox/v1/{path}`, its failures wrapped.
  Future<Map<String, Object?>> _get(
    String request,
    List<String> path,
    List<(String, String)> params,
  ) async {
    try {
      return await _http.get(['search', 'searchbox', 'v1', ...path], params);
    } on Exception catch (e) {
      throw MapboxSearchException(request, e);
    }
  }

  /// The result of [parse], a [MapboxDirectionsFormatException] wrapped.
  static T _guard<T>(String request, T Function() parse) {
    try {
      return parse();
    } on MapboxDirectionsFormatException catch (e) {
      throw MapboxSearchException(request, e);
    }
  }

  /// The suggestion at [path], or null for one that is not a place.
  static PlaceSuggestion? _suggestion(Object? json, String path) {
    final item = readMap(json, path);
    final type = readOptionalString(item['feature_type'], '$path.feature_type');
    if (notPlaces.contains(type)) return null;
    final id = readString(item['mapbox_id'], '$path.mapbox_id');
    final name = readString(item['name'], '$path.name');
    final formatted =
        readOptionalString(item['place_formatted'], '$path.place_formatted') ??
        '';
    return PlaceSuggestion(
      id: id,
      title: name,
      subtitle: formatted.isEmpty ? null : formatted,
    );
  }

  /// The GeoJSON feature at [path] as a [Place], the [fallback]
  /// suggestion's id and title filling in what it lacks.
  static Place _place(Object? json, String path, {PlaceSuggestion? fallback}) {
    final feature = readMap(json, path);
    final geometry = readMap(feature['geometry'], '$path.geometry');
    final position = readLngLat(
      geometry['coordinates'],
      '$path.geometry.coordinates',
    );
    final rawProperties = feature['properties'];
    final properties = rawProperties == null
        ? const <String, Object?>{}
        : readMap(rawProperties, '$path.properties');
    String text(String name) =>
        readOptionalString(properties[name], '$path.properties.$name') ?? '';
    final id = text('mapbox_id');
    final name = text('name');
    final full = text('full_address');
    final formatted = text('place_formatted');
    final address = full.isNotEmpty ? full : formatted;
    return Place(
      id: id.isNotEmpty ? id : fallback?.id ?? '',
      name: name.isNotEmpty
          ? name
          : fallback != null
          ? fallback.title
          : address,
      address: address.isEmpty ? null : address,
      position: position,
    );
  }
}
