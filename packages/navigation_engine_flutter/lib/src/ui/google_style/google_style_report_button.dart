import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation_strings.dart';
import 'google_style_colors.dart';

/// The report button, at the top of the navigation screen's end column. It
/// starts as a pill with a speech-bubble-plus icon and
/// [NavigationStrings.report]; after [collapseAfter] it shrinks to a 52 dp
/// circle with the icon alone.
/// It looks like the round map buttons: [GoogleStyleColors.buttonSurface],
/// a 1 dp [GoogleStyleColors.outline] ring, elevation 1.
/// Its accessibility label is always [NavigationStrings.report].
///
/// The key `google_style_report_button` (on its [Material]) is a stable
/// test hook.
class GoogleStyleReportButton extends StatefulWidget {
  /// Creates the report button.
  const GoogleStyleReportButton({
    super.key,
    required this.onPressed,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.collapseAfter = const Duration(seconds: 5),
  });

  /// Called when the button is pressed, such as to open the report sheet.
  final VoidCallback onPressed;

  /// The words of the button.
  final NavigationStrings strings;

  /// The colours of the button.
  final GoogleStyleColors colors;

  /// How long the label shows before the button shrinks to its icon. A new
  /// value while the label shows starts the countdown again.
  final Duration collapseAfter;

  @override
  State<GoogleStyleReportButton> createState() =>
      _GoogleStyleReportButtonState();
}

class _GoogleStyleReportButtonState extends State<GoogleStyleReportButton> {
  bool _expanded = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule(widget.collapseAfter);
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  void didUpdateWidget(GoogleStyleReportButton old) {
    super.didUpdateWidget(old);
    // A new delay starts the countdown again.
    if (_expanded && widget.collapseAfter != old.collapseAfter) {
      _schedule(widget.collapseAfter);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final label = widget.strings.report;
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('google_style_report_button'),
        color: colors.buttonSurface,
        elevation: 1,
        shape: StadiumBorder(side: BorderSide(color: colors.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPressed,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _expanded ? 16 : 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size.square(24),
                      painter: _ReportIconPainter(colors.buttonIcon),
                    ),
                    if (_expanded) ...[
                      const SizedBox(width: 8),
                      // Ellipsized in a parent narrower than the pill.
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.buttonIcon,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A speech bubble with a plus in it.
class _ReportIconPainter extends CustomPainter {
  const _ReportIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeJoin = StrokeJoin.round;
    final bubble = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3 * s, 3 * s, 18 * s, 14 * s),
          Radius.circular(3 * s),
        ),
      )
      ..moveTo(8 * s, 17 * s)
      ..lineTo(8 * s, 21 * s)
      ..lineTo(12 * s, 17 * s);
    canvas
      ..drawPath(bubble, stroke)
      ..drawLine(Offset(12 * s, 7 * s), Offset(12 * s, 13 * s), stroke)
      ..drawLine(Offset(9 * s, 10 * s), Offset(15 * s, 10 * s), stroke);
  }

  @override
  bool shouldRepaint(_ReportIconPainter old) => old.color != color;
}
