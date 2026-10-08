import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:navigation_engine/navigation_engine.dart';

const _tileSize = 256.0;
const _maxMercatorLat = 85.0511;

double _worldX(double lng) => (lng + 180) / 360;

double _worldY(double lat) {
  final phi = lat.clamp(-_maxMercatorLat, _maxMercatorLat) * math.pi / 180;
  final y = (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2;
  return y;
}

double _log2(double v) => math.log(v) / math.ln2;

/// The camera that shows all of [points] inside [viewport] minus [padding].
///
/// Uses a 256 dp Web Mercator world, as Google Maps does. The zoom is the
/// largest one that fits the bounds in the padded rectangle, clamped to
/// [minZoom]..[maxZoom] (a single point, or a degenerate bounds, gives
/// [maxZoom]). The centre is shifted so the bounds sit in the middle of the
/// padded rectangle, not of the whole view. Bearing and tilt are 0.
///
/// [mapPadding] is the padding the map widget itself has (`GoogleMap.padding`,
/// such as a navigation view's focus padding): the SDK puts the camera
/// target at the centre of [viewport] minus [mapPadding], so the target is
/// shifted to make the bounds centre show at the centre of [viewport] minus
/// [padding] all the same. The zoom does not depend on it. In world dp at
/// the fitted zoom, with y pointing down (south):
///
/// ```text
/// target = boundsCentre
///        + ((mapPadding.left - mapPadding.right) / 2,
///           (mapPadding.top - mapPadding.bottom) / 2)
///        - ((padding.left - padding.right) / 2,
///           (padding.top - padding.bottom) / 2)
/// ```
///
/// A padding larger than the viewport leaves a 1 dp rectangle, so the result
/// is the minimum zoom rather than an error. Throws [ArgumentError] when
/// [points] is empty.
///
/// Routes must not cross ±180° longitude.
CameraTarget fitCameraToBounds(
  List<GeoPoint> points,
  Size viewport,
  EdgeInsets padding, {
  double maxZoom = 18,
  double minZoom = 2,
  EdgeInsets mapPadding = EdgeInsets.zero,
}) {
  if (points.isEmpty) throw ArgumentError.value(points, 'points', 'is empty');
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in points) {
    final x = _worldX(p.lng);
    final y = _worldY(p.lat);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final dx = maxX - minX;
  final dy = maxY - minY;
  final w = math.max(1.0, viewport.width - padding.left - padding.right);
  final h = math.max(1.0, viewport.height - padding.top - padding.bottom);
  final zx = dx == 0 ? maxZoom : _log2(w / (_tileSize * dx));
  final zy = dy == 0 ? maxZoom : _log2(h / (_tileSize * dy));
  final zoom = math.min(zx, zy).clamp(minZoom, maxZoom).toDouble();

  final world = _tileSize * math.pow(2, zoom);
  final cx =
      (minX + maxX) / 2 * world +
      (mapPadding.left - mapPadding.right) / 2 -
      (padding.left - padding.right) / 2;
  final cy =
      (minY + maxY) / 2 * world +
      (mapPadding.top - mapPadding.bottom) / 2 -
      (padding.top - padding.bottom) / 2;
  final lng = cx / world * 360 - 180;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * cy / world))) * 180 / math.pi;
  return CameraTarget(
    position: GeoPoint(lat, lng),
    bearing: 0,
    zoom: zoom,
    tilt: 0,
  );
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;
