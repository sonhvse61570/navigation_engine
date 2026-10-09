import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

class _Mph extends EnglishGuidanceFormatter {
  const _Mph();
  @override
  String speedValue(double metresPerSecond) =>
      (metresPerSecond * 2.236936).round().toString();
  @override
  String get speedUnit => 'mph';
}

SpeedInfo _kmh(double speed, [double? limit]) =>
    SpeedInfo(speed: speed / 3.6, limit: limit == null ? null : limit / 3.6);
SpeedInfo _mph(double speed, double limit) =>
    SpeedInfo(speed: speed / 2.236936, limit: limit / 2.236936);

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: app!,
  ),
  home: Scaffold(body: Center(child: child)),
);

const _speedometer = ValueKey('google_style_speedometer');
const _value = ValueKey('google_style_speed_value');
const _limit = ValueKey('google_style_speed_limit');
const _cluster = ValueKey('google_style_speed_cluster');

void main() {
  const en = EnglishGuidanceFormatter();
  SpeedingLevel level(
    SpeedInfo i, {
    GuidanceFormatter f = en,
    double? minor,
    double? major,
  }) => GoogleStyleSpeedCluster.speedingLevel(i, f, minor: minor, major: major);

  group('speedingLevel', () {
    test('km/h: minor from 10 over, major from 20 over', () {
      expect(level(_kmh(59.5, 50)), SpeedingLevel.none);
      expect(level(_kmh(60.5, 50)), SpeedingLevel.minor);
      expect(level(_kmh(69.5, 50)), SpeedingLevel.minor);
      expect(level(_kmh(70.5, 50)), SpeedingLevel.major);
      expect(level(_kmh(130)), SpeedingLevel.none, reason: 'no limit');
    });

    test('mph formatter: minor from 5 over, major from 10 over', () {
      const f = _Mph();
      expect(level(_mph(34.5, 30), f: f), SpeedingLevel.none);
      expect(level(_mph(35.5, 30), f: f), SpeedingLevel.minor);
      expect(level(_mph(40.5, 30), f: f), SpeedingLevel.major);
    });

    test('custom thresholds, in the formatter unit', () {
      expect(level(_kmh(52.5, 50), minor: 3, major: 6), SpeedingLevel.none);
      expect(level(_kmh(53.5, 50), minor: 3, major: 6), SpeedingLevel.minor);
      expect(level(_kmh(56.5, 50), minor: 3, major: 6), SpeedingLevel.major);
    });
  });

  group('exactly at a threshold', () {
    test('km/h: +10 is minor and +20 is major for every integer limit', () {
      for (var limit = 5; limit <= 130; limit++) {
        expect(
          level(_kmh(limit + 10.0, limit.toDouble())),
          SpeedingLevel.minor,
          reason: 'limit $limit, +10',
        );
        expect(
          level(_kmh(limit + 20.0, limit.toDouble())),
          SpeedingLevel.major,
          reason: 'limit $limit, +20',
        );
      }
    });

    test('mph: +5 is minor and +10 is major for every integer limit', () {
      const f = _Mph();
      for (var limit = 5; limit <= 80; limit++) {
        expect(
          level(_mph(limit + 5.0, limit.toDouble()), f: f),
          SpeedingLevel.minor,
          reason: 'limit $limit, +5',
        );
        expect(
          level(_mph(limit + 10.0, limit.toDouble()), f: f),
          SpeedingLevel.major,
          reason: 'limit $limit, +10',
        );
      }
    });

    test('custom thresholds hold exactly too', () {
      for (var limit = 5; limit <= 130; limit++) {
        expect(
          level(_kmh(limit + 3.0, limit.toDouble()), minor: 3, major: 6),
          SpeedingLevel.minor,
          reason: 'limit $limit, +3',
        );
        expect(
          level(_kmh(limit + 6.0, limit.toDouble()), minor: 3, major: 6),
          SpeedingLevel.major,
          reason: 'limit $limit, +6',
        );
      }
    });

    test('a limit of 0 is no limit', () {
      expect(level(_kmh(130, 0)), SpeedingLevel.none);
    });
  });

  Color textColor(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(_value)).style!.color!;
  Color squareColor(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(_speedometer)).decoration!
              as BoxDecoration)
          .color!;

  testWidgets('the sign and the speedometer joined in one rounded group', (
    tester,
  ) async {
    await tester.pumpWidget(_host(GoogleStyleSpeedCluster(info: _kmh(48, 50))));
    final cluster = tester.widget<Material>(find.byKey(_cluster));
    expect(cluster.borderRadius, BorderRadius.circular(16));
    expect(cluster.color, GoogleStyleColors.day.speedometerSurface);
    expect(tester.getSize(find.byKey(_speedometer)), const Size(56, 56));
    expect(find.text('48'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
    final speed = tester.getRect(find.byKey(_speedometer));
    final sign = tester.getRect(find.byKey(_limit));
    expect(sign.right, lessThanOrEqualTo(speed.left));
    expect(sign.height, greaterThanOrEqualTo(48));
  });

  testWidgets('vienna is a red-ringed circle; us shows SPEED LIMIT', (
    tester,
  ) async {
    await tester.pumpWidget(_host(GoogleStyleSpeedCluster(info: _kmh(48, 50))));
    final circle = tester.widget<Container>(
      find
          .ancestor(of: find.text('50'), matching: find.byType(Container))
          .first,
    );
    final d = circle.decoration! as BoxDecoration;
    expect(d.shape, BoxShape.circle);
    expect((d.border! as Border).top.color, const Color(0xFFD93025));
    expect(find.text('SPEED LIMIT'), findsNothing);
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(
          info: _kmh(48, 50),
          style: SpeedLimitSignStyle.us,
        ),
      ),
    );
    expect(find.text('SPEED LIMIT'), findsOneWidget);
  });

  testWidgets('showLimit: false hides the sign, not the speedometer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(GoogleStyleSpeedCluster(info: _kmh(48, 50), showLimit: false)),
    );
    expect(find.byKey(_limit), findsNothing);
    expect(find.text('50'), findsNothing);
    expect(find.byKey(_speedometer), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
  });

  testWidgets('the us sign keeps its text at the normal size at 2x', (
    tester,
  ) async {
    Future<Size> words(double scale) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedCluster(
            info: _kmh(48, 50),
            style: SpeedLimitSignStyle.us,
          ),
          scale: scale,
        ),
      );
      return tester.getSize(find.text('SPEED LIMIT'));
    }

    final normal = await words(1);
    final large = await words(2);
    expect(large, normal);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('SPEED LIMIT'))),
      TextScaler.noScaling,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('$name speeding colours', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleSpeedCluster(info: _kmh(48, 50), colors: colors)),
      );
      expect(textColor(tester), colors.speedometerText);
      expect(squareColor(tester), colors.speedometerSurface);
      await tester.pumpWidget(
        _host(GoogleStyleSpeedCluster(info: _kmh(62, 50), colors: colors)),
      );
      expect(textColor(tester), colors.speeding, reason: 'minor');
      expect(squareColor(tester), colors.speedometerSurface);
      await tester.pumpWidget(
        _host(GoogleStyleSpeedCluster(info: _kmh(75, 50), colors: colors)),
      );
      expect(textColor(tester), const Color(0xFFFFFFFF), reason: 'major');
      expect(squareColor(tester), colors.speeding);
    });
  }

  testWidgets('night: a #202124 surface with white text', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(
          info: _kmh(48, 50),
          colors: GoogleStyleColors.night,
        ),
      ),
    );
    expect(squareColor(tester), const Color(0xFF202124));
    expect(textColor(tester), const Color(0xFFFFFFFF));
  });

  testWidgets('a tap on the sign calls onLimitTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(info: _kmh(48, 50), onLimitTap: () => taps++),
      ),
    );
    await tester.tap(find.byKey(_limit));
    expect(taps, 1);
  });

  testWidgets('the sign keeps its tap action for assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(info: _kmh(48, 50), onLimitTap: () => taps++),
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('SPEED LIMIT 50 km/h'));
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a limit of 0 draws no sign', (tester) async {
    await tester.pumpWidget(_host(GoogleStyleSpeedCluster(info: _kmh(48, 0))));
    expect(find.byKey(_limit), findsNothing);
    expect(find.byKey(_speedometer), findsOneWidget);
  });

  testWidgets('the speedometer is announced with its speed and unit', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(GoogleStyleSpeedCluster(info: _kmh(48, 50))));
    expect(find.bySemanticsLabel('48 km/h'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('speedometerVisible: false hides the speedometer, not the '
      'sign; without a limit the speedometer stays', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(info: _kmh(48, 50), speedometerVisible: false),
      ),
    );
    expect(find.byKey(_speedometer), findsNothing);
    expect(find.byKey(_limit), findsOneWidget);
    await tester.pumpWidget(
      _host(GoogleStyleSpeedCluster(info: _kmh(48), speedometerVisible: false)),
    );
    expect(find.byKey(_speedometer), findsOneWidget);
  });

  testWidgets('nothing to show: no size', (tester) async {
    await tester.pumpWidget(
      _host(GoogleStyleSpeedCluster(info: _kmh(48), showSpeed: false)),
    );
    expect(tester.getSize(find.byType(GoogleStyleSpeedCluster)), Size.zero);
  });

  testWidgets('speeds and the unit go through the formatter', (tester) async {
    await tester.pumpWidget(
      _host(
        GoogleStyleSpeedCluster(info: _mph(36, 30), formatter: const _Mph()),
      ),
    );
    expect(find.text('mph'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(textColor(tester), GoogleStyleColors.day.speeding, reason: '6 over');
  });

  testWidgets('2x text at 320 dp, both signs, 3-digit speeds: no overflow', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final style in SpeedLimitSignStyle.values) {
      await tester.pumpWidget(
        _host(
          GoogleStyleSpeedCluster(
            info: _kmh(135, 120),
            style: style,
            strings: const NavigationStrings.vietnamese(),
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull, reason: '$style');
      expect(find.text('135'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    }
  });

  for (final (name, colors) in [
    ('day', GoogleStyleColors.day),
    ('night', GoogleStyleColors.night),
  ]) {
    testWidgets('Re-center pill, $name colours, 48 dp high', (tester) async {
      await tester.pumpWidget(
        _host(GoogleStyleRecenterButton(onPressed: () {}, colors: colors)),
      );
      final button = tester.widget<FilledButton>(
        find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(button.style!.backgroundColor!.resolve({}), colors.buttonSurface);
      expect(button.style!.foregroundColor!.resolve({}), colors.accent);
      expect(
        tester.getSize(find.byWidgetPredicate((w) => w is FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  }
}
