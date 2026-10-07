/// Map-agnostic turn-by-turn navigation: snaps ~1 Hz GPS to a route, turns it
/// into smooth display-rate motion and camera targets, and produces
/// turn-by-turn guidance.
library;

export 'src/fix/fix_filter.dart';
export 'src/fix/fix_source.dart';
export 'src/fix/nav_fix.dart';
export 'src/geo/geo_math.dart'
    show angleDelta, bearingBetween, distanceBetween, offsetPoint;
export 'src/geo/geo_point.dart';
export 'src/guidance/english_guidance_formatter.dart';
export 'src/guidance/guidance_announcement.dart';
export 'src/guidance/guidance_formatter.dart'
    show GuidanceFormatter, splitDuration;
export 'src/guidance/guidance_state.dart';
export 'src/guidance/nav_guidance.dart';
export 'src/guidance/vietnamese_guidance_formatter.dart';
export 'src/map/camera_target.dart';
export 'src/map/follow_camera.dart';
export 'src/map/navigation_map.dart';
export 'src/motion/free_motion_engine.dart';
export 'src/motion/motion_engine.dart' show MotionEngine;
export 'src/motion/motion_frame.dart';
export 'src/motion/route_motion_engine.dart';
export 'src/route/lane.dart';
export 'src/route/maneuver.dart';
export 'src/route/nav_route.dart';
export 'src/route/route_snap.dart';
export 'src/route/route_step.dart';
export 'src/routing/route_provider.dart';
export 'src/session/navigation_session.dart';
export 'src/session/session_event.dart';
export 'src/sun/sun_times.dart';
