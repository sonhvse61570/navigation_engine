import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'google_style_colors.dart';
import 'incident_type.dart';

/// The width of a report tile and the gap between two: 4 fit in a row
/// within the sheet's padding on a 360 dp screen.
const double _tileWidth = 78;
const double _tileGap = 4;

/// Opens [GoogleStyleReportSheet] in a modal bottom sheet. It completes with
/// the type chosen, or with null when the sheet is dismissed.
Future<IncidentType?> showGoogleStyleReportSheet(
  BuildContext context, {
  NavigationStrings strings = const NavigationStrings(),
  GoogleStyleColors colors = GoogleStyleColors.day,
}) => showModalBottomSheet<IncidentType>(
  context: context,
  isScrollControlled: true,
  backgroundColor: colors.surface,
  builder: (context) => GoogleStyleReportSheet(
    strings: strings,
    colors: colors,
    onSelected: (type) => Navigator.of(context).pop(type),
  ),
);

/// The "Add a report" sheet: [NavigationStrings.addReport] (a header for
/// screen readers) over a grid of the 8 [IncidentType]s, each a round 64 dp
/// coloured tile with its icon and its name under it (wrapped between words
/// only, scaled down when a word would not fit), 4 to a row on a 360 dp
/// screen, spread over the sheet's width. A tap calls [onSelected]. It scrolls when the screen is
/// short.
///
/// The keys `google_style_report_tile_<name>` (the coloured circles) are
/// stable test hooks.
class GoogleStyleReportSheet extends StatelessWidget {
  /// Creates the report sheet.
  const GoogleStyleReportSheet({
    super.key,
    required this.onSelected,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
  });

  /// Called with the type of the tile tapped.
  final ValueChanged<IncidentType> onSelected;

  /// The words of the sheet.
  final NavigationStrings strings;

  /// The colours of the sheet.
  final GoogleStyleColors colors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        // The full width the sheet is given, so the grid spreads over it.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                textAlign: TextAlign.start,
                strings.addReport,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: _tileGap,
              runSpacing: 16,
              alignment: WrapAlignment.spaceEvenly,
              children: [
                for (final type in IncidentType.values) _tile(context, type),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IncidentType type) => SizedBox(
    width: _tileWidth,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onSelected(type),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            key: ValueKey('google_style_report_tile_${type.name}'),
            decoration: BoxDecoration(
              color: type.tileColor,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 64,
              child: Icon(type.icon, color: const Color(0xFFFFFFFF), size: 32),
            ),
          ),
          const SizedBox(height: 6),
          _label(context, type.label(strings)),
        ],
      ),
    ),
  );

  /// [name] under its tile: as many lines as it needs (the sheet scrolls),
  /// broken between words only. When its longest word is wider than the
  /// tile at this text size, the name is scaled down until that word fits.
  Widget _label(BuildContext context, String name) {
    final style = DefaultTextStyle.of(context).style
        .merge(TextStyle(color: colors.onSurface, fontSize: 13));
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final word in name.split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    // A margin under the tile's width: the engine may round a scaled font
    // size up.
    const room = _tileWidth * 0.9;
    return Text(
      name,
      textAlign: TextAlign.center,
      style: style,
      textScaler: widest > room
          ? TextScaler.linear(scaler.scale(13) / 13 * room / widest)
          : null,
    );
  }
}
