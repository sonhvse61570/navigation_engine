import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

import 'audio_guidance.dart';
import 'google_style_colors.dart';
import 'google_style_round_button.dart';

/// The 3-state sound button of the navigation screen: a round button with
/// the icon of [value]. A tap opens a pill on its start side with the three
/// [AudioGuidance] options, the current one filled with
/// [GoogleStyleColors.selectedTint]. A choice calls [onChanged] and closes
/// the pill, as does a tap on the button, the system back, or
/// [collapseAfter] without a choice, or [canOpen] turning false;
/// [onOpenChanged] hears each change. The app owns the audio and passes the
/// [value] back.
///
/// These keys are stable test hooks: `google_style_sound_pill`,
/// `google_style_sound_option_<name>` and `google_style_alerts_only_icon`.
class GoogleStyleSoundButton extends StatefulWidget {
  /// Creates the sound button showing [value].
  const GoogleStyleSoundButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.strings = const NavigationStrings(),
    this.colors = GoogleStyleColors.day,
    this.collapseAfter = const Duration(seconds: 4),
    this.onOpenChanged,
    this.canOpen = true,
  });

  /// Whether the pill may open. While false, a tap on the button does not
  /// open it, and an open pill closes ([onOpenChanged] then hears false
  /// after the frame). The drop-in sets it false while its trip sheet is
  /// not collapsed, so the button stays in its column, fading, without a
  /// pill that would keep the system back for itself.
  final bool canOpen;

  /// The current audio state.
  final AudioGuidance value;

  /// Called with the option chosen in the pill.
  final ValueChanged<AudioGuidance> onChanged;

  /// The words of the button: [NavigationStrings.sound],
  /// [NavigationStrings.alertsOnly] and [NavigationStrings.muted].
  final NavigationStrings strings;

  /// The colours of the button.
  final GoogleStyleColors colors;

  /// How long the pill stays open without a choice.
  final Duration collapseAfter;

  /// Called when the pill opens (true) or closes (false). When the button
  /// is disposed with the pill open, it is called with false after the
  /// frame, once the button is gone: check that the host is still mounted.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<GoogleStyleSoundButton> createState() => _GoogleStyleSoundButtonState();
}

class _GoogleStyleSoundButtonState extends State<GoogleStyleSoundButton> {
  bool _open = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    final notify = widget.onOpenChanged;
    // Not during teardown: the host may rebuild with it.
    if (_open && notify != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notify(false));
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(GoogleStyleSoundButton old) {
    super.didUpdateWidget(old);
    if (!widget.canOpen && _open) {
      // During the host's build: tell it after the frame.
      _timer?.cancel();
      _timer = null;
      _open = false;
      final notify = widget.onOpenChanged;
      if (notify != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => notify(false));
      }
    }
  }

  void _expand() {
    if (!widget.canOpen) return;
    _timer?.cancel();
    _timer = Timer(widget.collapseAfter, _collapse);
    if (_open) return;
    setState(() => _open = true);
    widget.onOpenChanged?.call(true);
  }

  void _collapse() {
    _timer?.cancel();
    _timer = null;
    if (!mounted || !_open) return;
    setState(() => _open = false);
    widget.onOpenChanged?.call(false);
  }

  void _choose(AudioGuidance value) {
    _collapse();
    widget.onChanged(value);
  }

  String _label(AudioGuidance value) => switch (value) {
    AudioGuidance.sound => widget.strings.sound,
    AudioGuidance.alertsOnly => widget.strings.alertsOnly,
    AudioGuidance.muted => widget.strings.muted,
  };

  static Widget _icon(AudioGuidance value) => switch (value) {
    AudioGuidance.sound => const Icon(Icons.volume_up),
    AudioGuidance.alertsOnly => const _AlertsOnlyIcon(),
    AudioGuidance.muted => const Icon(Icons.volume_off),
  };

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final button = GoogleStyleRoundButton(
      icon: _icon(widget.value),
      tooltip: _label(widget.value),
      onPressed: _open ? _collapse : _expand,
      colors: colors,
    );
    // The system back closes the pill before it leaves the screen.
    return PopScope<Object?>(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _collapse();
      },
      child: _open ? _pill(button, colors) : button,
    );
  }

  Widget _pill(Widget button, GoogleStyleColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          key: const ValueKey('google_style_sound_pill'),
          color: colors.buttonSurface,
          // As the round buttons: elevation 1, a 1 dp ring, 52 high.
          elevation: 1,
          shape: StadiumBorder(side: BorderSide(color: colors.outline)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in AudioGuidance.values)
                  _option(option, colors),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        button,
      ],
    );
  }

  Widget _option(AudioGuidance option, GoogleStyleColors colors) {
    final selected = option == widget.value;
    return Semantics(
      button: true,
      selected: selected,
      label: _label(option),
      child: InkResponse(
        key: ValueKey('google_style_sound_option_${option.name}'),
        onTap: () => _choose(option),
        child: SizedBox.square(
          dimension: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.selectedTint : const Color(0x00000000),
            ),
            child: Center(
              child: IconTheme(
                data: IconThemeData(
                  size: 24,
                  color: selected ? colors.accent : colors.buttonIcon,
                ),
                child: ExcludeSemantics(child: _icon(option)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A speaker with an alert badge, in the ambient icon colour: the
/// alerts-only state.
class _AlertsOnlyIcon extends StatelessWidget {
  const _AlertsOnlyIcon();

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return CustomPaint(
      key: const ValueKey('google_style_alerts_only_icon'),
      size: Size.square(size),
      painter: _AlertsOnlyPainter(theme.color ?? const Color(0xFF3C4043)),
    );
  }
}

class _AlertsOnlyPainter extends CustomPainter {
  const _AlertsOnlyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final fill = Paint()..color = color;
    // The speaker: a box and a cone, on the left two thirds.
    canvas.drawPath(
      Path()
        ..moveTo(3 * s, 9 * s)
        ..lineTo(7 * s, 9 * s)
        ..lineTo(12 * s, 4 * s)
        ..lineTo(12 * s, 20 * s)
        ..lineTo(7 * s, 15 * s)
        ..lineTo(3 * s, 15 * s)
        ..close(),
      fill,
    );
    // The badge: an exclamation mark on the right.
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(17 * s, 5 * s, 3 * s, 9 * s),
          Radius.circular(1.5 * s),
        ),
        fill,
      )
      ..drawCircle(Offset(18.5 * s, 17.5 * s), 1.7 * s, fill);
  }

  @override
  bool shouldRepaint(_AlertsOnlyPainter old) => old.color != color;
}
