import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_round_button.dart';

/// The least fling speed (logical px per second) that opens or closes the
/// trip sheet whatever its position: a fling picks its direction.
const double _dragVelocity = 200;

/// The least vertical travel (logical px) of a slow drag that opens or
/// closes the trip sheet; past it, the nearer state wins.
const double _dragDistance = 32;

/// How long a tap takes to open or close the trip sheet.
const Duration _tapDuration = Duration(milliseconds: 250);

/// The spring a released drag settles with: critically damped, so it does
/// not bounce past the open or the closed height.
final SpringDescription _spring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 500,
);

/// The diameter of the close and route-options circles.
const double _circleSize = 52;

/// A menu row's start padding, before its icon.
const double _rowStart = 24;

/// The size of a menu row's icon.
const double _iconSize = 24;

/// Where a menu row's label starts, and its divider with it.
const double _labelStart = 76;

/// One row of the trip sheet's menu.
@immutable
final class GoogleStyleSheetAction {
  /// Creates a menu row with [icon] and [label] that calls [onPressed].
  const GoogleStyleSheetAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
  });

  /// The row's icon.
  final IconData icon;

  /// The row's label; its key is `google_style_sheet_action_<label>`.
  final String label;

  /// Called when the row is tapped. The menu closes first, except for a
  /// toggle ([selected] not null), which flips in place.
  final VoidCallback onPressed;

  /// For a toggle, whether it is on (its trailing switch shows it); null
  /// for an action.
  final bool? selected;
}

/// The bottom sheet of the navigation screen.
///
/// **Collapsed:**
/// - rounded top corners (radius 24) and a 32×4 drag handle;
/// - a row at least 76 high: a 52 dp close circle calling [onClose] (end
///   navigation), the time left in 24 w500 [GoogleStyleColors.etaText]
///   (clamped at 1.6x text) over "distance • arrival time" in 16 (or
///   [NavigationStrings.rerouting]), and a route-options circle with a
///   fork icon calling [onRouteOptions]. Both circles are
///   [GoogleStyleRoundButton]s: white, flat, with a thin
///   [GoogleStyleColors.closeOutline] ring. A missing circle leaves its
///   slot empty, so the time stays centred (the drop-in puts route options
///   in its end column instead).
///
/// **Expanded:** [actions] as 64 dp rows under it: a dark icon, a grey 18
/// label, and a trailing classic switch for a toggle
/// ([GoogleStyleSheetAction.selected]). A toggle row flips in place; any
/// other row closes the menu before its action. Inset dividers part the
/// rows, from the labels' start to the sheet's end. A bottom sheet caps
/// the rows at 45 % of the screen's height (they scroll); a [floating] one
/// leaves the cap to its parent. In a short landscape side panel at large
/// text fewer rows fit, and the rest scroll into view.
///
/// **Between the two:** the sheet follows the finger. Its expanded
/// fraction t (0 collapsed, 1 expanded; [onFractionChanged]) sets its
/// height between the collapsed height and the expanded one, the menu
/// clipped to it and fading in with t; the rows take no taps until t is 1.
/// On release a spring settles it: a fling (at least 200 dp/s) goes its
/// way, a slower release goes to the nearer state (past halfway opens),
/// and one under 32 dp goes back. A tap on the handle or the centre opens
/// or closes it in 250 ms, easing out, as the system back closes it
/// (unless [backClosesMenu] is false). A tap outside the sheet or an
/// action closes it at once. Without actions it does not open.
/// [onExpandedChanged] hears each change once the sheet settles.
///
/// These keys are stable test hooks: `google_style_trip_sheet_handle`,
/// `google_style_trip_sheet_centre`, `google_style_sheet_action_<label>`
/// and `google_style_sheet_divider_<i>` (under row `i`).
class GoogleStyleTripSheet extends StatefulWidget {
  /// Creates the trip sheet for [progress].
  const GoogleStyleTripSheet({
    super.key,
    required this.progress,
    this.rerouting = false,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.onClose,
    this.onRouteOptions,
    this.actions = const [],
    this.floating = false,
    this.onExpandedChanged,
    this.backClosesMenu = true,
    this.onFractionChanged,
  });

  /// What to show.
  final TripProgress progress;

