import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'google_style_strings.dart';

/// The line height (a multiple of the font size) of the text of a route card.
const double _lineHeight = 1.25;

/// The height of one full route card, with its margin, at [scaler]; at most
/// three cards show before the list scrolls. Each line is rounded up, as the
/// text layout rounds line heights.
double _cardExtent(TextScaler scaler) =>
    24 /* padding */ +
    (scaler.scale(22) * _lineHeight).ceilToDouble() +
    4 /* gap */ +
    (scaler.scale(14) * _lineHeight).ceilToDouble() +
    8 /* margin */;

/// The bottom card of the route overview: a spinner (with a cancel button)
/// while routes are looked for, the route options with the start and steps
/// buttons (and a close button), or the error with retry and cancel buttons.
/// Shows nothing in any other flow state.
///
/// The route cards have the keys `ValueKey('route_card_<i>')`, `<i>` being
/// the index of the route: stable hooks for tests.
class GoogleStyleOverviewPanel extends StatelessWidget {
  /// Creates the overview panel for [state].
  const GoogleStyleOverviewPanel({
    super.key,
    required this.state,
    this.tripOverview = false,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const GoogleStyleStrings(),
    this.colors = GoogleStyleColors.day,
    this.onSelect,
    this.onStart,
    this.onSteps,
    this.onRetry,
    this.onCancel,
    this.onClose,
  });

  /// What to show.
  final NavigationFlowState state;

  /// Whether the overview is of the trip under way; the start button then
  /// reads "Resume".
  final bool tripOverview;

  /// Formats the durations and the distances.
  final GuidanceFormatter formatter;

  /// The words of the panel.
  final GoogleStyleStrings strings;

  /// The colours of the panel.
  final GoogleStyleColors colors;

  /// Called with the index of the route card that was tapped.
  final ValueChanged<int>? onSelect;

  /// Called when the start (or resume) button is pressed.
  final VoidCallback? onStart;

  /// Called when the steps button is pressed; the button is hidden when null.
  final VoidCallback? onSteps;

  /// Called when the retry button is pressed.
  final VoidCallback? onRetry;

  /// Called when the cancel button of the loading or the error state is
  /// pressed; while loading the button is hidden when null.
  final VoidCallback? onCancel;

  /// Called when the close button of the route options is pressed; the
  /// button, at the top right of the panel, is hidden when null. Its tooltip
  /// is [GoogleStyleStrings.cancel].
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final content = switch (state) {
      FlowLoading() => _loading(),
      final FlowOverview overview => _options(context, overview),
      final FlowError error => _error(error),
      _ => null,
    };
    if (content == null) return const SizedBox.shrink();

    return Material(
      color: colors.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: content,
        ),
      ),
    );
  }

  // The cancel button takes at most 40% of the row, so a large text scale
  // cannot push it out.
  Widget _loading() => LayoutBuilder(
    builder: (context, box) => Row(
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            strings.findingRoutes,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurface, fontSize: 16),
          ),
        ),
        if (onCancel != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: colors.accent),
              child: Text(
                strings.cancel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _options(BuildContext context, FlowOverview overview) {
    final maxCardsHeight = math.min(
      3 * _cardExtent(MediaQuery.textScalerOf(context)),
      MediaQuery.sizeOf(context).height * 0.45,
    );
    final routes = overview.routes;
    final cards = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < routes.length; i++)
          _card(
            routes[i],
            index: i,
            selected: i == overview.selected,
            fastest: i == 0 && routes.length >= 2,
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onClose != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: strings.cancel,
              color: colors.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxCardsHeight),
            child: SingleChildScrollView(child: cards),
          ),
        ),
        const SizedBox(height: 4),
        // The steps button takes at most 40% of the row, so a large text
        // scale cannot squeeze the start button out.
        LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation),
                  label: Text(
                    tripOverview ? strings.resume : strings.start,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                  ),
                ),
              ),
              if (onSteps != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                    child: TextButton(
                      onPressed: onSteps,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.accent,
                      ),
                      child: Text(
                        strings.steps,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(
    NavRoute route, {
    required int index,
    required bool selected,
    required bool fastest,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: selected
          ? BorderSide(color: colors.accent, width: 2)
          : BorderSide(
              color: colors.onSurfaceVariant.withValues(alpha: 0.3),
              width: 1,
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          key: ValueKey('route_card_$index'),
          customBorder: shape,
          onTap: onSelect == null ? null : () => onSelect!(index),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Large text shrinks the whole line rather than cutting the
                // duration.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        formatter.duration(
                          Duration(seconds: route.duration.round()),
                        ),
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.etaText,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: _lineHeight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatter.distance(route.length),
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 15,
                          height: _lineHeight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (fastest || route.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // "Fastest" takes at most half of the line, the via text
                  // the rest.
                  LayoutBuilder(
                    builder: (context, box) => Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (fastest) ...[
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: box.maxWidth / 2,
                            ),
                            child: Text(
                              strings.fastest,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.etaText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: _lineHeight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (route.summary.isNotEmpty)
                          Flexible(
                            child: Text(
                              strings.via(route.summary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 14,
                                height: _lineHeight,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _error(FlowError error) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        strings.noRoute,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${error.error}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Each button may shrink (and ellipsise) at large text scales.
          Flexible(
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: colors.accent),
              child: Text(
                strings.cancel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
              ),
              child: Text(
                strings.retry,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
