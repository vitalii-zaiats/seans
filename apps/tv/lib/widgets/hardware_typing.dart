import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/box_for_platform.dart';

/// Lets a real keyboard type into a screen built for a remote.
///
/// Every text screen here collects characters from an on-screen grid, because
/// that is what a D-pad can drive. There is no `TextField` anywhere and so
/// nothing that a USB or Bluetooth keyboard could type into — the arrows and
/// OK worked, and letters did nothing at all.
///
/// This listens for the keys the grid cannot produce and hands them to the same
/// callbacks the grid uses, so both ways of typing end up in one place. It
/// deliberately does not swallow the keys the interface needs: arrows, OK and
/// BACK pass straight through to focus traversal.
///
/// There is no `onSubmit`. Key events travel from the focused node outwards,
/// so whatever has focus sees Enter first and takes it — a wrapper this far
/// out cannot have it, and an option that quietly never fires is worse than
/// no option.
class HardwareTyping extends StatelessWidget {
  const HardwareTyping({
    required this.onCharacter,
    required this.onBackspace,
    required this.child,
    this.onClear,
    super.key,
  });

  /// One printable character, already upper-cased to match the grid.
  final ValueChanged<String> onCharacter;

  final VoidCallback onBackspace;

  /// Escape, when the screen has a clear.
  final VoidCallback? onClear;

  final Widget child;

  /// Keys that carry a character but are the interface's, not the text's.
  static final _reserved = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.tab,
  };

  @override
  Widget build(BuildContext context) {
    // Key events travel from the focused node *outwards*, so this only ever
    // sees a letter because something below it holds focus — and on a box that
    // something is the first key of the grid, which autofocuses.
    //
    // Where the grid is not drawn there is nothing below to hold it, and this
    // would sit watching a stream that never arrives. So it takes focus itself
    // exactly there: on a machine with a keyboard, which is the same machine
    // that has no remote whose focus it could be stealing.
    final holdsFocus = !platformBox.present;

    return Focus(
      canRequestFocus: holdsFocus,
      autofocus: holdsFocus,
      // Never a stop on the way round: arrows still walk past it to the
      // results, whether or not it started with focus.
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.backspace) {
          onBackspace();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape && onClear != null) {
          onClear!();
          return KeyEventResult.handled;
        }
        if (_reserved.contains(key)) return KeyEventResult.ignored;

        // A modifier held means a shortcut, not typing — Ctrl+V is not a `v`.
        if (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.ignored;
        }

        final character = event.character;
        if (character == null || character.length != 1) {
          return KeyEventResult.ignored;
        }
        // Control characters arrive with a character too; only things that can
        // be drawn belong in a query.
        if (character.codeUnitAt(0) < 0x20) return KeyEventResult.ignored;

        onCharacter(character.toUpperCase());
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
