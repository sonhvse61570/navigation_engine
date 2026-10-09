import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_lane_guidance.dart';

const _cardKey = ValueKey('google_style_header_card');
const _bandKey = ValueKey('google_style_header_band');
const _distanceKey = ValueKey('google_style_header_distance');
const _spinnerKey = ValueKey('google_style_header_spinner');
const _actionsKey = ValueKey('google_style_header_actions');

/// The least fling speed (logical px per second) that previews a step.
const double _swipeVelocity = 100;

/// "1.4 km" → ("1.4", "km"); a text without a space is all value.
(String, String) _splitDistance(String text) {
  final i = text.lastIndexOf(' ');
  return i <= 0 ? (text, '') : (text.substring(0, i), text.substring(i + 1));
}

/// Whether [step] goes straight on: a continue, a new name or a "turn"
/// whose modifier is straight or none. A continue or new name with a turn
/// modifier is a real turn (the road turns at a junction), and a
/// roundabout, fork or ramp keeps its own manoeuvre. A straight-on step
/// reads "toward" its road and hides its distance over 1 km.
bool _straightOn(RouteStep step) =>
    (step.type == ManeuverType.continueOn ||
        step.type == ManeuverType.newName ||
        step.type == ManeuverType.turn) &&
    (step.modifier == ManeuverModifier.straight ||
        step.modifier == ManeuverModifier.none);

/// Whether [step]'s road reads `toward <road>`: a straight-on step or a
/// depart.
bool _toward(RouteStep step) =>
    step.type == ManeuverType.depart || _straightOn(step);

/// The distance over which a [_straightOn] step hides it, in metres.
const double _hideDistanceOver = 1000;

/// The radius of the card's corners.
const Radius _cardRadius = Radius.circular(20);

/// The radius of the bottom corners of the band and the "Then" tab.
const BorderRadius _bandRadius = BorderRadius.vertical(
  bottom: Radius.circular(16),
);

/// The card's and the band's elevation: flat, so no shadow seam shows
/// where they meet.
const double _elevation = 0;

/// The turn card at the top of the navigation screen, after the Google
/// Maps app.
///
/// - **Card.** [GoogleStyleColors.guidance], radius 20, flat, [margin]
///   around it. The manoeuvre icon (48) sits on the start side with the
///   distance under it (value 18 w600, unit 13; clamped at 1.6x text). The
///   distance hides over 1 km on a straight-on step (a continue, new name
///   or turn whose modifier is straight or none). The road, in 28 w500 (2
///   lines at most), is vertically centred beside it. A straight-on step
///   or a depart puts a small [NavigationStrings.toward] (16) before the
///   road, on the same line; a turn shows the road alone. A step without a
///   road shows the formatter's instruction instead. Rerouting uses the
///   road's style.
/// - **"Then" tab** ([GoogleStyleColors.guidanceSecondary]): hanging under
///   the card's bottom-start corner, square on top and round below (16),
///   hugging "Then" (24) and the next manoeuvre's icon (40, an arrow about
///   26 across), when the next step follows closely and the step has no
///   lanes.
/// - **Lanes band** (the same colour): the lanes, as wide as the card,
///   round below (16), when the step has lanes.
///
/// A tap on the card, the tab or the band calls [onTap] (the step list);
/// while previewing, the band's chevrons preview instead. A horizontal
/// swipe calls [onNextStep] when it goes towards the start side, else
/// [onPreviousStep]. Screen readers get both as custom actions.
///
/// While [previewStep] is set, the card is grey
/// ([GoogleStyleColors.guidancePreview]) and shows that step at
/// [previewDistance], with chevron buttons in the band. While [rerouting],
/// it is grey with a spinner and [NavigationStrings.rerouting].
///
/// [GoogleStyleManeuverHeader.arrival] shows the same card with a flag,
/// [NavigationStrings.arrived], and the destination's name and address, or
/// the last road when the name is missing or blank.
///
/// These keys are stable test hooks: `google_style_header_card`,
/// `google_style_header_band` (the band or the "Then" tab),
/// `google_style_header_distance`, `google_style_header_spinner` and
/// `google_style_header_actions`.
class GoogleStyleManeuverHeader extends StatelessWidget {
  /// Creates the turn card for [state].
  const GoogleStyleManeuverHeader({
    super.key,
    required GuidanceState this.state,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.rerouting = false,
    this.previewStep,
    this.previewDistance = 0,
    this.onTap,
    this.onNextStep,
    this.onPreviousStep,
    this.margin = const EdgeInsets.all(8),
  }) : destination = null,
       lastRoad = null,
       _arrival = false;

