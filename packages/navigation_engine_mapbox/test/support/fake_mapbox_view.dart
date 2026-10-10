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
    show MapboxViewBinding;

import 'recording_backend.dart';

/// Stands in for [MapboxNavigationView] in widget tests, where the Mapbox
/// `MapWidget` cannot be mounted (its platform is not reachable without a
/// new dependency).
///
/// Pass [build] as `MapboxStyleNavigation.mapViewBuilder`. It records each
/// [MapboxNavigationView] the drop-in builds ([built]) and shows a
/// [FakeMapboxView] for it, which runs the real view's [MapboxViewBinding]
/// (attaching the adapter to the session, forwarding the view's
/// parameters, the light preset and the style by `night`) with a
/// [MapboxNavigationMap] on the [backend] in place of the SDK's map, and
/// ticks the session through a [NavigationMapFrame]. [createMap] and [loadStyle] play the
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

  /// The SDK reports a tap on the map where no feature took it.
  void tapMap(GeoPoint point) => backend.tapMap(point);

  /// The SDK reports a long tap on the map.
  void longPressMap(GeoPoint point) => backend.longPressMap(point);
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
  /// The real view's binding: the same adapter logic as the view.
  late final MapboxViewBinding binding = MapboxViewBinding(
    _view,
    // Rendered without the engine.
    fallbackVehicleImage: (_) async => Uint8List(4),
  );

  /// The adapter the view draws with.
  MapboxNavigationMap get adapter => binding.adapter;

  MapboxNavigationView get _view => widget.view;

  @override
  void initState() {
    super.initState();
    widget.owner.mounted.add(this);
    binding; // Creates the adapter and attaches it now.
  }

  /// What the real view does in `MapWidget.onMapCreated`.
  void createMap() {
    adapter.attachBackend(widget.owner.backend);
    binding.mapCreated();
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
    binding.update(old.view, _view);
  }

  @override
  void dispose() {
    binding.dispose(_view);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigationMapFrame(
    session: _view.session,
    vehicleMarkers: adapter,
    focus: _view.focus,
    horizontalFocus: _view.horizontalFocus,
    puck: _view.puck,
    recenterButton: _view.recenterButton,
    mapBuilder: (context, padding) {
      binding.framePadding(padding);
      return LayoutBuilder(
        builder: (context, constraints) {
          binding.reportViewport(constraints.biggest, mounted: () => mounted);
          return const SizedBox.expand();
        },
      );
    },
  );
}
