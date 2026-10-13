import 'package:navigation_engine/navigation_engine.dart';

import 'osrm_exception.dart';
import 'osrm_geometries.dart';
import 'osrm_json.dart';

/// Turns the JSON of an answer of OSRM's route service into [NavRoute]s.
///
/// `OsrmRouteProvider` reads every answer with it. A provider whose
/// answers follow OSRM's format, such as Mapbox's Directions API, can
/// reuse it, so that its steps, manoeuvres, lanes, durations and speed
/// limits read exactly as OSRM's do:
///
/// ```dart
/// final json = jsonDecode(response.body) as Map<String, Object?>;
/// if (json['code'] != 'Ok') throw MyCodeException(json['code']);
/// final routes = OsrmResponseParser.parse(
///   json,
///   geometries: OsrmGeometries.polyline6,
///   speedLimits: true,
///   providerName: 'Mapbox',
/// );
/// ```
abstract final class OsrmResponseParser {
  /// The routes of [json], an answer of the route service whose `code` is
  /// `Ok`: the best route first, then the alternatives, in the answer's
  /// order. At most [maxAlternatives] alternatives are kept (all of them
  /// when it is null).
  ///
  /// It reads only `routes`: the caller checks `code` first, since what an
  /// error code means depends on the HTTP status. For each route:
  ///
  /// - `geometry` is the route's points, in the form [geometries] says
  ///   (GeoJSON, or a precision-6 polyline);
  /// - each step of each leg becomes a [RouteStep] placed at its
  ///   `maneuver.location`, with its manoeuvre type and modifier (a type
  ///   it does not know is a turn, as OSRM asks), its road name (`name`,
  ///   falling back to `ref`) and the lanes of its first intersection;
  /// - each leg's `annotation.duration` gives the per-segment durations,
  ///   scaled so that the leg sums to its `duration` (the annotations
  ///   leave out the time of the turns);
  /// - when [speedLimits] is true, each leg's `annotation.maxspeed` gives
  ///   the per-segment speed limits: `{speed, unit}` in km/h or mph, with
  ///   `{unknown: true}`, `{none: true}` and speeds that are not positive
  ///   as no limit;
  /// - the legs' `summary` values, joined, are the route's summary, and
  ///   its name is [providerName] then its `distance`, such as
  ///   `OSRM 2192 m`.
  ///
  /// Durations or speed limits whose count does not match the route's
  /// segments are left out. Fields it does not know, such as Mapbox's
  /// `voiceInstructions` and `bannerInstructions`, are ignored.
  ///
  /// Throws [OsrmFormatException], whose message names the field, for
  /// JSON of an unexpected shape or with no routes, and [ArgumentError]
  /// when [maxAlternatives] is negative.
  static List<NavRoute> parse(
    Map<String, Object?> json, {
    OsrmGeometries geometries = OsrmGeometries.geojson,
    bool speedLimits = false,
    int? maxAlternatives,
    String providerName = 'OSRM',
  }) {
    if (maxAlternatives != null && maxAlternatives < 0) {
      throw ArgumentError.value(maxAlternatives, 'maxAlternatives', 'is < 0');
    }
    final routes = jsonList(json['routes'], 'routes');
    if (routes.isEmpty) {
      throw const OsrmFormatException('routes: an Ok answer with no routes');
    }
    return [
      for (
        var i = 0;
        i < routes.length && (maxAlternatives == null || i <= maxAlternatives);
        i++
      )
        _route(
          routes[i],
          'routes[$i]',
          geometries: geometries,
          speedLimits: speedLimits,
          providerName: providerName,
        ),
    ];
  }

