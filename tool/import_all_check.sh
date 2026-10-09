#!/usr/bin/env bash
# Checks that an app can import every package library of the workspace at
# once, without prefixes: a name exported by two libraries for different
# elements would be ambiguous and fail to analyze.
#
# It writes a throwaway app (path dependencies on all six packages) to a
# temporary directory, resolves it offline from the workspace's lock (run
# `flutter pub get` at the repo root first) and analyzes it; nothing is
# built.
# Usage: tool/import_all_check.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$(mktemp -d)"
trap 'rm -rf "$app"' EXIT

packages=(
  navigation_engine
  navigation_engine_flutter
  navigation_engine_flutter_map
  navigation_engine_google_maps
  navigation_engine_mapbox
  navigation_engine_maplibre
)

{
  echo 'name: import_all_check'
  echo 'publish_to: none'
  echo 'environment:'
  echo '  sdk: ^3.8.0'
  echo 'dependencies:'
  echo '  flutter:'
  echo '    sdk: flutter'
  for p in "${packages[@]}"; do
    echo "  $p: {path: $repo/packages/$p}"
  done
  # The adapters depend on the core packages by version: use the local ones.
  echo 'dependency_overrides:'
  for p in navigation_engine navigation_engine_flutter; do
    echo "  $p: {path: $repo/packages/$p}"
  done
} > "$app/pubspec.yaml"

mkdir -p "$app/lib"
{
  echo '// ignore_for_file: unused_element'
  for p in "${packages[@]}"; do
    echo "import 'package:$p/$p.dart';"
  done
  cat <<'DART'

// Each name in one library or re-exported unchanged by several; a clash
// fails the analysis.
final _names = <Object>[
  NavigationSession,
  GeoPoint,
  NavRoute,
  FollowCamera,
  NavigationFlowController,
  NavigationFlowScaffold,
  NavigationStrings,
  SpeedLimitSign,
  RouteColors,
  RouteLabelColors,
  CarPuck,
  VehicleImageBuilder,
  LaneGuidanceRow,
  MapboxStyleColors,
  MapboxStyleFlowScaffold,
  GoogleStyleColors,
  GoogleStyleFlowScaffold,
  GoogleStyleMapLayers,
  AlongRoutePlace,
  AudioGuidance,
  IncidentType,
  SearchPinsMap,
  SpeedLimitSignStyle,
  GoogleStyleNavigation,
  MapboxStyleNavigation,
  MapLibreStyleNavigation,
  NeutralNavigation,
  GoogleMapsNavigationMap,
  MapboxNavigationMap,
  MapLibreNavigationMap,
  FlutterMapNavigationMap,
  GoogleMapsNavigationView,
  MapboxNavigationView,
  MapLibreNavigationView,
  FlutterMapNavigationView,
  fitCameraToBounds,
  paintRouteLabel,
  laneDirectionIcon,
];
DART
} > "$app/lib/import_all.dart"

# The versions the workspace resolved and tests with: its lock, and only
# the pub cache that the workspace's own `pub get` filled.
cp "$repo/pubspec.lock" "$app/pubspec.lock"
cd "$app"
flutter pub get --offline > /dev/null
# Every package the check resolved has the workspace lock's version (the
# workspace's own packages are path dependencies here, not in that lock).
versions() {
  awk '/^  [a-z_0-9]+:$/ { name = $1 } /^    version:/ { print name, $2 }' "$1" |
    grep -v '^navigation_engine' | sort
}
drift="$(comm -13 <(versions "$repo/pubspec.lock") <(versions pubspec.lock))"
if [ -n "$drift" ]; then
  echo "Resolved versions that differ from the workspace lock:" >&2
  echo "$drift" >&2
  exit 1
fi
flutter analyze --no-pub lib