  /// Creates the arrival card: a flag, [NavigationStrings.arrived], and
  /// [destination]'s name and address, or [lastRoad] without a destination
  /// or when its name is blank.
  const GoogleStyleManeuverHeader.arrival({
    super.key,
    this.destination,
    this.lastRoad,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.margin = const EdgeInsets.all(8),
  }) : state = null,
       formatter = const EnglishGuidanceFormatter(),
       rerouting = false,
       previewStep = null,
       previewDistance = 0,
       onTap = null,
       onNextStep = null,
       onPreviousStep = null,
       _arrival = true;

  /// What to show; null for the arrival card.
  final GuidanceState? state;

  /// Formats the distance and the manoeuvre.
  final GuidanceFormatter formatter;

  /// The words of the card.
  final NavigationStrings strings;

  /// The colours of the card.
  final GoogleStyleColors colors;

  /// Whether a new route is being looked for.
  final bool rerouting;

  /// The step previewed instead of the next one; null when none is.
  final RouteStep? previewStep;

  /// The distance to [previewStep], in metres along the route.
  final double previewDistance;

  /// Called on a tap on the card, such as to open the step list.
  final VoidCallback? onTap;

  /// Called to preview the next step: a swipe towards the start side, a
  /// chevron, or a screen reader action.
  final VoidCallback? onNextStep;

  /// Called to preview the previous step (or go back to the current one).
  final VoidCallback? onPreviousStep;

  /// The arrival card's destination.
  final PlaceLabel? destination;

  /// The arrival card's road when there is no [destination].
  final String? lastRoad;

  /// The space around the card, inside the top safe area.
  final EdgeInsetsGeometry margin;

  final bool _arrival;

