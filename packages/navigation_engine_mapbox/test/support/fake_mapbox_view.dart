// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';
import 'package:navigation_engine_mapbox/navigation_engine_mapbox.dart';
import 'package:navigation_engine_mapbox/src/mapbox_navigation_map.dart'
    show MapboxNavigationMapTesting;
import 'package:navigation_engine_mapbox/src/mapbox_navigation_view.dart'
    show dayNightStyle;

import 'recording_backend.dart';

/// Stands in for [MapboxNavigationView] in widget tests, where the Mapbox
/// `MapWidget` cannot be mounted (its platform is not reachable without a
/// new dependency).
///
/// Pass [build] as `MapboxStyleNavigation.mapViewBuilder`. It records each
/// [MapboxNavigationView] the drop-in builds ([built]) and shows a
/// [FakeMapboxView] for it, which does what the real view does with a
/// [MapboxNavigationMap] on the [backend] in place of the SDK's map: it
/// attaches the adapter to the session, forwards the view's parameters,
/// ticks the session through a [NavigationMapFrame], sets the light preset
/// and changes the style by `night`. [createMap] and [loadStyle] play the
/// SDK's `onMapCreated` and `onStyleLoadedListener`; `onMapCreated` gets no
/// map (null), as no `MapboxMap` can be made without the SDK's platform.
class FakeMapboxViews {
  /// The backend every fake map draws into.
  final backend = RecordingBackend();

  /// Every view the drop-in built, in order.
  final built = <MapboxNavigationView>[];

  /// The fake views mounted, in order: one per map the real view would
  /// have created.
  final mounted = <FakeMapboxViewState>[];

  /// The view the drop-in built last.
  MapboxNavigationView get view => built.last;

  /// The fake view on screen.
  FakeMapboxViewState get current => mounted.last;

  /// The `mapViewBuilder` of `MapboxStyleNavigation`.
  Widget build(BuildContext context, MapboxNavigationView view) {
    built.add(view);
    return FakeMapboxView(key: view.key, view: view, owner: this);
  }

  /// The SDK created the map: the adapter gets the backend, then the
  /// view's `onMapCreated` is called (with no map).
  void createMap() => current.createMap();

  /// The SDK loaded the style.
  void loadStyle() => current.loadStyle();
}

/// A [MapboxNavigationView] without the SDK's map; see [FakeMapboxViews].
class FakeMapboxView extends StatefulWidget {
  const FakeMapboxView({super.key, required this.view, required this.owner});

  /// The view the drop-in built.
  final MapboxNavigationView view;

  final FakeMapboxViews owner;

  @override
  State<FakeMapboxView> createState() => FakeMapboxViewState();
}

class FakeMapboxViewState extends State<FakeMapboxView> {
  late final MapboxNavigationMap adapter = MapboxNavigationMap(
    routeColors: _view.routeColors,
    // Rendered without the engine.
    vehicleImage: _view.vehicleImage ?? (_) async => Uint8List(4),
  );

  MapboxNavigationView get _view => widget.view;

  ({String styleUri, String? lightPreset}) _dayNight(MapboxNavigationView v) =>
      dayNightStyle(v.styleUri, v.nightStyleUri, night: v.night);

  @override
  void initState() {
    super.initState();
    widget.owner.mounted.add(this);
    _sync();
    adapter.lightPreset = _dayNight(_view).lightPreset;
    _view.session.map = adapter;
  }

  void _sync() {
    adapter
      ..routeLabel = _view.routeLabel
      ..onRouteOptionTap = _view.onRouteOptionTap
      ..routeColors = _view.routeColors
      ..alternativeColor = _view.alternativeRouteColor
      ..labelColors = _view.labelColors
      ..bottomInset = _view.bottomInset;
  }

  /// What the real view does in `MapWidget.onMapCreated`.
  void createMap() {
    adapter
      ..attachBackend(widget.owner.backend)
      ..hideOrnaments()
      ..placeOrnaments();
    // There is no MapboxMap without the SDK's platform: the drop-in's hook
    // takes a nullable map, so it can be called with none.
    final onMapCreated = _view.onMapCreated;
    if (onMapCreated == null) return;
    if (onMapCreated is! void Function(mb.MapboxMap?)) {
      throw StateError('onMapCreated cannot be called without a MapboxMap');
    }
    onMapCreated(null);
  }

  /// What the real view does in `MapWidget.onStyleLoadedListener`.
  void loadStyle() => unawaited(adapter.onStyleLoaded());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    adapter.pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void didUpdateWidget(FakeMapboxView old) {
    super.didUpdateWidget(old);
    if (!identical(old.view.session, _view.session)) {
      if (identical(old.view.session.map, adapter)) old.view.session.map = null;
      _view.session.map = adapter;
    }
    _sync();
    final shown = _dayNight(_view);
    if (_dayNight(old.view).styleUri != shown.styleUri) {
      adapter.changeStyle(shown.styleUri);
    }
    adapter.lightPreset = shown.lightPreset;
  }

  @override
  void dispose() {
    if (identical(_view.session.map, adapter)) _view.session.map = null;
    adapter.dispose();
    super.dispose();
  }

  Size? _reportedSize;

  @override
  Widget build(BuildContext context) => NavigationMapFrame(
    session: _view.session,
    vehicleMarkers: adapter,
    focus: _view.focus,
    puck: _view.puck,
    recenterButton: _view.recenterButton,
    mapBuilder: (context, padding) {
      adapter.padding = padding;
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size != _reportedSize) {
            _reportedSize = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _reportedSize == size) {
                adapter.viewportSize = size;
              }
            });
          }
          return const SizedBox.expand();
        },
      );
    },
  );
}
