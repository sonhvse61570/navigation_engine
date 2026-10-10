import 'package:navigation_engine/navigation_engine.dart';

/// A map that can pin a trip's destination. Map adapters implement it,
/// drawing the shared red marker of `paintDestinationPin`; a navigation
/// screen calls it when the session's map is one, and works without it.
///
/// The styled scaffolds (through `NavigationFlowScaffold`) pin the end of
/// the selected route while the flow is in the overview, navigating or
/// arrived, move the pin when the selection, an alternate or a reroute
/// changes the route, and remove it when the flow goes back to idle and
/// while a request loads or has failed. While the flow shows no pin of its
/// own the app may pin a place itself (such as one the user long-pressed);
/// the flow's pin replaces it once the overview shows.
/// An error a call throws is reported through `FlutterError` by the caller
/// and does not break the screen.
abstract interface class DestinationPinMap {
  /// Shows the destination pin at [point], replacing the one shown; null
  /// removes it.
  void showDestinationPin(GeoPoint? point);
}
