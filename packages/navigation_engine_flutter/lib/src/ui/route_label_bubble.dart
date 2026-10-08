import 'package:flutter/widgets.dart';

import 'route_label.dart';

/// The route duration bubble that [paintRouteLabel] paints, as a widget, for
/// maps that take widget markers.
///
/// It has the same look and the same size as the painted bubble: the text is
/// 14 logical px, weight 600, inside a 10 x 6 logical px padding and a
/// corner radius of 8. An unselected bubble is [RouteLabelColors.fill] with
/// a 1 px [RouteLabelColors.border]; a selected one is
/// [RouteLabelColors.selectedFill] with no visible border.
///
/// Like the painted bubble, it ignores the app's text scale
/// ([TextScaler.noScaling]): it is a map label, sized like the map's own
/// labels, and maps size the box they give it from the unscaled text.
class RouteLabelBubble extends StatelessWidget {
  /// Creates the bubble for [text] (a route's duration, say).
  const RouteLabelBubble({
    super.key,
    required this.text,
    required this.selected,
    this.colors = const RouteLabelColors(),
  });

  /// The text of the bubble.
  final String text;

  /// Whether this is the selected route's label.
  final bool selected;

  /// The colours of the bubble.
  final RouteLabelColors colors;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? colors.selectedFill : colors.fill;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(routeLabelRadius),
        // A DecoratedBox border takes no room, as in the painted bubble.
        // The selected bubble's is in its own fill colour.
        border: Border.all(color: selected ? fill : colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: routeLabelPaddingX,
          vertical: routeLabelPaddingY,
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: routeLabelFontSize,
            fontWeight: FontWeight.w600,
            color: selected ? colors.selectedText : colors.text,
          ),
        ),
      ),
    );
  }
}
