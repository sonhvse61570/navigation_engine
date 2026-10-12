import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart';

import 'google_http.dart';
import 'google_routes_exception.dart';

/// Place search on Google's [Places API (New)](https://developers.google.com/maps/documentation/places/web-service/op-overview)
/// and [Geocoding API](https://developers.google.com/maps/documentation/geocoding/overview):
/// a [PlaceSearchProvider] for a destination search field.
///
/// - [autocomplete] calls `POST /v1/places:autocomplete`. Its suggestions
///   are place predictions, with a place id and **no position**; query
///   predictions are left out.
/// - [resolve] calls `GET /v1/places/{placeId}` with the field mask
///   [detailsFieldMask] (Place Details Essentials), for the chosen
///   suggestion's position; the place is named by the suggestion's title.
///   [fetchDisplayName] asks for Google's `displayName` too, a Pro field.
/// - [reverse] calls the Geocoding API's reverse geocoding,
///   `GET /maps/api/geocode/json?latlng=…`, the cheapest documented way
///   to name a point (see the README).
///
/// **Sessions.** Google bills Autocomplete per session: autocomplete
/// requests with the same `sessionToken`, ended by the Place Details
/// request that sends it. Pass the same [PlaceSearchSession] to every
/// [autocomplete] call of a search and to the [resolve] of the chosen
/// suggestion; then create a new session (Google bills a token used again
/// as no token). A call without a session sends no token, and is billed
/// per request.
///
/// Google Maps Platform's terms ask that these results be shown on a
/// Google map (see the README).
///
/// Failures throw a [GooglePlacesSearchException], a [PlaceSearchException]
/// whose `cause` is the [GoogleRoutesException] (or the `http` client's
/// error) that says why.
class GooglePlacesSearch implements PlaceSearchProvider {
  /// A search on [placesBaseUrl] (by default [defaultPlacesBaseUrl]) and,
  /// for [reverse], [geocodingBaseUrl] (by default
  /// [defaultGeocodingBaseUrl]).
  ///
  /// - [apiKey] is sent as the `X-Goog-Api-Key` header to the Places API,
  ///   and as the `key` query parameter to the Geocoding API (which takes
  ///   it there); pass null to send none, for a proxy that adds it.
  /// - [placesBaseUrl] and [geocodingBaseUrl] may carry a path prefix, to
  ///   which `v1/...` and `maps/api/geocode/json` are appended, and query
  ///   parameters, which are kept.
  /// - [proximity] biases the suggestions towards a position when
  ///   [autocomplete] is given no `near`, within [biasRadius] metres
  ///   (more than 0, at most 50 000; [defaultBiasRadius] by default).
  /// - [regionCodes] limits the suggestions to up to 15 regions: CLDR
  ///   two-letter codes such as `vn` (`includedRegionCodes`).
  /// - [languageCode] is the results' language, such as `vi`.
  /// - [fetchDisplayName] (false by default) makes [resolve] ask for the
  ///   place's `displayName` and name the place by it. `displayName` is a
  ///   Place Details Pro field, so [resolve] leaves the Essentials tier:
  ///   per Google's [session pricing](https://developers.google.com/maps/documentation/places/web-service/session-pricing),
  ///   a session it ends is billed at the SKU "Place Details Enterprise +
  ///   Atmosphere", whatever fields it asks for (see the README).
  ///   Without it, the place is named by the suggestion's title.
  /// - [headers] are added to every request, after the package's own,
  ///   which they may replace.
  /// - [timeout] bounds each request, the answer's body included.
  /// - [userAgent] is sent as the `User-Agent` header; null sends none. The
  ///   default is [defaultUserAgent], except on the web, where it is null
  ///   (no CORS preflight).
  /// - [client] makes the requests. When given, it stays the caller's to
  ///   close; when not, the search creates one and [close] closes it.
  ///
  /// Throws [ArgumentError] for a [biasRadius] outside (0, 50 000], more
  /// than 15 [regionCodes], or a [proximity] that is not finite.
  GooglePlacesSearch({
    required String? apiKey,
    Uri? placesBaseUrl,
    Uri? geocodingBaseUrl,
    this.proximity,
    this.biasRadius = defaultBiasRadius,
    List<String>? regionCodes,
    this.languageCode,
    this.fetchDisplayName = false,
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
    String? userAgent = googlePlatformUserAgent,
    http.Client? client,
  }) : placesBaseUrl = placesBaseUrl ?? googlePlacesApi,
       geocodingBaseUrl = geocodingBaseUrl ?? googleGeocodingApi,
       regionCodes = regionCodes == null
           ? null
           : List.unmodifiable(regionCodes),
       _http = _checked(
         biasRadius,
         regionCodes,
         proximity,
         () => GoogleHttp(
           owner: 'GooglePlacesSearch',
           apiKey: apiKey,
           headers: headers,
           timeout: timeout,
           userAgent: userAgent,
           client: client,
         ),
       );

