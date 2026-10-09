import 'package:flutter/widgets.dart';

/// A column of round map buttons on the end side: [children], end-aligned,
/// [gap] apart. Given a bounded height it shows only as many as fit,
/// dropping them from the bottom up, or by [priorities] (the lowest first)
/// when given; those it keeps stay in their order. When not even the first
/// fits, it shows nothing (an empty box of that height), so it never
/// overlaps what lies around it and never overflows.
///
/// It decides from its constraints during layout, so it cannot sit in a
/// parent that asks for its intrinsic size (such as `IntrinsicHeight`).
class GoogleStyleControlStack extends StatelessWidget {
  /// Creates a stack of [children], each [itemExtent] high.
  const GoogleStyleControlStack({
    super.key,
    required this.children,
    this.gap = 12,
    this.itemExtent = 48,
    this.priorities,
  });

  /// The buttons, top first.
  final List<Widget> children;

  /// The space between two buttons.
  final double gap;

  /// The height of one button.
  final double itemExtent;

  /// How long each child stays when not all fit, one per child: the lowest
  /// goes first. Null drops them from the bottom up.
  final List<int>? priorities;

  /// The indices of the children kept when only [fit] of [count] fit, in
  /// their order: the first [fit] without [priorities], else the [fit]
  /// highest priorities (the earlier child on a tie).
  static List<int> keep(int count, int fit, List<int>? priorities) {
    if (fit >= count) return List.generate(count, (i) => i);
    if (fit <= 0) return const [];
    if (priorities == null) return List.generate(fit, (i) => i);
    final order = List.generate(count, (i) => i)
      ..sort((a, b) {
        final byRank = priorities[b].compareTo(priorities[a]);
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return order.take(fit).toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      priorities == null || priorities!.length == children.length,
      'priorities needs one entry per child',
    );
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxHeight;
        final fit = max.isInfinite
            ? children.length
            : ((max + gap) / (itemExtent + gap)).floor();
        if (fit < 1) return SizedBox(height: max);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: gap,
          children: [
            for (final i in keep(children.length, fit, priorities)) children[i],
          ],
        );
      },
    );
  }
}