  RouteStep? get _shownStep => previewStep ?? state?.step;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final grey = rerouting || previewStep != null;
    final band = _arrival || rerouting ? null : _band();
    final wideBand =
        band != null &&
        previewStep == null &&
        (_shownStep?.lanes.isNotEmpty ?? false);
    final card = Material(
      key: _cardKey,
      color: grey ? colors.guidancePreview : colors.guidance,
      elevation: _elevation,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadiusDirectional.only(
        topStart: _cardRadius,
        topEnd: _cardRadius,
        bottomStart: band == null ? _cardRadius : Radius.zero,
        bottomEnd: wideBand ? Radius.zero : _cardRadius,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 16, 16),
          child: _content(context),
        ),
      ),
    );
    Widget header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [card, ?band],
    );
    final next = onNextStep;
    final previous = onPreviousStep;
    if (next != null || previous != null) {
      header = Semantics(
        key: _actionsKey,
        customSemanticsActions: {
          CustomSemanticsAction(label: strings.nextStep): ?next,
          CustomSemanticsAction(label: strings.previousStep): ?previous,
        },
        // The custom actions are the swipe's for screen readers: the drag
        // adds no scroll actions of its own, which would do nothing.
        child: GestureDetector(
          excludeFromSemantics: true,
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v.abs() < _swipeVelocity) return;
            final towardsStart = rtl ? v > 0 : v < 0;
            (towardsStart ? next : previous)?.call();
          },
          child: header,
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: Padding(padding: margin, child: header),
    );
  }

  Widget _content(BuildContext context) {
    final on = colors.onGuidance;
    if (_arrival) return _arrivalContent(on);
    if (rerouting) {
      return Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              key: _spinnerKey,
              strokeWidth: 3,
              color: on,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              strings.rerouting,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // The road's style.
              style: TextStyle(
                color: on,
                fontSize: 28,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ],
      );
    }
    final guidance = state!;
    final step = _shownStep;
    final distance = previewStep != null
        ? previewDistance
        : guidance.distanceToStep;
    final (value, unit) = _splitDistance(formatter.distance(distance));
    final named = step != null && step.roadName.isNotEmpty;
    final road = step == null
        ? strings.arrived
        : named
        ? step.roadName
        : formatter.instruction(step);
    final toward = named && _toward(step);
    final showDistance =
        step == null || !(distance > _hideDistanceOver && _straightOn(step));
    // Large text scales stop at 1.6 for the distance, so it fits under the
    // icon on a narrow phone.
    final clamped = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return Row(
      children: [
        MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clamped),
          child: SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(maneuverIcon(step), size: 48, color: on),
                if (showDistance)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (unit.isNotEmpty)
                            TextSpan(
                              text: ' $unit',
                              style: const TextStyle(fontSize: 13),
                            ),
                        ],
                      ),
                      key: _distanceKey,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(color: on),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (toward)
                  TextSpan(
                    text: '${strings.toward} ',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                TextSpan(
                  text: road,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on, height: 1.2),
          ),
        ),
      ],
    );
  }

  Widget _arrivalContent(Color on) {
    // A blank name (empty or spaces) names nothing: the last road does.
    final given = destination?.name;
    final name = given != null && given.trim().isNotEmpty ? given : lastRoad;
    final address = destination?.address;
    return Row(
      children: [
        SizedBox(width: 64, child: Icon(Icons.flag, size: 48, color: on)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.arrived,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: on.withValues(alpha: 0.85),
                  fontSize: 16,
                ),
              ),
              if (name != null && name.isNotEmpty)
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              if (address != null && address.isNotEmpty)
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on.withValues(alpha: 0.85),
                    fontSize: 16,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The band under the card: the chevrons of a preview, the lanes, or
  /// the "Then" tab; null when there is nothing to show.
  Widget? _band() {
    if (previewStep != null) return _previewBand();
    final step = _shownStep;
    if (step != null && step.lanes.isNotEmpty) return _lanesBand(step);
    final then = state?.thenStep;
    return then == null ? null : _thenTab(then);
  }

  /// A flat piece under the card in [color], round below, keyed as the
  /// band.
  Widget _piece(Color color, EdgeInsetsGeometry padding, Widget child) =>
      Material(
        key: _bandKey,
        color: color,
        elevation: _elevation,
        borderRadius: _bandRadius,
        child: Padding(padding: padding, child: child),
      );

  /// Outside a preview the band is part of the header: a tap on it opens
  /// the step list as a tap on the card does (screen readers have the
  /// card's).
  Widget _tappable(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: onTap,
    child: child,
  );

  Widget _previewBand() {
    final on = colors.onGuidance;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _piece(
        colors.guidancePreview,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPreviousStep,
              tooltip: strings.previousStep,
              color: on,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: onNextStep,
              tooltip: strings.nextStep,
              color: on,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  /// The lanes, in a band as wide as the card.
  Widget _lanesBand(RouteStep step) => _tappable(
    _piece(
      colors.guidanceSecondary,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      GoogleStyleLaneGuidance(lanes: step.lanes, color: colors.onGuidance),
    ),
  );

  /// "Then" and [then]'s icon, in a tab hugging them under the card's
  /// bottom-start corner.
  Widget _thenTab(RouteStep then) {
    final on = colors.onGuidance;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _tappable(
        _piece(
          colors.guidanceSecondary,
          const EdgeInsetsDirectional.fromSTEB(20, 2, 12, 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  strings.then,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // A 40 dp box draws the arrow about 26 dp across.
              Icon(maneuverIcon(then), size: 40, color: on),
            ],
          ),
        ),
      ),
    );
  }
}
