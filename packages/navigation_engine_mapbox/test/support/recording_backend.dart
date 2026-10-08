// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:navigation_engine_mapbox/src/mapbox_navigation_map.dart' as mba;

/// A layer of the fake style: the layer and the id it was last moved below
/// (null when it was only added, on top).
typedef FakeLayer = ({mb.Layer layer, String? below});

/// A backend that records what the adapter sends and can be told to fail
/// or to hold a call back.
///
/// It also keeps a small model of the style: [sources] with their (decoded)
/// data, [layers] bottom to top (a layer is added on top; `moveLayer` puts
/// it right below another), [images] and the import [config]. Adding a source or layer
/// twice fails the way the native SDK does; so do removing or updating
/// something that is not there, and removing a source a layer still uses.
/// [resetStyle] empties the model, as a new style does. The tap
/// interactions ([taps]) belong to the map, not the style: they stay.
class RecordingBackend implements mba.MapboxBackend {
  final calls = <(String, Object?)>[];

  /// The style's GeoJSON sources and their current data.
  final sources = <String, Object?>{};

  /// The style's layers, bottom to top.
  final layers = <FakeLayer>[];

  /// The style's images by id: their scale and image.
  final images = <String, (double, mb.StyleImage)>{};

  /// The ids passed to `addImage`, in order.
  final imageAdds = <String>[];

  /// The style import config properties, by (import, property).
  final config = <(String, String), Object>{};

  /// The tap interactions, by layer id.
  final taps = <String, mba.FeatureTap>{};

  /// Held back until completed; consumed by the first addImage call.
  Completer<void>? get addImageGate => _addImageGate;
  set addImageGate(Completer<void>? gate) {
    _addImageGate = gate;
    _gateReached = Completer<void>();
  }

  Completer<void>? _addImageGate;
  Completer<void> _gateReached = Completer<void>();

  /// Completes when an addImage call takes the [addImageGate] (it is held
  /// back from then on): a signal to wait on instead of polling.
  Future<void> get addImageGateReached => _gateReached.future;

  /// Methods that throw once, by name.
  final failOnce = <String>{};

  /// A layer id whose add throws once (before the layer is added).
  String? failLayerOnce;

  /// A layer id whose move throws once (the layer stays where it is).
  String? failMoveOf;

  /// A new style: the sources, layers, images and config so far are gone.
  void resetStyle() {
    sources.clear();
    layers.clear();
    images.clear();
    config.clear();
  }

  Iterable<String> get names => calls.map((c) => c.$1);
  Iterable<Object?> argsOf(String name) =>
      calls.where((c) => c.$1 == name).map((c) => c.$2);

  /// The layer ids, bottom to top.
  List<String> get layerIds => [for (final l in layers) l.layer.id];

  /// The layer [id]; fails when it is not in the style.
  FakeLayer layer(String id) => layers.singleWhere((l) => l.layer.id == id);

  /// A tap on a feature of [layerId] with [id] and [properties], as the SDK
  /// reports one: only to an interaction on that layer, and only while the
  /// layer is in the style (otherwise nothing is rendered there).
  void tapFeature(
    String layerId, {
    String? id,
    Map<String, Object?> properties = const {},
  }) {
    final onTap = taps[layerId];
    if (onTap == null || !layerIds.contains(layerId)) return;
    onTap(id, properties);
  }

  Never _fail(String message) =>
      throw PlatformException(code: 'Throwable', message: message);

  Future<void> _record(String name, Object? arg) async {
    calls.add((name, arg));
    await Future<void>.delayed(Duration.zero);
    if (failOnce.remove(name)) _fail('$name failed');
  }

  @override
  Future<void> updateCompass(mb.CompassSettings settings) =>
      _record('updateCompass', settings);

  @override
  Future<void> updateScaleBar(mb.ScaleBarSettings settings) =>
      _record('updateScaleBar', settings);

  @override
  Future<void> updateLogo(mb.LogoSettings settings) =>
      _record('updateLogo', settings);

  @override
  Future<void> updateAttribution(mb.AttributionSettings settings) =>
      _record('updateAttribution', settings);

  final _imageWaiters = <String, Completer<void>>{};

  /// Completes once the image [imageId] is in the style (at once if it is),
  /// or with the error of an addImage of it that fails.
  Future<void> imageAdded(String imageId) {
    if (images.containsKey(imageId)) return Future.value();
    return (_imageWaiters[imageId] ??= Completer<void>()).future;
  }

