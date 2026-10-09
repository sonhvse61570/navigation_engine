import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import '../along_route_search.dart';
import 'google_style_colors.dart';

/// The search-along-the-route overlay. It fills its parent and leaves the
/// middle see-through: touches there reach the map.
///
/// - **Top**, inside the safe area: a rounded card with a back button
///   ([onClose]) and a search field, with a thin progress bar while a
///   search runs; under it, one chip per [AlongRouteCategory].
/// - **Bottom:** [NavigationStrings.searchFailed],
///   [NavigationStrings.noResults], or the results (name, subtitle and
///   "+detour"). A tap on a result focuses it and calls [onFocus]; the
///   host can focus one too ([focusedPlace], such as from its pin). With
///   [onAddStop], an "Add stop" button for the focused result calls it; the
///   library adds no stop itself.
///
/// Each search calls [onResults] with an empty list at once (the pins of
/// the previous search go), then with its results. A newer search drops an
/// older one's results, and so does leaving the screen. When [route]
/// changes (a reroute), the results go and the last search runs again
/// along the new route.
///
/// These keys are stable test hooks: `google_style_search_field`,
/// `google_style_search_progress`, `google_style_search_chip_<category>`,
/// `google_style_search_result_<id>` and `google_style_search_add_stop`.
class GoogleStyleSearchAlongRoute extends StatefulWidget {
  /// Creates the overlay that searches with [search] along [route].
  const GoogleStyleSearchAlongRoute({
    super.key,
    required this.search,
    required this.route,
    required this.fromDistance,
    required this.onResults,
    required this.onFocus,
    required this.onClose,
    this.onAddStop,
    this.formatter = const EnglishGuidanceFormatter(),
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.focusedPlace,
    this.onBarHeight,
  });

  /// The app's search back end.
  final AlongRouteSearch search;

  /// The route being driven.
  final NavRoute route;

  /// How far along [route] the vehicle is, in metres.
  final double fromDistance;

  /// Called with each search's results (empty when a search starts).
  final ValueChanged<List<AlongRoutePlace>> onResults;

  /// Called with the result the user tapped.
  final ValueChanged<AlongRoutePlace> onFocus;

  /// Called by the back button.
  final VoidCallback onClose;

  /// Called by the "Add stop" button; the button is hidden when null.
  final ValueChanged<AlongRoutePlace>? onAddStop;

  /// Formats the detours.
  final GuidanceFormatter formatter;

  /// The words of the overlay.
  final NavigationStrings strings;

  /// The colours of the overlay.
  final GoogleStyleColors colors;

  /// A place the host focused, such as by a tap on its pin on the map. When
  /// it changes to a place among the results, that result is selected as by
  /// a tap on it (without calling [onFocus]), with its "Add stop" button.
  final AlongRoutePlace? focusedPlace;

  /// Called after a frame whose layout changed the height of the top (the
  /// search bar: from the overlay's top edge, its safe area included, to
  /// below the chips), so a host can keep its own pieces under it.
  final ValueChanged<double>? onBarHeight;

  @override
  State<GoogleStyleSearchAlongRoute> createState() =>
      _GoogleStyleSearchAlongRouteState();
}