  /// [connect]'s connection, once the options are checked: the check comes
  /// first, so a constructor that throws creates no client.
  static GoogleHttp _checked(
    double biasRadius,
    List<String>? regionCodes,
    GeoPoint? proximity,
    GoogleHttp Function() connect,
  ) {
    if (!(biasRadius > 0 && biasRadius <= 50000)) {
      throw ArgumentError.value(
        biasRadius,
        'biasRadius',
        'must be more than 0 and at most 50000',
      );
    }
    if (regionCodes != null && regionCodes.length > 15) {
      throw ArgumentError.value(
        regionCodes.length,
        'regionCodes',
        'at most 15 codes',
      );
    }
    if (proximity case final p?) checkFinite(p, 'proximity');
    return connect();
  }

  /// The Places API (New)'s root, `https://places.googleapis.com`.
  static final Uri defaultPlacesBaseUrl = googlePlacesApi;

  /// The Geocoding API's root, `https://maps.googleapis.com`.
  static final Uri defaultGeocodingBaseUrl = googleGeocodingApi;

  /// The default [timeout]: 12 seconds.
  static const Duration defaultTimeout = googleDefaultTimeout;

  /// The default [userAgent] off the web, which names this package.
  static const String defaultUserAgent = googleUserAgent;

  /// The default [biasRadius]: 20 km.
  static const double defaultBiasRadius = 20000;

  /// The field mask [resolve] sends as `X-Goog-FieldMask` by default:
  /// Place Details Essentials fields only (`id` is IDs Only), so the
  /// request, and the autocomplete session it ends, are billed at the
  /// Essentials rates.
  static const String detailsFieldMask = 'id,formattedAddress,location';

  /// The field mask [resolve] sends with [fetchDisplayName]. `displayName`
  /// is a Place Details Pro field; per Google's
  /// [session pricing](https://developers.google.com/maps/documentation/places/web-service/session-pricing),
  /// a session ended by a request with it is billed at the SKU "Place
  /// Details Enterprise + Atmosphere", whatever fields it asks for (see
  /// the README).
  static const String detailsFieldMaskWithDisplayName =
      'id,displayName,formattedAddress,location';

  /// Whether [resolve] asks for the place's `displayName` (a Pro field)
  /// and names the place by it, rather than by the suggestion's title.
  final bool fetchDisplayName;

  /// The Places API root, with any path prefix and query parameters.
  final Uri placesBaseUrl;

  /// The Geocoding API root, with any path prefix and query parameters.
  final Uri geocodingBaseUrl;

  /// The position suggestions are biased towards when [autocomplete] is
  /// given no `near`; null for none.
  final GeoPoint? proximity;

  /// The radius of the circle the suggestions are biased towards, in
  /// metres.
  final double biasRadius;

  /// The regions the suggestions are limited to (`includedRegionCodes`),
  /// or null.
  final List<String>? regionCodes;

  /// The results' language (`languageCode`, and `language` for the
  /// Geocoding API), or null for Google's default.
  final String? languageCode;

  final GoogleHttp _http;

  /// The headers added to every request.
  Map<String, String> get headers => _http.headers;

  /// How long a request may take, its body included.
  Duration get timeout => _http.timeout;

  /// The `User-Agent` header, or null to send none.
  String? get userAgent => _http.userAgent;

