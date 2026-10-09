import 'package:navigation_engine/navigation_engine.dart';

/// The name of the last named road on [route], or null if no step has one.
///
/// Shared by the arrival sheet and the drop-in, which use it as the
/// destination's name when no label is known.
String? lastRoadName(NavRoute route) => route.steps
    .map((step) => step.roadName)
    .where((name) => name.isNotEmpty)
    .lastOrNull;
