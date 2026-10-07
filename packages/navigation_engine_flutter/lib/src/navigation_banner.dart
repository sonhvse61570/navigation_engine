import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';

import 'maneuver_icon.dart';

/// A minimal turn-by-turn banner for a [NavigationSession]: the next
/// manoeuvre's icon, distance and instruction, the close follow-up
/// manoeuvre, and optionally the last spoken prompt. Hidden while the
/// session has no guidance. Red while the vehicle is off route.
class NavigationBanner extends StatefulWidget {
  const NavigationBanner({
    super.key,
    required this.session,
    this.formatter = const EnglishGuidanceFormatter(),
    this.showLastAnnouncement = false,
    this.color = const Color(0xFF0B6E4F),
    this.offRouteColor = const Color(0xFFB3261E),
  });

  final NavigationSession session;
  final GuidanceFormatter formatter;
  final bool showLastAnnouncement;
  final Color color;
  final Color offRouteColor;

  @override
  State<NavigationBanner> createState() => _NavigationBannerState();
}

class _NavigationBannerState extends State<NavigationBanner> {
  final _subs = <StreamSubscription<Object?>>[];
  GuidanceState? _state;
  String? _lastPrompt;
  bool _offRoute = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NavigationBanner old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _unsubscribe();
      _state = widget.session.guidanceState;
      _lastPrompt = null;
      _offRoute = false;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    final session = widget.session;
    _state = session.guidanceState;
    _subs
      ..add(session.guidance.listen((g) => setState(() => _state = g)))
      ..add(
        session.announcements.listen(
          (a) => setState(() => _lastPrompt = widget.formatter.announcement(a)),
        ),
      )
      ..add(
        session.frames.listen((f) {
          if (f.offRoute != _offRoute) setState(() => _offRoute = f.offRoute);
        }),
      );
  }

  void _unsubscribe() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  @override
  Widget build(BuildContext context) {
    final g = _state;
    if (g == null) return const SizedBox.shrink();
    final f = widget.formatter;
    final step = g.step;
    final String title;
    if (g.arrived) {
      title = f.announcement(
        const GuidanceAnnouncement(
          stepIndex: -1,
          step: null,
          kind: AnnouncementKind.arrived,
          threshold: 0,
          distance: 0,
        ),
      );
    } else {
      // No manoeuvre left before the destination: head for the arrival.
      title = f.instruction(
        step ?? const RouteStep(distance: 0, type: ManeuverType.arrive),
      );
    }
    final then = g.thenStep;
    final prompt = widget.showLastAnnouncement ? _lastPrompt : null;
    return Material(
      color: _offRoute ? widget.offRouteColor : widget.color,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    g.arrived ? Icons.flag : maneuverIcon(step),
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!g.arrived)
                          Text(
                            f.distance(g.distanceToStep),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (then != null && !then.isArrival) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.subdirectory_arrow_right,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Icon(maneuverIcon(then), color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.instruction(then),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (prompt != null) ...[
                const SizedBox(height: 6),
                Text(
                  prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
