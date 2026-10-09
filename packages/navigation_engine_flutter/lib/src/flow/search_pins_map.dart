import '../along_route_search.dart';

/// A map that can pin the places found along the route. Map adapters
/// implement it; a screen that searches along the route calls it when the
/// session's map is one, and works without it. The map styles the pins
/// itself. An error a call throws, or a future that fails, is reported
/// through `FlutterError` by the caller and does not break the screen; an
/// adapter should still report its own failures and complete normally.
abstract interface class SearchPinsMap {
  /// Pins [places] on the map, the one with [focusedId] larger and on top; a
  /// tap on a pin calls [onTap] with its place. A newer call replaces the
  /// pins shown. The returned future completes once the pins are drawn, or
  /// were dropped by a newer call or [clearSearchPins].
  Future<void> showSearchPins(
    List<AlongRoutePlace> places, {
    String? focusedId,
    void Function(AlongRoutePlace place)? onTap,
  });

  /// Removes what [showSearchPins] drew, also pins still being drawn.
  void clearSearchPins();
}