  /// Whether the sheet floats as a card (in a landscape side panel): all
  /// four corners rounded alike. When false (the default) it is a bottom
  /// sheet reaching the screen's bottom edge, rounded at the top only.
  final bool floating;

  /// Whether a new route is being looked for; shown instead of the distance
  /// and the arrival time.
  final bool rerouting;

  /// Formats the duration, the distance and the arrival time.
  final GuidanceFormatter formatter;

  /// The words of the sheet.
  final NavigationStrings strings;

  /// The colours of the sheet.
  final GoogleStyleColors colors;

  /// Called by the close circle; it is hidden when null.
  final VoidCallback? onClose;

  /// Called by the route-options circle; it is hidden when null.
  final VoidCallback? onRouteOptions;

  /// The rows of the expanded menu.
  final List<GoogleStyleSheetAction> actions;

  /// Called when the menu opens (true) or closes (false), once the sheet
  /// settles. It may be called after the frame, and once more (with false)
  /// after the sheet is disposed with its menu open: check that the host is
  /// still mounted.
  final ValueChanged<bool>? onExpandedChanged;

  /// Called with the expanded fraction t (0 collapsed, 1 expanded) each
  /// time it changes: on every frame of a drag or an animation, so a host
  /// can fade its own controls with it. Like [onExpandedChanged] it may be
  /// called after the frame, and once more (with 0) after the sheet is
  /// disposed while not collapsed.
  final ValueChanged<double>? onFractionChanged;

  /// Whether the system back closes the open menu. Set it to false while a
  /// layer above the sheet (such as an open sound pill) closes on that back
  /// instead: the menu then stays open, and still keeps the back from
  /// leaving the screen.
  final bool backClosesMenu;

  @override
  State<GoogleStyleTripSheet> createState() => _GoogleStyleTripSheetState();
}