  /// The suggestions for [query] (trimmed), best first, with no position:
  /// [resolve] gives it.
  ///
  /// The body is `input`, then `sessionToken` ([session]'s token; none
  /// without a session), `languageCode`, `includedRegionCodes` and
  /// `locationBias.circle` around [near] (else [proximity]) with radius
  /// [biasRadius]. An empty query returns an empty list without a
  /// request.
  ///
  /// A suggestion's id is its `placeId`, its title its
  /// `structuredFormat.mainText` (else its `text`), and its subtitle its
  /// `structuredFormat.secondaryText`, or null when there is none. Query
  /// predictions (a query, not a place) are left out.
  ///
  /// Throws [ArgumentError] for a [near] that is not finite, [StateError]
  /// after [close], and a [GooglePlacesSearchException] when the request
  /// fails.
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
    final json = await _send(
      'autocomplete',
      'POST',
      placesBaseUrl,
      const ['v1', 'places:autocomplete'],
      body: {
        'input': text,
        'sessionToken': ?session?.token,
        'languageCode': ?languageCode,
        'includedRegionCodes': ?regionCodes,
        if (bias != null)
          'locationBias': {
            'circle': {
              'center': {'latitude': bias.lat, 'longitude': bias.lng},
              'radius': biasRadius,
            },
          },
      },
    );
    return _guard('autocomplete', () {
      final raw = json['suggestions'];
      // Google omits an empty list.
      final items = raw == null
          ? const <Object?>[]
          : readList(raw, 'suggestions');
      return [
        for (var i = 0; i < items.length; i++)
          ?_suggestion(items[i], 'suggestions[$i]'),
      ];
    });
  }

  /// The place of [suggestion], from `GET /v1/places/{placeId}` with the
  /// field mask [detailsFieldMask]: its `location`, its `formattedAddress`
  /// and its `id` (else the suggestion's id), named by the suggestion's
  /// title (else the address). With [fetchDisplayName], the mask is
  /// [detailsFieldMaskWithDisplayName] and the place is named by its
  /// `displayName` (else as without it).
  ///
  /// [session]'s token is sent as `sessionToken`, which ends the session
  /// for Google's billing; [languageCode] as `languageCode`.
  ///
  /// Throws [ArgumentError] for a suggestion without an id, [StateError]
  /// after [close], and a [GooglePlacesSearchException] when the request
  /// fails.
  @override
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    PlaceSearchSession? session,
  }) async {
    _http.checkOpen();
    if (suggestion.id.isEmpty) {
      throw ArgumentError.value(suggestion, 'suggestion', 'has no id');
    }
    final json = await _send(
      'place details',
      'GET',
      placesBaseUrl,
      ['v1', 'places', suggestion.id],
      params: [
        if (session != null) ('sessionToken', session.token),
        if (languageCode case final code?) ('languageCode', code),
      ],
      fieldMask: fetchDisplayName
          ? detailsFieldMaskWithDisplayName
          : detailsFieldMask,
    );
    return _guard('place details', () {
      final position = readPosition(json['location'], 'location');
      final id = readOptionalString(json['id'], 'id') ?? '';
      final display = fetchDisplayName
          ? readOptionalMap(json['displayName'], 'displayName')
          : null;
      final name =
          readOptionalString(display?['text'], 'displayName.text') ?? '';
      final address =
          readOptionalString(json['formattedAddress'], 'formattedAddress') ??
          '';
      return Place(
        id: id.isNotEmpty ? id : suggestion.id,
        name: name.isNotEmpty
            ? name
            : suggestion.title.isNotEmpty
            ? suggestion.title
            : address,
        address: address.isEmpty ? null : address,
        position: position,
      );
    });
  }

  /// The place at [point], from the Geocoding API
  /// (`latlng={lat},{lng}`, `key`, `language`): the first result, named
  /// by its `formatted_address`, with its `place_id` and its location;
  /// null for `ZERO_RESULTS`.
  ///
  /// Any other status but `OK` (`REQUEST_DENIED`, `OVER_QUERY_LIMIT`,
  /// `INVALID_REQUEST`, `UNKNOWN_ERROR`, …) is a
  /// [GoogleRoutesStatusException] cause, with Google's `error_message`.
  ///
  /// Throws [ArgumentError] for a point that is not finite, [StateError]
  /// after [close], and a [GooglePlacesSearchException] when the request
  /// fails.
  @override
  Future<Place?> reverse(GeoPoint point) async {
    _http.checkOpen();
    checkFinite(point, 'point');
    final json = await _send(
      'reverse geocoding',
      'GET',
      geocodingBaseUrl,
      const ['maps', 'api', 'geocode', 'json'],
      params: [
        ('latlng', '${coordinate(point.lat)},${coordinate(point.lng)}'),
        ..._http.keyParam,
        if (languageCode case final code?) ('language', code),
      ],
      keyInQuery: true,
    );
    return _guard('reverse geocoding', () {
      final status = readString(json['status'], 'status');
      if (status == 'ZERO_RESULTS') return null;
      if (status != 'OK') {
        throw GoogleRoutesStatusException(
          _http.scrubbed(status)!,
          serverMessage: switch (json['error_message']) {
            final String m => _http.scrubbed(m),
            _ => null,
          },
          statusCode: 200,
        );
      }
      final results = readList(json['results'], 'results');
      if (results.isEmpty) {
        throw const GoogleRoutesFormatException(
          'results: an OK answer with no results',
        );
      }
      final result = readMap(results.first, 'results[0]');
      final geometry = readMap(result['geometry'], 'results[0].geometry');
      final position = readPosition(
        geometry['location'],
        'results[0].geometry.location',
        latName: 'lat',
        lngName: 'lng',
      );
      final address =
          readOptionalString(
            result['formatted_address'],
            'results[0].formatted_address',
          ) ??
          '';
      return Place(
        id: readOptionalString(result['place_id'], 'results[0].place_id') ?? '',
        name: address,
        address: address.isEmpty ? null : address,
        position: position,
      );
    });
  }

  /// Releases the HTTP client when the search created it; an injected
  /// client is left open. The search throws [StateError] afterwards.
  /// Calling it again does nothing.
  void close() => _http.close();

  /// The JSON answer of [request], its failures wrapped.
  Future<Map<String, Object?>> _send(
    String request,
    String method,
    Uri base,
    List<String> path, {
    List<(String, String)> params = const [],
    Object? body,
    String? fieldMask,
    bool keyInQuery = false,
  }) async {
    try {
      return await _http.send(
        method,
        base,
        path,
        params: params,
        body: body,
        fieldMask: fieldMask,
        keyInQuery: keyInQuery,
      );
    } on Exception catch (e) {
      throw GooglePlacesSearchException(request, e);
    }
  }

  /// The result of [parse], a [GoogleRoutesStatusException] or
  /// [GoogleRoutesFormatException] wrapped. (The search's format messages
  /// name fields and JSON kinds, never a server string, so they need no
  /// scrub; a Geocoding status is scrubbed where it is read.)
  static T _guard<T>(String request, T Function() parse) {
    try {
      return parse();
    } on GoogleRoutesStatusException catch (e) {
      throw GooglePlacesSearchException(request, e);
    } on GoogleRoutesFormatException catch (e) {
      throw GooglePlacesSearchException(request, e);
    }
  }

  /// The place prediction at [path], or null for a query prediction.
  static PlaceSuggestion? _suggestion(Object? json, String path) {
    final item = readMap(json, path);
    final raw = item['placePrediction'];
    if (raw == null) return null;
    final at = '$path.placePrediction';
    final prediction = readMap(raw, at);
    final id = readString(prediction['placeId'], '$at.placeId');
    final text = readString(
      readMap(prediction['text'], '$at.text')['text'],
      '$at.text.text',
    );
    final format = readOptionalMap(
      prediction['structuredFormat'],
      '$at.structuredFormat',
    );
    String? part(String name) {
      final value = readOptionalMap(
        format?[name],
        '$at.structuredFormat.$name',
      );
      return readOptionalString(
        value?['text'],
        '$at.structuredFormat.$name.text',
      );
    }

    final main = part('mainText') ?? '';
    final secondary = part('secondaryText') ?? '';
    return PlaceSuggestion(
      id: id,
      title: main.isNotEmpty ? main : text,
      subtitle: secondary.isEmpty ? null : secondary,
    );
  }
}