  @override
  Future<void> addImage(
    String imageId,
    double scale,
    mb.StyleImage image,
  ) async {
    final gate = _addImageGate;
    _addImageGate = null;
    try {
      await _record('addImage', (imageId, scale, image));
    } catch (e, st) {
      _imageWaiters.remove(imageId)?.completeError(e, st);
      rethrow;
    }
    imageAdds.add(imageId);
    images[imageId] = (scale, image);
    _imageWaiters.remove(imageId)?.complete();
    if (gate != null) {
      if (!_gateReached.isCompleted) _gateReached.complete();
      await gate.future;
    }
  }

  @override
  Future<void> removeImage(String imageId) async {
    await _record('removeImage', imageId);
    images.remove(imageId);
  }

  @override
  Future<void> addGeoJsonSource(String sourceId, String data) async {
    await _record('addGeoJsonSource', sourceId);
    if (sources.containsKey(sourceId)) {
      _fail('Source $sourceId already exists.');
    }
    sources[sourceId] = jsonDecode(data);
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _record('removeSource', sourceId);
    if (!sources.containsKey(sourceId)) _fail('Source $sourceId not found.');
    if (layers.any((l) => _sourceOf(l.layer) == sourceId)) {
      _fail('Source $sourceId is in use.');
    }
    sources.remove(sourceId);
  }

  static String? _sourceOf(mb.Layer layer) => switch (layer) {
    mb.LineLayer(:final sourceId) => sourceId,
    mb.SymbolLayer(:final sourceId) => sourceId,
    _ => null,
  };

  @override
  Future<void> addLayer(mb.Layer layer) async {
    await _record('addLayer', layer);
    if (layer.id == failLayerOnce) {
      failLayerOnce = null;
      _fail('layer failed');
    }
    if (layerIds.contains(layer.id)) {
      _fail('Layer ${layer.id} already exists.');
    }
    layers.add((layer: layer, below: null));
  }

  @override
  Future<void> moveLayer(String layerId, {required String below}) async {
    await _record('moveLayer', (layerId, below));
    if (layerId == failMoveOf) {
      failMoveOf = null;
      _fail('move of $layerId failed');
    }
    final from = layerIds.indexOf(layerId);
    if (from < 0) _fail('Layer $layerId not found.');
    if (!layerIds.contains(below)) _fail('Layer $below not found.');
    final moved = layers.removeAt(from);
    layers.insert(layerIds.indexOf(below), (layer: moved.layer, below: below));
  }

  @override
  Future<void> updateLayer(mb.Layer layer) async {
    await _record('updateLayer', layer);
    final at = layerIds.indexOf(layer.id);
    if (at < 0) _fail('Layer ${layer.id} not found.');
    layers[at] = (layer: layer, below: layers[at].below);
  }

  @override
  Future<void> removeLayer(String layerId) async {
    await _record('removeLayer', layerId);
    final at = layerIds.indexOf(layerId);
    if (at < 0) _fail('Layer $layerId not found.');
    layers.removeAt(at);
  }

  @override
  Future<bool> styleSourceExists(String sourceId) async {
    await _record('styleSourceExists', sourceId);
    return sources.containsKey(sourceId);
  }

  @override
  Future<bool> styleLayerExists(String layerId) async {
    await _record('styleLayerExists', layerId);
    return layerIds.contains(layerId);
  }

  @override
  Future<void> setStyleSourceProperty(
    String sourceId,
    String property,
    Object value,
  ) async {
    await _record('setStyleSourceProperty', (sourceId, property, value));
    if (!sources.containsKey(sourceId)) _fail('Source $sourceId not found.');
    if (property == 'data') sources[sourceId] = jsonDecode(value as String);
  }

  @override
  Future<void> setStyleImportConfigProperty(
    String importId,
    String property,
    Object value,
  ) async {
    await _record('setStyleImportConfigProperty', (importId, property, value));
    config[(importId, property)] = value;
  }

  @override
  void addTapInteraction(String layerId, mba.FeatureTap onTap) {
    calls.add(('addTapInteraction', layerId));
    taps[layerId] = onTap;
  }

  @override
  Future<void> loadStyleURI(String uri) => _record('loadStyleURI', uri);

  @override
  Future<void> setCamera(mb.CameraOptions options) =>
      _record('setCamera', options);

  @override
  Future<void> easeTo(mb.CameraOptions options) => _record('easeTo', options);
}