class _GoogleStyleSearchAlongRouteState
    extends State<GoogleStyleSearchAlongRoute> {
  final _text = TextEditingController();
  AlongRouteCategory? _category;
  int _generation = 0;
  bool _searching = false;
  bool _failed = false;
  List<AlongRoutePlace>? _results;
  AlongRoutePlace? _focused;

  /// The last search asked for, to run again along a new route; null
  /// before the first.
  ({String? text, AlongRouteCategory? category})? _lastQuery;

  @override
  void didUpdateWidget(GoogleStyleSearchAlongRoute old) {
    super.didUpdateWidget(old);
    if (!identical(old.route, widget.route)) _onNewRoute();
    final place = widget.focusedPlace;
    if (place == null || place.id == old.focusedPlace?.id) return;
    final match = _results?.where((r) => r.id == place.id).firstOrNull;
    if (match != null) _focused = match;
  }

  @override
  void dispose() {
    _generation++;
    _text.dispose();
    super.dispose();
  }

  /// The route changed (a reroute): the results, found along the old one,
  /// go now, an answer still due for it is dropped, and the last search runs
  /// again along the new route after this frame (it tells the host, which
  /// must not rebuild during this build).
  void _onNewRoute() {
    _generation++;
    _searching = false;
    _failed = false;
    _results = null;
    _focused = null;
    final last = _lastQuery;
    if (last == null) return;
    final route = widget.route;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.route, route)) return;
      _run(text: last.text, category: last.category);
    });
  }

  Future<void> _run({String? text, AlongRouteCategory? category}) async {
    final generation = ++_generation;
    _lastQuery = (text: text, category: category);
    setState(() {
      _searching = true;
      _failed = false;
      _results = null;
      _focused = null;
      _category = category;
    });
    _notify(const []);
    final List<AlongRoutePlace> results;
    try {
      results = await widget.search(
        AlongRouteQuery(
          text: text,
          category: category,
          route: widget.route,
          fromDistance: widget.fromDistance,
        ),
      );
    } catch (_) {
      // Only the search back end's errors are a failed search.
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _failed = true;
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _searching = false;
      _results = results;
    });
    _notify(results);
  }

  /// Calls the host's [GoogleStyleSearchAlongRoute.onResults]; an error it
  /// throws is the host's bug, so it is reported, not shown as a failed
  /// search.
  void _notify(List<AlongRoutePlace> results) {
    try {
      widget.onResults(results);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'navigation_engine_google_maps',
          context: ErrorDescription('while calling onResults'),
        ),
      );
    }
  }

  void _focus(AlongRoutePlace place) {
    FocusScope.of(context).unfocus();
    setState(() => _focused = place);
    widget.onFocus(place);
  }

  String _label(AlongRouteCategory c) => switch (c) {
    AlongRouteCategory.gas => widget.strings.gasStations,
    AlongRouteCategory.restaurant => widget.strings.restaurants,
    AlongRouteCategory.coffee => widget.strings.coffee,
    AlongRouteCategory.grocery => widget.strings.groceries,
  };

  static IconData _icon(AlongRouteCategory c) => switch (c) {
    AlongRouteCategory.gas => Icons.local_gas_station,
    AlongRouteCategory.restaurant => Icons.restaurant,
    AlongRouteCategory.coffee => Icons.local_cafe,
    AlongRouteCategory.grocery => Icons.local_grocery_store,
  };

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final strings = widget.strings;
    final top = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: colors.buttonSurface,
              elevation: 4,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: strings.cancel,
                        onPressed: widget.onClose,
                        color: colors.buttonIcon,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('google_style_search_field'),
                          controller: _text,
                          textInputAction: TextInputAction.search,
                          cursorColor: colors.accent,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: strings.searchHint,
                            hintStyle: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) {
                            final text = value.trim();
                            if (text.isNotEmpty) _run(text: text);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  if (_searching)
                    LinearProgressIndicator(
                      key: const ValueKey('google_style_search_progress'),
                      semanticsLabel: strings.searchAlongRoute,
                      minHeight: 2,
                      color: colors.accent,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in AlongRouteCategory.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        key: ValueKey('google_style_search_chip_${c.name}'),
                        avatar: Icon(
                          _icon(c),
                          size: 18,
                          color: _category == c
                              ? colors.onSelectedTint
                              : colors.buttonIcon,
                        ),
                        label: Text(_label(c)),
                        labelStyle: TextStyle(
                          color: _category == c
                              ? colors.onSelectedTint
                              : colors.onSurface,
                        ),
                        selected: _category == c,
                        showCheckmark: false,
                        // One colour per state, set directly: the chip's own
                        // selection fade starts from the theme's selected
                        // colour (Material's purple) for a frame.
                        color: WidgetStatePropertyAll(
                          _category == c
                              ? colors.selectedTint
                              : colors.buttonSurface,
                        ),
                        side: BorderSide(color: colors.outline),
                        onSelected: (_) {
                          FocusScope.of(context).unfocus();
                          _run(category: c);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final bottom = _bottom(context, colors, strings);
    final onBarHeight = widget.onBarHeight;
    return Column(
      children: [
        // Always wrapped, so a callback that comes or goes does not remount
        // the field.
        _HeightReporter(onHeight: onBarHeight, child: top),
        // See-through: touches here reach the map under the overlay.
        // The results card takes the room left under the top, so it
        // shrinks with a keyboard the parent made room for.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => bottom == null
                ? const SizedBox()
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.min(
                          constraints.maxHeight,
                          MediaQuery.sizeOf(context).height * 0.4,
                        ),
                      ),
                      child: bottom,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget? _bottom(
    BuildContext context,
    GoogleStyleColors colors,
    NavigationStrings strings,
  ) {
    Widget card(Widget child) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: colors.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
    // Read out when it appears.
    Widget message(String text) => card(
      Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            style: TextStyle(color: colors.onSurface, fontSize: 16),
          ),
        ),
      ),
    );
    if (_failed) return message(strings.searchFailed);
    final results = _results;
    if (results == null) return null;
    if (results.isEmpty) return message(strings.noResults);
    final focused = _focused;
    final onAddStop = widget.onAddStop;
    return card(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final place in results)
                  ListTile(
                    key: ValueKey('google_style_search_result_${place.id}'),
                    selected: focused?.id == place.id,
                    selectedTileColor: colors.selectedTint,
                    title: Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurface),
                    ),
                    subtitle: place.subtitle == null
                        ? null
                        : Text(
                            place.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                    trailing: place.detour == null
                        ? null
                        : Text(
                            '+${widget.formatter.duration(place.detour!)}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                    onTap: () => _focus(place),
                  ),
              ],
            ),
          ),
          if (focused != null && onAddStop != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                key: const ValueKey('google_style_search_add_stop'),
                onPressed: () => onAddStop(focused),
                icon: const Icon(Icons.add_location_alt),
                label: Text(strings.addStop),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reports its child's height after a frame whose layout changed it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, super.child});

  final ValueChanged<double>? onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this._onHeight);

  ValueChanged<double>? _onHeight;
  double? _reported;

  set onHeight(ValueChanged<double>? value) {
    if (value == null) _reported = null;
    if (identical(value, _onHeight)) return;
    final reportNow = _onHeight == null && value != null;
    _onHeight = value;
    // A callback given later hears the height at the next layout.
    if (reportNow) markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_onHeight == null) return;
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Not during layout: the host may rebuild with it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final onHeight = _onHeight;
      if (attached && _reported == height && onHeight != null) {
        onHeight(height);
      }
    });
  }
}