  static NavRoute _route(
    Object? json,
    String path, {
    required OsrmGeometries geometries,
    required bool speedLimits,
    required String providerName,
  }) {
    final route = jsonMap(json, path);
    final points = _points(route['geometry'], '$path.geometry', geometries);
    final legs = jsonList(route['legs'], '$path.legs');
    final seeds = <RouteStepSeed>[];
    final summaries = <String>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = jsonMap(legs[l], legPath);
      final steps = jsonList(leg['steps'], '$legPath.steps');
      for (var s = 0; s < steps.length; s++) {
        seeds.add(_seed(steps[s], '$legPath.steps[$s]'));
      }
      final summary = jsonOptionalString(leg['summary'], '$legPath.summary');
      if (summary != null && summary.isNotEmpty) summaries.add(summary);
    }
    final durations = _durations(legs, path);
    final limits = speedLimits ? _speedLimits(legs, path) : null;
    final distance = jsonNumber(route['distance'], '$path.distance');
    try {
      return NavRoute.fromPoints(
        points,
        steps: seeds,
        name: '$providerName ${distance.round()} m',
        summary: summaries.isEmpty ? null : summaries.join(', '),
        segmentDurations: durations?.length == points.length - 1
            ? durations
            : null,
        segmentSpeedLimits: limits?.length == points.length - 1 ? limits : null,
      );
    } on ArgumentError catch (e) {
      throw OsrmFormatException('$path: ${e.message} (${e.name})');
    }
  }

  static List<GeoPoint> _points(
    Object? json,
    String path,
    OsrmGeometries geometries,
  ) {
    final List<GeoPoint> points;
    switch (geometries) {
      case OsrmGeometries.geojson:
        final coordinates = jsonList(
          jsonMap(json, path)['coordinates'],
          '$path.coordinates',
        );
        points = [
          for (var i = 0; i < coordinates.length; i++)
            jsonLngLat(coordinates[i], '$path.coordinates[$i]'),
        ];
      case OsrmGeometries.polyline6:
        if (json is! String) {
          throw OsrmFormatException('$path: expected a polyline6 string');
        }
        try {
          points = decodePolyline(json, precision: 6);
        } on FormatException catch (e) {
          throw OsrmFormatException('$path: ${e.message}');
        }
    }
    if (points.length < 2) {
      throw OsrmFormatException(
        '$path: ${points.length} point(s), a route needs at least 2',
      );
    }
    return points;
  }

  static RouteStepSeed _seed(Object? json, String path) {
    final step = jsonMap(json, path);
    final maneuver = jsonMap(step['maneuver'], '$path.maneuver');
    final type = jsonString(maneuver['type'], '$path.maneuver.type');
    final modifier = jsonOptionalString(
      maneuver['modifier'],
      '$path.maneuver.modifier',
    );
    final name = jsonOptionalString(step['name'], '$path.name') ?? '';
    final ref = jsonOptionalString(step['ref'], '$path.ref') ?? '';
    return RouteStepSeed.atLocation(
      jsonLngLat(maneuver['location'], '$path.maneuver.location'),
      type: _type(type),
      modifier: _modifier(modifier),
      roadName: name.isNotEmpty ? name : ref,
      lanes: _lanes(step['intersections'], '$path.intersections', modifier),
    );
  }

  /// Each leg's `annotation.duration`, scaled so that the leg sums to its
  /// `duration`: the annotations leave out the time of the turns. Null
  /// when a leg has none, or when they sum to 0 for a leg that takes time.
  static List<double>? _durations(List<Object?> legs, String path) {
    final out = <double>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final leg = jsonMap(legs[l], legPath);
      final annotation = leg['annotation'];
      if (annotation == null) return null;
      final raw = jsonMap(annotation, '$legPath.annotation')['duration'];
      if (raw == null) return null;
      final list = jsonList(raw, '$legPath.annotation.duration');
      final values = <double>[];
      for (var i = 0; i < list.length; i++) {
        final d = jsonNumber(list[i], '$legPath.annotation.duration[$i]');
        if (d < 0) {
          throw OsrmFormatException(
            '$legPath.annotation.duration[$i]: negative ($d)',
          );
        }
        values.add(d);
      }
      final total = jsonNumber(leg['duration'], '$legPath.duration');
      final sum = values.fold(0.0, (a, b) => a + b);
      if (sum == 0) {
        if (total > 0) return null;
        out.addAll(values);
        continue;
      }
      out.addAll(values.map((d) => d * total / sum));
    }
    return out;
  }

  /// Each leg's `annotation.maxspeed` in m/s: `{speed, unit}` in km/h or
  /// mph; `{unknown: true}`, `{none: true}` and speeds that are not
  /// positive are no limit (null). Null when a leg has none.
  static List<double?>? _speedLimits(List<Object?> legs, String path) {
    final out = <double?>[];
    for (var l = 0; l < legs.length; l++) {
      final legPath = '$path.legs[$l]';
      final annotation = jsonMap(legs[l], legPath)['annotation'];
      if (annotation == null) return null;
      final raw = jsonMap(annotation, '$legPath.annotation')['maxspeed'];
      if (raw == null) return null;
      final list = jsonList(raw, '$legPath.annotation.maxspeed');
      for (var i = 0; i < list.length; i++) {
        final entryPath = '$legPath.annotation.maxspeed[$i]';
        final entry = jsonMap(list[i], entryPath);
        if (entry['speed'] == null) {
          out.add(null);
          continue;
        }
        final speed = jsonNumber(entry['speed'], '$entryPath.speed');
        final unit = jsonOptionalString(entry['unit'], '$entryPath.unit');
        out.add(switch (unit) {
          _ when !(speed > 0) => null,
          'mph' => speed * 0.44704,
          _ => speed / 3.6,
        });
      }
    }
    return out;
  }

  /// The lanes of the step's first intersection, where its manoeuvre is.
  static List<Lane> _lanes(Object? json, String path, String? modifier) {
    if (json == null) return const [];
    final intersections = jsonList(json, path);
    if (intersections.isEmpty) return const [];
    final raw = jsonMap(intersections.first, '$path[0]')['lanes'];
    if (raw == null) return const [];
    final lanes = jsonList(raw, '$path[0].lanes');
    final follow = _laneDirection(modifier);
    return [
      for (var i = 0; i < lanes.length; i++)
        _lane(lanes[i], '$path[0].lanes[$i]', follow),
    ];
  }

  static Lane _lane(Object? json, String path, LaneDirection? follow) {
    final lane = jsonMap(json, path);
    final indications = lane['indications'] == null
        ? const <Object?>[]
        : jsonList(lane['indications'], '$path.indications');
    final directions = <LaneDirection>{
      for (var i = 0; i < indications.length; i++)
        ?_laneDirection(jsonString(indications[i], '$path.indications[$i]')),
    };
    // `none` (or nothing): no arrow painted, which drivers read as straight.
    if (directions.isEmpty) directions.add(LaneDirection.straight);
    final valid = lane['valid'] == true;
    final given = _laneDirection(
      jsonOptionalString(lane['valid_indication'], '$path.valid_indication'),
    );
    final active = !valid
        ? null
        : given ??
              (follow != null && directions.contains(follow)
                  ? follow
                  : directions.first);
    return Lane(directions: directions, valid: valid, active: active);
  }

  static LaneDirection? _laneDirection(String? s) => switch (s) {
    'uturn' => LaneDirection.uturn,
    'sharp right' => LaneDirection.sharpRight,
    'right' => LaneDirection.right,
    'slight right' => LaneDirection.slightRight,
    'straight' => LaneDirection.straight,
    'slight left' => LaneDirection.slightLeft,
    'left' => LaneDirection.left,
    'sharp left' => LaneDirection.sharpLeft,
    _ => null,
  };

  /// OSRM's `maneuver.type`. OSRM asks clients to handle a type they do not
  /// know like `turn`.
  static ManeuverType _type(String t) => switch (t) {
    'depart' => ManeuverType.depart,
    'arrive' => ManeuverType.arrive,
    'new name' => ManeuverType.newName,
    'continue' || 'notification' || 'use lane' => ManeuverType.continueOn,
    'merge' => ManeuverType.merge,
    'on ramp' => ManeuverType.onRamp,
    'off ramp' => ManeuverType.offRamp,
    'fork' => ManeuverType.fork,
    'end of road' => ManeuverType.endOfRoad,
    'roundabout' || 'rotary' => ManeuverType.roundabout,
    'exit roundabout' || 'exit rotary' => ManeuverType.exitRoundabout,
    // `roundabout turn`: a small roundabout driven like an intersection.
    _ => ManeuverType.turn,
  };

  static ManeuverModifier _modifier(String? m) => switch (m) {
    'uturn' => ManeuverModifier.uturn,
    'sharp right' => ManeuverModifier.sharpRight,
    'right' => ManeuverModifier.right,
    'slight right' => ManeuverModifier.slightRight,
    'straight' => ManeuverModifier.straight,
    'slight left' => ManeuverModifier.slightLeft,
    'left' => ManeuverModifier.left,
    'sharp left' => ManeuverModifier.sharpLeft,
    _ => ManeuverModifier.none,
  };
}
