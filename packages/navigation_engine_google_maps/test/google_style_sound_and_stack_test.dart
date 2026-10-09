import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_google_maps/navigation_engine_google_maps.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Align(alignment: AlignmentDirectional.topEnd, child: child),
      ),
    );

const _pill = ValueKey('google_style_sound_pill');
Key _option(AudioGuidance a) => ValueKey('google_style_sound_option_${a.name}');

void main() {
  const strings = NavigationStrings();

  group('GoogleStyleSoundButton', () {
    for (final (value, label, icon) in [
      (AudioGuidance.sound, strings.sound, find.byIcon(Icons.volume_up)),
      (
        AudioGuidance.alertsOnly,
        strings.alertsOnly,
        find.byKey(const ValueKey('google_style_alerts_only_icon')),
      ),
      (AudioGuidance.muted, strings.muted, find.byIcon(Icons.volume_off)),
    ]) {
      testWidgets('${value.name}: its own icon and label', (tester) async {
        await tester.pumpWidget(
          _host(GoogleStyleSoundButton(value: value, onChanged: (_) {})),
        );
        expect(icon, findsOneWidget);
        expect(find.byTooltip(label), findsOneWidget);
        expect(find.byKey(_pill), findsNothing);
      });
    }

    testWidgets('a tap opens the pill; a choice calls back and closes it', (
      tester,
    ) async {
      final chosen = <AudioGuidance>[];
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(
            value: AudioGuidance.sound,
            onChanged: chosen.add,
          ),
        ),
      );
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump();
      expect(find.byKey(_pill), findsOneWidget);
      for (final a in AudioGuidance.values) {
        expect(tester.getSize(find.byKey(_option(a))), const Size(48, 48));
      }
      final selected =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(_option(AudioGuidance.sound)),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(selected.color, GoogleStyleColors.day.selectedTint);
      await tester.tap(find.byKey(_option(AudioGuidance.alertsOnly)));
      await tester.pump();
      expect(chosen, [AudioGuidance.alertsOnly]);
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('the pill grows to the start side of the button', (
      tester,
    ) async {
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(
          _host(
            GoogleStyleSoundButton(
              value: AudioGuidance.muted,
              onChanged: (_) {},
            ),
            direction: direction,
          ),
        );
        await tester.tap(find.byTooltip(strings.muted));
        await tester.pump();
        final pill = tester.getRect(find.byKey(_pill));
        final button = tester.getRect(find.byTooltip(strings.muted));
        if (direction == TextDirection.ltr) {
          expect(pill.right, lessThanOrEqualTo(button.left));
        } else {
          expect(pill.left, greaterThanOrEqualTo(button.right));
        }
        await tester.tap(find.byTooltip(strings.muted));
        await tester.pump();
        expect(find.byKey(_pill), findsNothing, reason: 'a tap closes it');
      }
    });

    testWidgets('the pill closes by itself after 4 s', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(value: AudioGuidance.sound, onChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.byKey(_pill), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('a second opening starts the 4 s again', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(value: AudioGuidance.sound, onChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump(const Duration(seconds: 3));
      // A tap on the button closes it; a second tap opens it again.
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump();
      expect(find.byKey(_pill), findsNothing);
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(_pill), findsOneWidget, reason: '3 s after reopening');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('a custom collapseAfter', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(
            value: AudioGuidance.sound,
            onChanged: (_) {},
            collapseAfter: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.tap(find.byTooltip(strings.sound));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(_pill), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('each option is a button labelled with its state, the '
        'current one selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(
            value: AudioGuidance.alertsOnly,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byTooltip(strings.alertsOnly));
      await tester.pump();
      for (final (option, label) in [
        (AudioGuidance.sound, strings.sound),
        (AudioGuidance.alertsOnly, strings.alertsOnly),
        (AudioGuidance.muted, strings.muted),
      ]) {
        expect(
          tester.getSemantics(find.byKey(_option(option))),
          matchesSemantics(
            label: label,
            isButton: true,
            hasSelectedState: true,
            isSelected: option == AudioGuidance.alertsOnly,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      }
      handle.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('at ${scale}x text on a 360 dp screen the pill fits and '
          'keeps 48 dp options', (tester) async {
        tester.view
          ..physicalSize = const Size(360, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Align(
              alignment: AlignmentDirectional.topEnd,
              child: GoogleStyleSoundButton(
                value: AudioGuidance.sound,
                onChanged: (_) {},
                strings: const NavigationStrings.vietnamese(),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(GoogleStyleSoundButton));
        await tester.pump();
        final pill = tester.getRect(find.byKey(_pill));
        expect(pill.left, greaterThanOrEqualTo(0));
        for (final a in AudioGuidance.values) {
          expect(tester.getSize(find.byKey(_option(a))), const Size(48, 48));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('night colours; leaving the screen with the pill open is '
        'fine', (tester) async {
      await tester.pumpWidget(
        _host(
          GoogleStyleSoundButton(
            value: AudioGuidance.muted,
            onChanged: (_) {},
            colors: GoogleStyleColors.night,
          ),
        ),
      );
      await tester.tap(find.byTooltip(strings.muted));
      await tester.pump();
      final pill = tester.widget<Material>(find.byKey(_pill));
      expect(pill.color, GoogleStyleColors.night.buttonSurface);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('GoogleStyleControlStack', () {
    List<Widget> buttons(int n) => [
      for (var i = 0; i < n; i++)
        SizedBox(key: ValueKey('b$i'), width: 48, height: 48),
    ];

    Future<void> pumpStack(WidgetTester tester, double? height) =>
        tester.pumpWidget(
          _host(
            height == null
                // A scroll view gives its child an unbounded height.
                ? SingleChildScrollView(
                    child: GoogleStyleControlStack(children: buttons(3)),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: GoogleStyleControlStack(children: buttons(3)),
                  ),
          ),
        );

    testWidgets('unbounded: all, 12 apart, end-aligned', (tester) async {
      await pumpStack(tester, null);
      final b0 = tester.getRect(find.byKey(const ValueKey('b0')));
      final b1 = tester.getRect(find.byKey(const ValueKey('b1')));
      final b2 = tester.getRect(find.byKey(const ValueKey('b2')));
      expect(b1.top, closeTo(b0.bottom + 12, 0.01));
      expect(b2.top, closeTo(b1.bottom + 12, 0.01));
      expect(b0.right, b2.right);
    });

    for (final (height, shown) in [
      (170.0, 3),
      (168.0, 3),
      (167.9, 2),
      (110.0, 2),
      (108.0, 2),
      (107.9, 1),
      (60.0, 1),
      (48.0, 1),
    ]) {
      testWidgets('$height high: the first $shown, from the top', (
        tester,
      ) async {
        await pumpStack(tester, height);
        for (var i = 0; i < 3; i++) {
          expect(
            find.byKey(ValueKey('b$i')),
            i < shown ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('too low even for one: nothing, and no overflow error', (
      tester,
    ) async {
      await pumpStack(tester, 30);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('b0')), findsNothing);
      expect(find.byKey(const ValueKey('b1')), findsNothing);
    });

    testWidgets('no children: nothing', (tester) async {
      await tester.pumpWidget(
        _host(const GoogleStyleControlStack(children: [])),
      );
      expect(tester.getSize(find.byType(GoogleStyleControlStack)), Size.zero);
    });
  });
}
