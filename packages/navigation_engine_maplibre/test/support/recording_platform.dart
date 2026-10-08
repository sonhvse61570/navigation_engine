import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// A layer of the fake style.
typedef FakeLayer = ({
  String kind,
  String id,
  String source,
  String? below,
  bool interactive,
  Map<String, dynamic> properties,
});

/// A platform that records what the controller sends and can be told to
/// fail or to hold a call back. Only the calls the adapter makes are
/// implemented.
///
/// It also keeps a small model of the style: [sources] with their data,
/// [layers] bottom to top (a layer added with a `belowLayerId` goes right
/// below that layer) and [images]. Adding a source or layer twice throws as
/// the SDK does; removing a source a layer still uses throws.
/// [reloadStyle] empties the model, as a new style does.
class RecordingPlatform extends ml.MapLibrePlatform {
  final calls = <(String, Object?)>[];

  /// The style's GeoJSON sources and their current data.
  final sources = <String, Map<String, dynamic>>{};

  /// The style's layers, bottom to top.
  final layers = <FakeLayer>[];

  /// The style's images by name.
  final images = <String, Uint8List>{};

  /// The names passed to `addImage`, in order.
  final imageAdds = <String>[];

  /// Held back until completed; consumed by the first addImage call.
  Completer<void>? addImageGate;

  /// Methods that throw once, by name.
  final failOnce = <String>{};

  // Everything not overridden below is not expected to be called.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Iterable<String> get names => calls.map((c) => c.$1);
  Iterable<Object?> argsOf(String name) =>
      calls.where((c) => c.$1 == name).map((c) => c.$2);

  /// The layer ids, bottom to top.
  List<String> get layerIds => [for (final l in layers) l.id];

  /// The layer [id]; fails when it is not in the style.
  FakeLayer layer(String id) => layers.singleWhere((l) => l.id == id);

  /// Drops the style's sources, layers and images, as a new style does.
  void reloadStyle() {
    sources.clear();
    layers.clear();
    images.clear();
  }

  /// Sends a feature tap as the SDK reports one: the feature's [id] (as the
  /// SDK has it, null without one) on [layerId].
  void tapFeature(String layerId, {Object? id}) => onFeatureTappedPlatform({
    'id': id,
    'point': const Point<double>(0, 0),
    'latLng': const ml.LatLng(0, 0),
    'layerId': layerId,
  });

  Future<void> _record(String name, Object? arg) async {
    calls.add((name, arg));
    if (failOnce.remove(name)) throw StateError('$name failed');
  }

  void _addLayer(
    String kind,
    String sourceId,
    String layerId,
    Map<String, dynamic> properties,
    String? belowLayerId,
    bool enableInteraction,
  ) {
    if (layers.any((l) => l.id == layerId)) {
      throw PlatformException(code: 'layerAlreadyExists');
    }
    final layer = (
      kind: kind,
      id: layerId,
      source: sourceId,
      below: belowLayerId,
      interactive: enableInteraction,
      properties: properties,
    );
    final at = layers.indexWhere((l) => l.id == belowLayerId);
    if (at < 0) {
      layers.add(layer);
    } else {
      layers.insert(at, layer);
    }
  }

  bool _viewCreated = false;

  /// The creation params of each `buildView`.
  final creationParams = <Map<String, dynamic>>[];

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    ml.OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    calls.add(('buildView', creationParams['styleString']));
    this.creationParams.add(creationParams);
    if (!_viewCreated) {
      _viewCreated = true;
      scheduleMicrotask(() => onPlatformViewCreated(1));
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<ml.CameraPosition?> updateMapOptions(
    Map<String, dynamic> optionsUpdate,
  ) async {
    await _record('updateMapOptions', optionsUpdate);
    return null;
  }

  @override
  Future<void> updateContentInsets(EdgeInsets insets, bool animated) =>
      _record('updateContentInsets', insets);

  @override
  Future<void> addImage(
    String name,
    Uint8List bytes, [
    bool sdf = false,
  ]) async {
    final gate = addImageGate;
    addImageGate = null;
    await _record('addImage', bytes);
    imageAdds.add(name);
    images[name] = bytes;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson, {
    String? promoteId,
  }) async {
    await _record('addGeoJsonSource', sourceId);
    if (sources.containsKey(sourceId)) {
      throw PlatformException(code: 'sourceAlreadyExists');
    }
    sources[sourceId] = geojson;
  }

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    await _record('setGeoJsonSource', (sourceId, geojson));
    if (!sources.containsKey(sourceId)) {
      throw PlatformException(code: 'sourceNotFound');
    }
    sources[sourceId] = geojson;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _record('removeSource', sourceId);
    if (layers.any((l) => l.source == sourceId)) {
      throw StateError('source $sourceId is in use');
    }
    sources.remove(sourceId);
  }

  @override
  Future<void> addLineLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    await _record('addLineLayer', (layerId, properties));
    _addLayer(
      'line',
      sourceId,
      layerId,
      properties,
      belowLayerId,
      enableInteraction,
    );
  }

  @override
  Future<void> setLayerProperties(
    String layerId,
    Map<String, dynamic> properties,
  ) => _record('setLayerProperties', (layerId, properties));

  @override
  Future<void> addSymbolLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    await _record('addSymbolLayer', properties);
    _addLayer(
      'symbol',
      sourceId,
      layerId,
      properties,
      belowLayerId,
      enableInteraction,
    );
  }

  @override
  Future<void> removeLayer(String layerId) async {
    await _record('removeLayer', layerId);
    layers.removeWhere((l) => l.id == layerId);
  }

  @override
  Future<bool?> moveCamera(ml.CameraUpdate cameraUpdate) async {
    await _record('moveCamera', cameraUpdate);
    return true;
  }

  @override
  Future<bool?> animateCamera(
    ml.CameraUpdate cameraUpdate, {
    Duration? duration,
  }) async {
    await _record('animateCamera', cameraUpdate);
    return true;
  }
}

/// A controller on [platform], without annotation managers.
ml.MapLibreMapController controllerOn(RecordingPlatform platform) =>
    ml.MapLibreMapController(
      maplibrePlatform: platform,
      annotationOrder: const [],
      annotationConsumeTapEvents: const [],
    );

/// Makes `MapLibreMap` use [platform] until the end of the test.
void installRecordingPlatform(RecordingPlatform platform) {
  final previous = ml.MapLibrePlatform.createInstance;
  ml.MapLibrePlatform.createInstance = () => platform;
  addTearDown(() => ml.MapLibrePlatform.createInstance = previous);
}
