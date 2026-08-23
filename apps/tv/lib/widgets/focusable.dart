import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dpad.dart';
import '../core/sfx.dart';
import '../platform/box_for_platform.dart';
import '../theme/nocturne.dart';

/// The one focusable surface in the app.
///
/// A television has no pointer, so focus is the whole of the interface: it says
/// where you are, and OK acts on it. The design gives focus an accent ring and
/// a soft glow rather than a fill, and that glow breathes — a console-style
/// pulse, slow enough to read as "alive" from three metres rather than as
/// something demanding attention.
class Focusable extends StatefulWidget {
  const Focusable({
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.borderRadius,
    this.scaleOnFocus = 1.06,
    this.glow = true,
    this.onSecondary,
    this.cue = SfxCue.tap,
    super.key,
  });

  final Widget child;

  /// OK on the remote, or Enter on a keyboard.
  final VoidCallback onSelect;

  /// A second action on the same tile — starring a channel, say.
  ///
  /// Bound to play/pause and the gamepad's Y, which is what a television
  /// remote has spare. Not every remote carries either, so nothing essential
  /// should live here.
  final VoidCallback? onSecondary;

  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final BorderRadius? borderRadius;

  /// How much the tile grows when focused. `1` for things that must not move —
  /// a row of chips whose neighbours would be pushed around.
  final double scaleOnFocus;

  final bool glow;

  /// What this makes when it is activated. `null` for silence.
  ///
  /// Every selectable thing sounds the same by default, which is the point of
  /// there being one of these. The exception so far is the section row along
  /// the top, where changing section is a different event from picking a card
  /// and the set has a different sound for it.
  final SfxCue? cue;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable>
    with SingleTickerProviderStateMixin {
  /// Every way a remote or a keyboard says "this one".
  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };

  /// What a television remote has spare for a second action.
  static final _secondaryKeys = {
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.gameButtonY,
    LogicalKeyboardKey.contextMenu,
  };

  late FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;

  /// The cursor is over this one.
  ///
  /// Only ever true where hovering does *not* move focus. On a box it would be
  /// the same thing as [_focused] a moment later, so it is not tracked there
  /// and costs that machine nothing.
  bool _hovered = false;

  /// Runs only while this tile has focus. One tile is focused at a time, so
  /// the box is never animating a screenful of rails at once.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _pulse.dispose();
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Focusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != null && widget.focusNode != _node) {
      _node = widget.focusNode!;
    }
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused && widget.glow && context.focusGlow) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
    widget.onFocusChange?.call(focused);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_selectKeys.contains(event.logicalKey)) {
      // A key *repeat* is a held-down OK, not a second press. Selecting twice
      // is the screen's problem to be idempotent about; clicking twice would
      // be a stutter nobody asked for.
      if (event is KeyDownEvent) widget.cue?.play();
      widget.onSelect();
      return KeyEventResult.handled;
    }
    final secondary = widget.onSecondary;
    if (secondary != null && _secondaryKeys.contains(event.logicalKey)) {
      secondary();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ??
        BorderRadius.circular(context.px(Nocturne.radius));

    final tile = Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: AnimatedScale(
        scale: _focused ? widget.scaleOnFocus : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          // Two things move the ring: the pulse, and whether anybody has
          // started steering with the keyboard at all.
          animation: Listenable.merge([_pulse, Dpad.used]),
          child: ClipRRect(borderRadius: radius, child: widget.child),
          builder: (context, child) {
            // Eased rather than linear, so the glow lingers at the top and
            // bottom of its travel instead of sawing between them.
            final breath = _focused
                ? Curves.easeInOut.transform(_pulse.value)
                : 0.0;

            // Focus exists from the first frame — something has to be ringed
            // for OK to mean anything, and `autofocus` puts it there. But on a
            // machine somebody is driving with a mouse, drawing that ring
            // before they have touched an arrow key highlights a choice they
            // did not make. So the ring waits for the first arrow; the focus
            // underneath it does not. Same idea as `:focus-visible`.
            final ringed = _focused && Dpad.used.value;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  // Three states, and they must not be confusable. Focus is
                  // the accent at full strength and breathes; hover is the
                  // same colour held back, so a cursor resting on something
                  // says "this is a thing you can press" without claiming to
                  // be where the remote is.
                  color: ringed
                      ? Color.lerp(context.accent, context.accentSoft, breath)!
                      : _hovered
                      ? context.accent.withValues(alpha: 0.45)
                      : Colors.transparent,
                  width: context.px(2),
                ),
                boxShadow: [
                  if (ringed && widget.glow && context.focusGlow)
                    BoxShadow(
                      color: context.accent.withValues(
                        alpha: 0.22 + 0.20 * breath,
                      ),
                      blurRadius: context.px(18 + 18 * breath),
                      spreadRadius: context.px(breath),
                    ),
                ],
              ),
              child: child,
            );
          },
        ),
      ),
    );

    // Only wrapped when something can actually produce a pointer. An air mouse
    // does; a remote without a gyroscope never will, and then these handlers
    // are dead weight on every tile on screen — and a stray pointer event
    // would pull focus out from under somebody's thumb.
    if (!context.pointer) return tile;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Hovering moves focus only on a box, where the pointer is an air mouse:
      // there the ring following the cursor is the whole point, because the
      // thing in your hand is still a remote and OK still acts on the ring.
      //
      // In a browser it is a real mouse, and a ring that chases it repaints the
      // screen on every idle movement — you click what you are pointing at, and
      // the pointer is already the cursor. Clicking still moves focus, below.
      onEnter: (_) {
        if (platformBox.present) {
          _node.requestFocus();
        } else {
          setState(() => _hovered = true);
        }
      },
      onExit: platformBox.present
          ? null
          : (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.cue?.play();
          _node.requestFocus();
          widget.onSelect();
        },
        child: tile,
      ),
    );
  }
}

/// Scrolls [context]'s tile into view when it takes focus, with room either
/// side so the next one is visibly there.
void revealOnFocus(BuildContext context, {double alignment = 0.1}) {
  final object = context.findRenderObject();
  if (object == null) return;
  Scrollable.ensureVisible(
    context,
    alignment: alignment,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}
