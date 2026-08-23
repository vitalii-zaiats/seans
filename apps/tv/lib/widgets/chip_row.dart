import 'package:flutter/material.dart';

import '../theme/nocturne.dart';
import 'focusable.dart';

/// One horizontally scrolling row of chips.
///
/// `Clip.none` matters: a focused chip is outlined, and a clipping viewport
/// would shave the ring off the one at either end.
class TvChipRow extends StatelessWidget {
  const TvChipRow({
    required this.itemCount,
    required this.builder,
    this.padding,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) builder;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.px(56),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(width: context.px(10)),
        itemBuilder: builder,
      ),
    );
  }
}

/// The one chip shape in the app: seasons, episodes and voice-overs all use it.
class TvChip extends StatefulWidget {
  const TvChip({
    required this.label,
    required this.onSelect,
    this.selected = false,
    this.enabled = true,
    this.autofocus = false,
    this.hint,
    this.swatch,
    super.key,
  });

  final String label;
  final VoidCallback onSelect;
  final bool selected;
  final bool enabled;
  final bool autofocus;

  /// A colour this chip stands for, drawn as a dot before the label.
  final Color? swatch;

  /// Small trailing note, e.g. why the chip is inert.
  final String? hint;

  @override
  State<TvChip> createState() => _TvChipState();
}

class _TvChipState extends State<TvChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    // No `alignment` on the Container: giving one makes it expand to the
    // largest size its constraints allow, and every chip would come out the
    // same width instead of hugging its label.
    final body = Container(
      padding: EdgeInsets.symmetric(horizontal: context.px(18)),
      constraints: BoxConstraints(maxWidth: context.px(420)),
      decoration: BoxDecoration(
        color: widget.selected ? context.accentTint : context.surface,
        border: Border.all(
          color: active ? context.accent : Nocturne.neutral800,
          width: context.px(1),
        ),
        borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.swatch != null) ...[
            Container(
              width: context.px(16),
              height: context.px(16),
              decoration: BoxDecoration(
                color: widget.swatch,
                shape: BoxShape.circle,
                // A dark ground swatch would vanish without an edge.
                border: Border.all(
                  color: Nocturne.neutral700,
                  width: context.px(1),
                ),
              ),
            ),
            SizedBox(width: context.px(10)),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.sp(17),
                color: active ? Nocturne.text : Nocturne.neutral400,
              ),
            ),
          ),
          if (widget.hint != null) ...[
            SizedBox(width: context.px(8)),
            Text(
              widget.hint!,
              style: TextStyle(
                fontSize: context.sp(13),
                color: Nocturne.neutral700,
              ),
            ),
          ],
        ],
      ),
    );

    // Disabled controls drop to 45% opacity — the design system's own rule.
    if (!widget.enabled) return Opacity(opacity: 0.45, child: body);

    return Focusable(
      autofocus: widget.autofocus,
      // Chips must not grow: a shifting chip is one you press by mistake.
      scaleOnFocus: 1,
      glow: false,
      onSelect: widget.onSelect,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) revealOnFocus(context);
      },
      child: body,
    );
  }
}

/// The small caps label above a chip row.
class TvChipRowLabel extends StatelessWidget {
  const TvChipRowLabel({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: context.sp(13),
      letterSpacing: context.px(3),
      color: context.accent,
    ),
  );
}
