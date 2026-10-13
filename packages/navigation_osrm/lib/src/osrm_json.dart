import 'package:navigation_engine/navigation_engine.dart';

import 'osrm_exception.dart';

// Typed reads of OSRM's JSON that name the field when it is not what OSRM
// sends. Internal: not exported by the package.

/// What [json] is, in words: `an object`, `a string`, `null`, ...
String jsonKind(Object? json) => switch (json) {
  Map<Object?, Object?>() => 'an object',
  List<Object?>() => 'an array',
  String() => 'a string',
  num() => 'a number',
  bool() => 'a boolean',
  null => 'null',
  _ => 'a ${json.runtimeType}',
};

/// [json] as an object, else an [OsrmFormatException] naming [path].
Map<String, Object?> jsonMap(Object? json, String path) =>
    json is Map<String, Object?>
    ? json
    : throw OsrmFormatException(
        '$path: expected an object, got ${jsonKind(json)}',
      );

/// [json] as an array, else an [OsrmFormatException] naming [path].
List<Object?> jsonList(Object? json, String path) => json is List<Object?>
    ? json
    : throw OsrmFormatException(
        '$path: expected an array, got ${jsonKind(json)}',
      );

/// [json] as a number, else an [OsrmFormatException] naming [path].
double jsonNumber(Object? json, String path) => json is num
    ? json.toDouble()
    : throw OsrmFormatException(
        '$path: expected a number, got ${jsonKind(json)}',
      );

/// [json] as a string, else an [OsrmFormatException] naming [path].
String jsonString(Object? json, String path) => json is String
    ? json
    : throw OsrmFormatException(
        '$path: expected a string, got ${jsonKind(json)}',
      );

/// [json] as a string, or null when it is null.
String? jsonOptionalString(Object? json, String path) =>
    json == null ? null : jsonString(json, path);

/// A `[longitude, latitude]` pair as a [GeoPoint].
GeoPoint jsonLngLat(Object? json, String path) {
  final pair = jsonList(json, path);
  if (pair.length < 2) {
    throw OsrmFormatException('$path: expected [longitude, latitude]');
  }
  return GeoPoint(
    jsonNumber(pair[1], '$path[1]'),
    jsonNumber(pair[0], '$path[0]'),
  );
}