class _GoogleStyleTripSheetState extends State<GoogleStyleTripSheet>
    with SingleTickerProviderStateMixin {
  /// The expanded fraction t.
  late final AnimationController _t = AnimationController(vsync: this)
    ..addListener(_onFraction)
    ..addStatusListener(_onStatus);

  /// The settled state, as [GoogleStyleTripSheet.onExpandedChanged] last
  /// heard it.
  bool _expanded = false;

  /// Whether the sheet is not collapsed (t > 0), as last built.
  bool _moving = false;

  /// While a drag is on, t follows it and nothing settles.
  bool _dragging = false;

  /// Where the sheet was, or was heading, when the current drag started.
  bool _openAtStart = false;

  /// The state the sheet is in, or heading for while it animates.
  bool _heading = false;

  /// The vertical travel of the current drag; negative is up.
  double _travel = 0;

  /// While true, t changes are reported after the frame (a change made
  /// during a build).
  bool _later = false;

  /// The menu (with its top divider), for its natural height.
  final _menuKey = GlobalKey();

  /// The menu's natural height: the height t = 1 adds to the sheet.
  double get _menuExtent {
    final box = _menuKey.currentContext?.findRenderObject();
    final h = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    return math.max(h, 1);
  }

  @override
  void didUpdateWidget(GoogleStyleTripSheet old) {
    super.didUpdateWidget(old);
    if (widget.actions.isEmpty && (_expanded || _t.value > 0)) {
      // During the host's build: report after the frame.
      _later = true;
      _t.value = 0;
      _later = false;
      _moving = false;
      _dragging = false;
      _heading = false;
      if (_expanded) {
        _expanded = false;
        _notifyLater(false);
      }
    }
  }

  @override
  void dispose() {
    if (_expanded) _notifyLater(false);
    final fraction = widget.onFractionChanged;
    if (fraction != null && _t.value > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fraction(0));
    }
    _t.dispose();
    super.dispose();
  }

  // Not during this build or teardown: the host may rebuild with it.
  void _notifyLater(bool expanded) {
    final notify = widget.onExpandedChanged;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => notify(expanded));
  }

  void _onFraction() {
    final t = _t.value;
    final moving = t > 0;
    if (moving != _moving) setState(() => _moving = moving);
    final notify = widget.onFractionChanged;
    if (notify == null) return;
    final building =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    if (_later || building) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notify(_t.value);
      });
    } else {
      notify(t);
    }
  }

  /// Settles at the end of an animation: snaps t to the state it reached
  /// and reports it.
  void _onStatus(AnimationStatus status) {
    if (_dragging || _later || status.isAnimating) return;
    final open = _t.value >= 0.5;
    final target = open ? 1.0 : 0.0;
    if (_t.value != target) _t.value = target;
    _commit(open);
  }

  void _commit(bool open) {
    _heading = open;
    if (open == _expanded) return;
    setState(() => _expanded = open);
    widget.onExpandedChanged?.call(open);
  }

  /// Animates to [open] as a tap does: [_tapDuration], easing out.
  void _animate(bool open) {
    if (open && widget.actions.isEmpty) return;
    final target = open ? 1.0 : 0.0;
    _heading = open;
    if (_t.value == target && !_t.isAnimating) return _commit(open);
    _t.animateTo(target, duration: _tapDuration, curve: Curves.easeOut);
  }

  /// Closes at once (a tap outside, an action).
  void _close() {
    _dragging = false;
    _t.value = 0;
    _commit(false);
  }

  void _onDragStart(DragStartDetails details) {
    _t.stop();
    _dragging = true;
    // Grabbed mid-animation, it keeps the way it was going.
    _openAtStart = _heading;
    _travel = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0;
    _travel += dy;
    _t.value = (_t.value - dy / _menuExtent).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    final v = details.primaryVelocity ?? 0;
    // A fling picks its way; a slow release under the least travel goes
    // back; else the nearer state wins.
    final bool open;
    if (v.abs() >= _dragVelocity) {
      open = v < 0;
    } else if (_travel.abs() < _dragDistance) {
      open = _openAtStart;
    } else {
      open = _t.value >= 0.5;
    }
    final target = open ? 1.0 : 0.0;
    _heading = open;
    if (_t.value == target) return _commit(open);
    final simulation = SpringSimulation(
      _spring,
      _t.value,
      target,
      -v / _menuExtent,
    );
    if (open) {
      _t.animateWith(simulation);
    } else {
      _t.animateBackWith(simulation);
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _animate(_t.value >= 0.5);
  }

  void _run(GoogleStyleSheetAction action) {
    // A toggle flips in place, the menu staying open; an action closes it.
    if (action.selected == null) _close();
    action.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final strings = widget.strings;
    final formatter = widget.formatter;
    final progress = widget.progress;
    final second = widget.rerouting
        ? Text(
            strings.rerouting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.warning, fontSize: 16),
          )
        : Text(
            '${formatter.distance(progress.remainingDistance)}'
            ' • ${formatter.clockTime(progress.eta)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          );
    final canExpand = widget.actions.isNotEmpty;
    final centre = Semantics(
      button: canExpand,
      expanded: canExpand ? _expanded : null,
      child: InkWell(
        key: const ValueKey('google_style_trip_sheet_centre'),
        borderRadius: BorderRadius.circular(12),
        onTap: canExpand ? _toggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.6),
                ),
                child: Text(
                  formatter.duration(progress.remainingDuration),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.etaText,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              second,
            ],
          ),
        ),
      ),
    );
    final onClose = widget.onClose;
    final onRouteOptions = widget.onRouteOptions;
    final sheet = Material(
      color: colors.surface,
      elevation: 8,
      borderRadius: widget.floating
          ? BorderRadius.circular(24)
          : const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The handle's strip takes taps as the centre does (screen
            // readers have the centre's).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: canExpand ? _toggle : null,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    key: const ValueKey('google_style_trip_sheet_handle'),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    if (onClose != null)
                      _circle(
                        Icons.close,
                        strings.exitNavigation,
                        onClose,
                        colors,
                      )
                    else
                      const SizedBox(width: _circleSize),
                    Expanded(child: centre),
                    if (onRouteOptions != null)
                      _circle(
                        Icons.alt_route,
                        strings.routeOptions,
                        onRouteOptions,
                        colors,
                      )
                    else
                      const SizedBox(width: _circleSize),
                  ],
                ),
              ),
            ),
            if (canExpand) _reveal(_menu(context, colors)),
          ],
        ),
      ),
    );
    final open = _expanded || _moving;
    final sheetWithGestures = TapRegion(
      onTapOutside: open ? (_) => _close() : null,
      child: GestureDetector(
        // The sheet follows the finger from the touch, slop included.
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: canExpand ? _onDragStart : null,
        onVerticalDragUpdate: canExpand ? _onDragUpdate : null,
        onVerticalDragEnd: canExpand ? _onDragEnd : null,
        onVerticalDragCancel: canExpand ? _onDragCancel : null,
        child: sheet,
      ),
    );
    // The system back closes the menu before it leaves the screen.
    return PopScope<Object?>(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.backClosesMenu) _animate(false);
      },
      child: sheetWithGestures,
    );
  }

  /// A tap on the handle or the centre: towards the other state than the
  /// one the sheet is in or heading for.
  void _toggle() => _animate(!_heading);

  /// The menu under the row: its divider and its rows, capped.
  Widget _menu(BuildContext context, GoogleStyleColors colors) => Column(
    key: _menuKey,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Divider(height: 1, color: colors.outline),
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.floating
              ? double.infinity
              : MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, action) in widget.actions.indexed) ...[
                if (i > 0) _divider(i - 1, colors),
                _row(action, colors),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  /// [menu] shown to the expanded fraction t: as tall as t of its natural
  /// height (clipped), fading in with t, and taking taps only at t = 1.
  /// Collapsed, it is laid out (for its height) but off stage.
  Widget _reveal(Widget menu) => AnimatedBuilder(
    animation: _t,
    child: menu,
    builder: (context, menu) {
      final t = _t.value;
      return Offstage(
        offstage: t == 0,
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: IgnorePointer(
              ignoring: t < 1,
              child: Opacity(opacity: t, child: menu),
            ),
          ),
        ),
      );
    },
  );

  Widget _circle(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
    GoogleStyleColors colors,
  ) => GoogleStyleRoundButton(
    icon: Icon(icon),
    tooltip: tooltip,
    onPressed: onPressed,
    colors: colors,
    size: _circleSize,
    surface: colors.buttonSurface,
    outline: colors.closeOutline,
    iconColor: colors.buttonIcon,
    elevation: 0,
  );

  /// The inset divider under row [i]: from the labels' start to the end.
  Widget _divider(int i, GoogleStyleColors colors) => Padding(
    padding: const EdgeInsetsDirectional.only(start: _labelStart),
    child: Divider(
      key: ValueKey('google_style_sheet_divider_$i'),
      height: 1,
      thickness: 1,
      color: colors.outline,
    ),
  );

  Widget _row(GoogleStyleSheetAction action, GoogleStyleColors colors) {
    final selected = action.selected;
    return Semantics(
      button: true,
      toggled: selected,
      child: InkWell(
        key: ValueKey('google_style_sheet_action_${action.label}'),
        onTap: () => _run(action),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: _rowStart,
              end: 16,
            ),
            child: Row(
              children: [
                Icon(action.icon, size: _iconSize, color: colors.onSurface),
                const SizedBox(width: _labelStart - _rowStart - _iconSize),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (selected != null)
                  // The row's semantics say toggled, and a tap anywhere on
                  // the row (the switch too) flips it.
                  _ClassicSwitch(
                    key: ValueKey('google_style_sheet_switch_${action.label}'),
                    value: selected,
                    colors: colors,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A classic switch, drawn here: a large thumb with a soft shadow over a
/// thin track with no outline, as in Google Maps. It only shows the state;
/// its row takes the taps. The thumb is [GoogleStyleColors.switchThumb];
/// the track is [GoogleStyleColors.accent] when on, else
/// [GoogleStyleColors.switchTrackOff].
class _ClassicSwitch extends StatelessWidget {
  const _ClassicSwitch({super.key, required this.value, required this.colors});

  final bool value;
  final GoogleStyleColors colors;

  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 20,
    child: Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          key: const ValueKey('google_style_sheet_switch_track'),
          duration: _duration,
          width: 34,
          height: 14,
          decoration: BoxDecoration(
            color: value ? colors.accent : colors.switchTrackOff,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        AnimatedAlign(
          duration: _duration,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            key: const ValueKey('google_style_sheet_switch_thumb'),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colors.switchThumb,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
