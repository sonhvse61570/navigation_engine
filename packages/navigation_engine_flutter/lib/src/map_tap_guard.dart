import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Keeps the map tap of a gesture away from the app when a feature the map
/// adapter draws (a route option, an alternate, a bubble, a pin) took the
/// tap: a platform may report a map tap too for that gesture, before or
/// after the feature tap.
///
/// The adapter calls [featureTapped] from each tap on its own features and
/// passes every map tap to [dispatch]. A feature tap leaves a one-shot token
/// that the next map tap spends (it is dropped); the token lapses at the end
/// of the frame. A map tap is held for one turn of the event loop, and a
/// feature tap in that turn drops it. No wall clock is involved.
///
/// The map adapters of this family use it for their views' `onMapTap`; a
/// map adapter of an app's own, or an app that draws tappable features on
/// an SDK map itself, can use it the same way:
///
/// ```dart
/// final guard = MapTapGuard();
/// // From each tap on a feature you draw:
/// guard.featureTapped();
/// // From the SDK's map tap:
/// guard.dispatch(() => onMapTap(point));
/// // When the map goes:
/// guard.dispose();
/// ```
class MapTapGuard {
  // The one-shot token a feature tap leaves for the map tap of the same
  // gesture; it lapses at the end of the frame.
  bool _token = false;

  // A map tap held for one turn of the event loop, in case the feature tap
  // of its gesture follows it; null when none is held.
  _HeldTap? _held;

  bool _disposed = false;

  /// A tap on a feature the map draws: it drops the map tap of its gesture,
  /// held or to come (in the same frame).
  void featureTapped() {
    if (_disposed) return;
    final held = _held;
    if (held != null) {
      held.cancelled = true;
      _held = null;
      return;
    }
    _token = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _token = false)
      ..ensureVisualUpdate();
  }

  /// Delivers a tap on the map itself through [deliver], unless it belongs
  /// to a tap on a feature the map draws: one that came before it in the
  /// same frame ([featureTapped]), or one that comes in the same turn of the
  /// event loop. [deliver] runs after that turn, and not at all once the
  /// guard is disposed.
  void dispatch(VoidCallback deliver) {
    if (_disposed) return;
    if (_token) {
      _token = false;
      return;
    }
    final held = _HeldTap();
    _held = held;
    Timer.run(() {
      if (identical(_held, held)) _held = null;
      if (!held.cancelled && !_disposed) deliver();
    });
  }

  /// Drops a held map tap and the token; later calls do nothing.
  void dispose() {
    _disposed = true;
    _held?.cancelled = true;
    _held = null;
    _token = false;
  }
}

/// A map tap waiting for its turn of the event loop.
class _HeldTap {
  bool cancelled = false;
}
