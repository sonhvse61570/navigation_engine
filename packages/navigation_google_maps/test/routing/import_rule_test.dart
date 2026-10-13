@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Routing and search must not depend on the map SDK or Flutter, so they
/// stay usable and testable apart from the map (and compile for the web).
///
/// Every `import`, `export` and `part` directive in the three folders is
/// checked, however many lines it spans, and so is every URI after an `if`
/// in a conditional one. A URI is allowed when it is:
///  - one of the web-safe `dart:` libraries below;
///  - a `package:` URI of the core, `http` or `navigation_osrm`;
///  - a file of the three folders, relative or by this package's own name.
/// Anything else, such as another folder of this package, is an offender.
const _folders = ['lib/src/routing', 'lib/src/search', 'lib/src/web_service'];
const _dartLibraries = {
  'async',
  'collection',
  'convert',
  'core',
  'math',
  'typed_data',
};
const _packages = {'navigation_engine', 'http', 'navigation_osrm'};

// Strings are matched too, so that `//` inside a URI is not a comment.
final _commentOrString = RegExp(
  r'''/\*[\s\S]*?\*/|//[^\n]*|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"''',
);
final _directive = RegExp(
  r'''^[ \t]*(?:import|export|part)\s+(['"])([^'"\n]*)\1([^;]*);''',
  multiLine: true,
);
final _conditionalUri = RegExp(r'''\bif\s*\([^)]*\)\s*(['"])([^'"\n]*)\1''');

String _stripComments(String source) => source.replaceAllMapped(
  _commentOrString,
  (m) => m[0]!.startsWith('/') ? ' ' : m[0]!,
);

/// The URIs of every directive in [source] (the file at [path]) that break
/// the rule, as `uri (reason)`. [packageName] is this package's own name.
List<String> offendingUris(String source, String path, String packageName) {
  final here = Directory.current.absolute.uri;
  final allowedDirs = [for (final f in _folders) here.resolve('$f/').path];
  final from = Uri.file(File(path).absolute.path);

  String? check(String uri) {
    if (uri.startsWith('dart:')) {
      return _dartLibraries.contains(uri.substring(5))
          ? null
          : 'a dart: library that is not web-safe pure Dart';
    }
    Uri target;
    if (uri.startsWith('package:')) {
      final rest = uri.substring(8);
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      if (_packages.contains(name)) return null;
      if (name != packageName || slash < 0) {
        return 'a package that is not allowed';
      }
      target = here.resolve('lib/${rest.substring(slash + 1)}');
    } else if (uri.contains(':')) {
      return 'a URI scheme that is not allowed';
    } else {
      target = from.resolve(uri);
    }
    return allowedDirs.any(target.path.startsWith)
        ? null
        : 'outside lib/src/routing, search and web_service';
  }

  final offenders = <String>[];
  for (final m in _directive.allMatches(_stripComments(source))) {
    final uris = [
      m[2]!,
      for (final c in _conditionalUri.allMatches(m[3]!)) c[2]!,
    ];
    for (final uri in uris) {
      final why = check(uri);
      if (why != null) offenders.add("$uri ($why)");
    }
  }
  return offenders;
}

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final packageName = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)![1]!;

  test('routing, search and web_service import no map SDK or Flutter', () {
    final offenders = <String>[];
    for (final folder in _folders) {
      final dir = Directory(folder);
      expect(dir.existsSync(), isTrue, reason: '$folder is missing');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final bad in offendingUris(
          f.readAsStringSync(),
          f.path,
          packageName,
        )) {
          offenders.add('${f.path}: $bad');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  group('the rule', () {
    List<String> check(String source) =>
        offendingUris(source, 'lib/src/routing/x.dart', packageName);

    test('allows what the moved code uses', () {
      expect(
        check('''
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:navigation_engine/navigation_engine.dart' show GeoPoint;
import 'package:navigation_osrm/navigation_osrm.dart';
import '../web_service/google_http.dart';
import 'maneuvers.dart';
export 'package:$packageName/src/search/google_places_search.dart';
// import 'package:flutter/material.dart';
/* export 'dart:ui'; */
const url = 'https://example.com/a'; // import 'dart:io';
'''),
        isEmpty,
      );
    });

    test('catches every kind of directive, on one line or several', () {
      expect(check("export 'package:flutter/foundation.dart';"), hasLength(1));
      expect(
        check("part '../ui/night_map_style.dart';"),
        hasLength(1),
        reason: 'part',
      );
      expect(
        check('''
export
    'package:flutter/foundation.dart'
    show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart'
    as gm;
'''),
        hasLength(2),
      );
    });

    test('catches every URI of a conditional import', () {
      expect(
        check('''
import 'dart:async'
    if (dart.library.io) 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.js_interop) 'package:http/http.dart';
'''),
        hasLength(1),
      );
    });

    test('keeps relative URIs inside the three folders', () {
      expect(
        check("import '../google_maps_navigation_map.dart';"),
        hasLength(1),
      );
      expect(
        check("import '../ui/google_style_navigation.dart';"),
        hasLength(1),
      );
      expect(
        check("import '../../navigation_google_maps.dart';"),
        hasLength(1),
      );
      expect(
        check("import 'package:$packageName/src/ui/night_map_style.dart';"),
        hasLength(1),
      );
      expect(check("import '../search/google_places_search.dart';"), isEmpty);
    });

    test('allows only web-safe dart: libraries', () {
      for (final lib in ['ui', 'io', 'html', 'js_interop', 'isolate']) {
        expect(check("import 'dart:$lib';"), hasLength(1), reason: lib);
      }
      for (final lib in _dartLibraries) {
        expect(check("import 'dart:$lib';"), isEmpty, reason: lib);
      }
    });
  });
}
