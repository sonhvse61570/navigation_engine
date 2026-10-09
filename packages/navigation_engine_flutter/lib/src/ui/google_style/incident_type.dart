import 'package:flutter/material.dart';

import '../navigation_strings.dart';

/// What a driver reports on the road.
enum IncidentType {
  /// A crash.
  crash,

  /// Slow traffic.
  slowdown,

  /// Police.
  police,

  /// Road works.
  construction,

  /// A closed lane.
  laneClosure,

  /// A stalled vehicle.
  stalledVehicle,

  /// An object on the road.
  objectOnRoad,

  /// A closed road.
  roadClosure,
}

/// The look of an [IncidentType] in the report sheet.
extension GoogleStyleIncidentType on IncidentType {
  /// The name of the incident in [strings].
  String label(NavigationStrings strings) => switch (this) {
    IncidentType.crash => strings.crash,
    IncidentType.slowdown => strings.slowdown,
    IncidentType.police => strings.police,
    IncidentType.construction => strings.construction,
    IncidentType.laneClosure => strings.laneClosure,
    IncidentType.stalledVehicle => strings.stalledVehicle,
    IncidentType.objectOnRoad => strings.objectOnRoad,
    IncidentType.roadClosure => strings.roadClosure,
  };

  /// The Material icon of the incident's tile.
  IconData get icon => switch (this) {
    IncidentType.crash => Icons.car_crash,
    IncidentType.slowdown => Icons.traffic,
    IncidentType.police => Icons.local_police,
    IncidentType.construction => Icons.construction,
    IncidentType.laneClosure => Icons.merge,
    IncidentType.stalledVehicle => Icons.car_repair,
    IncidentType.objectOnRoad => Icons.warning_amber,
    IncidentType.roadClosure => Icons.do_not_disturb_on,
  };

  /// The colour of the incident's round tile (the same by day and night).
  Color get tileColor => switch (this) {
    IncidentType.crash => const Color(0xFFD93025),
    IncidentType.slowdown => const Color(0xFFE37400),
    IncidentType.police => const Color(0xFF1A73E8),
    IncidentType.construction => const Color(0xFFF29900),
    IncidentType.laneClosure => const Color(0xFFB06000),
    IncidentType.stalledVehicle => const Color(0xFF5F6368),
    IncidentType.objectOnRoad => const Color(0xFF9334E6),
    IncidentType.roadClosure => const Color(0xFFA50E0E),
  };
}
