import 'alternate_route.dart';

/// A map that can draw alternate routes while navigating. Map adapters
/// implement it; a `NavigationFlowController` calls it when the session's
/// map is one, and works without it. The map styles the lines and their
/// labels itself.
abstract interface class AlternateRoutesMap {
  /// Draws [alternates] under the current route, each with a label; a tap
  /// on one calls [onTap] with its index. The bundled adapters draw each
  /// line from [alternateLinePoints] (the alternate's own part, so a tap on
  /// the current route where the two share the road is a map tap), and
  /// treat an empty list as [clearAlternates].
  void showAlternates(
    List<AlternateRoute> alternates, {
    required void Function(int index) onTap,
  });

  /// Removes what [showAlternates] drew.
  void clearAlternates();
}
