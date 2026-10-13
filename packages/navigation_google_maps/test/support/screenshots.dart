import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the review screenshots go: the `NAV_SCREENSHOTS` environment
/// variable. When it is not set (the default) the screenshot test is
/// skipped.
String? get screenshotDir => Platform.environment['NAV_SCREENSHOTS'];

/// The key of the [RepaintBoundary] the drop-in harness wraps the app in.
const shotKey = ValueKey('navigation_engine_screenshot');

bool _fontsLoaded = false;

/// Loads Roboto and the Material icons from the Flutter SDK, so screenshots
/// show real text and icons instead of the test font's boxes.
Future<void> loadScreenshotFonts() async {
  if (_fontsLoaded) return;
  final root = Platform.environment['FLUTTER_ROOT'] ?? _flutterRoot();
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String file) async =>
      ByteData.sublistView(await File('$dir/$file').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(read(file));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
  _fontsLoaded = true;
}

/// The Flutter SDK root, from the test runner's path
/// (`<root>/bin/cache/artifacts/engine/<platform>/flutter_tester`).
String _flutterRoot() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}

/// Writes what is under [shotKey] to `<screenshotDir>/<name>.png`, at
/// [pixelRatio] times the logical size.
Future<void> saveScreenshot(
  WidgetTester tester,
  String name, {
  double pixelRatio = 2,
}) async {
  final dir = screenshotDir!;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(shotKey),
    );
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(Uint8List.sublistView(bytes!));
    } finally {
      image.dispose();
    }
  });
}
