import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'car_puck.dart';
import 'focus_padding.dart';
import 'vehicle_marker_map.dart';

/// Builds the map widget of a map SDK. [focusPadding] is the padding that
/// puts the camera centre at the frame's focus point; apply it the way the
/// SDK expects (widget padding, camera padding, …).
typedef NavigationMapBuilder =
    Widget Function(BuildContext context, EdgeInsets focusPadding);

/// The map-independent part of a navigation view: drives a
/// [NavigationSession] once per frame, draws the vehicle [puck] fixed at the
/// focus point while the camera follows, stops following when the user
/// touches the map and offers a recenter button.
///
/// The [puck] is drawn pointing up and turned by the vehicle's bearing
/// minus the camera's: not at all while the camera is heading up (the map
/// turns instead), and by the vehicle's bearing while it is north up
/// ([FollowCamera.headingUp] false). A switch shows on the next frame.
///
/// The app owns the session: it creates, starts and disposes it. The frame
/// only ticks it, toggles [NavigationSession.follow], and pauses / resumes
/// it when the app goes to the background.
///
/// ## How the session is driven
///
/// The frame ticks the session only while it is on screen. A full-screen
/// route pushed on top mutes it: no guidance and no reroute until the user
/// returns. Show a session in one view at a time; two frames on one session
/// tick it twice. To keep guidance running off-screen, call
/// [NavigationSession.tick] yourself, for example from a `Timer` or your own
/// `Ticker`.
class NavigationMapFrame extends StatefulWidget {
  /// Creates the frame of [session]'s map, built by [mapBuilder].
  const NavigationMapFrame({
    super.key,
    required this.session,
    required this.mapBuilder,
    this.vehicleMarkers,
    this.focus = 0.7,
    this.horizontalFocus = 0.5,
    this.puck = const CarPuck(),
    this.recenterButton,
    this.recenterTooltip = 'Recenter',
    this.pauseInBackground = true,
    this.markerInterval = const Duration(milliseconds: 100),
  });

  /// The session the frame ticks and shows. Owned by the app.
  final NavigationSession session;

  /// Builds the map SDK's widget with the focus padding.
  final NavigationMapBuilder mapBuilder;

  /// Draws the vehicle while the camera does not follow it.
  final VehicleMarkerMap? vehicleMarkers;

  /// Where the followed vehicle sits, as a fraction of the height (0 = top).
  final double focus;

  /// Where the followed vehicle sits across the screen, as a fraction of
  /// the width (0 = left, 0.5 = the centre, the default), such as right of
  /// centre when a panel covers the left of the map.
  final double horizontalFocus;

  /// The vehicle drawn at the focus point while the camera follows it.
  final Widget puck;

  /// Builds the button shown while not following; null for a default one.
  final Widget Function(VoidCallback recenter)? recenterButton;

  /// Tooltip (and accessibility label) of the default recenter button.
  final String recenterTooltip;

  /// Pause the session while the app is in the background.
  final bool pauseInBackground;

  /// Minimum time between two vehicle-marker updates while not following.
  final Duration markerInterval;

  @override
  State<NavigationMapFrame> createState() => _NavigationMapFrameState();
}

class _NavigationMapFrameState extends State<NavigationMapFrame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  Duration? _markerAt;
  late bool _follow = widget.session.follow;

  /// The puck's turn, in radians clockwise: the vehicle's bearing minus the
  /// camera's (see [_puckTurn]).
  final _puckAngle = ValueNotifier<double>(0);
  bool _pausedByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didUpdateWidget(NavigationMapFrame old) {
    super.didUpdateWidget(old);
    final sessionChanged = !identical(old.session, widget.session);
    if (sessionChanged ||
        !identical(old.vehicleMarkers, widget.vehicleMarkers)) {
      old.vehicleMarkers?.hideVehicle();
      _markerAt = null;
    }
    if (sessionChanged) {
      if (_pausedByLifecycle) {
        _pausedByLifecycle = false;
        old.session.resume();
      }
      _follow = widget.session.follow;
    }
  }

  @override
  void dispose() {
    if (_pausedByLifecycle) {
      _pausedByLifecycle = false;
      widget.session.resume();
    }
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _puckAngle.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.pauseInBackground) return;
    final session = widget.session;
    if (state == AppLifecycleState.paused) {
      if (session.isRunning && !session.isPaused) {
        session.pause();
        _pausedByLifecycle = true;
      }
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      session.resume();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final session = widget.session;
    session.tick(dt);
    _puckAngle.value = _puckTurn(session);
    final markers = widget.vehicleMarkers;
    if (session.follow != _follow) {
      // The app changed `session.follow` itself: follow it.
      final follow = session.follow;
      setState(() => _follow = follow);
      if (follow) {
        markers?.hideVehicle();
      } else {
        _markerAt = null;
      }
    }
    if (_follow || markers == null) return;
    final at = _markerAt;
    if (at != null && elapsed - at < widget.markerInterval) return;
    final frame = session.frame;
    if (frame == null) return;
    _markerAt = elapsed;
    markers.showVehicle(frame.position, frame.bearing);
  }

  /// The vehicle's bearing minus the bearing the camera was sent (the
  /// vehicle's while heading up, north otherwise), in radians clockwise.
  static double _puckTurn(NavigationSession session) {
    final frame = session.frame;
    if (frame == null || session.camera.headingUp) return 0;
    return frame.bearing * math.pi / 180;
  }

  void _setFollow(bool follow) {
    if (_follow == follow && widget.session.follow == follow) return;
    if (_follow != follow) setState(() => _follow = follow);
    widget.session.follow = follow;
    if (follow) {
      widget.vehicleMarkers?.hideVehicle();
    } else {
      _markerAt = null;
    }
  }

  void _recenter() => _setFollow(true);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final padding = focusPadding(
          size,
          widget.focus,
          horizontal: widget.horizontalFocus,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => _setFollow(false),
                child: widget.mapBuilder(context, padding),
              ),
            ),
            if (_follow)
              Positioned(
                left: size.width * widget.horizontalFocus.clamp(0.0, 1.0),
                top: size.height * widget.focus.clamp(0.0, 1.0),
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _puckAngle,
                      builder: (context, angle, puck) =>
                          Transform.rotate(angle: angle, child: puck),
                      child: widget.puck,
                    ),
                  ),
                ),
              ),
            if (!_follow)
              Positioned(
                right: 16,
                bottom: 16,
                child:
                    widget.recenterButton?.call(_recenter) ??
                    FloatingActionButton.small(
                      // No hero: the app's own FAB already uses the default
                      // tag, and two equal tags throw on route transitions.
                      heroTag: null,
                      onPressed: _recenter,
                      tooltip: widget.recenterTooltip,
                      child: const Icon(Icons.navigation),
                    ),
              ),
          ],
        );
      },
    );
  }
}
