import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets a real keyboard type into a screen built for a remote.
///
/// Every text screen here collects characters from an on-screen grid, because
/// that is what a D-pad can drive. There is no `TextField` anywhere and so
/// nothing that a USB or Bluetooth keyboard could type into — the arrows and
/// OK worked, and letters did nothing at all.
///
/// This listens for the keys the grid cannot produce and hands them to the same
/// callbacks the grid uses, so both ways of typing end up in one place. It
/// deliberately does not swallow the keys the interface needs: arrows and OK
/// pass straight through to the arbiter and to whatever holds focus.
///
/// **A pure ancestor: it never takes focus itself.** Key events travel from the
/// focused node outwards, so this only sees a letter because something below
/// it holds focus — and something always does now, because the screen's area
/// anchors focus even where nothing is focusable. It used to take focus itself
/// wherever there was no on-screen grid, and a full-screen node with no
/// candidates beyond its edge in any direction is a screen where no arrow
/// moves anything: in a browser, search was exactly that.
///
/// There is no `onSubmit`. Key events travel outwards, so whatever has focus
/// sees Enter first and takes it — a wrapper this far out cannot have it, and
/// an option that quietly never fires is worse than no option.
class HardwareTyping extends StatefulWidget {
  const HardwareTyping({
    required this.onCharacter,
    required this.onBackspace,
    required this.child,
    super.key,
  });

  /// One printable character, already upper-cased to match the grid.
  final ValueChanged<String> onCharacter;

  /// Backspace, while somebody is typing. Not a contradiction with "⌫ means
  /// back" elsewhere: the focus tree already says whose key it is, and while
  /// there is text under the cursor it is the text's.
  final VoidCallback onBackspace;

  final Widget child;

  /// Keys that carry a character but are the interface's, not the text's.
  static final _reserved = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.tab,
  };

  /// The typing above [context], for a keypad that wants the number keys.
  static DigitSink? of(BuildContext context) =>
      context.findAncestorStateOfType<_HardwareTypingState>();

  @override
  State<HardwareTyping> createState() => _HardwareTypingState();
}

class _HardwareTypingState extends State<HardwareTyping> implements DigitSink {
  /// Set while a keypad below is drawn. Read at the moment of the press, so
  /// nothing here rebuilds when it changes.
  ValueChanged<String>? _digits;

  @override
  void claimDigits(ValueChanged<String> onDigit) => _digits = onDigit;

  @override
  void releaseDigits(ValueChanged<String> onDigit) {
    if (identical(_digits, onDigit)) _digits = null;
  }

  /// Every way a remote or a keyboard spells a digit.
  static String? _digitOf(LogicalKeyboardKey key) {
    for (var digit = 0; digit <= 9; digit++) {
      if (key == _rowKeys[digit] || key == _numpadKeys[digit]) return '$digit';
    }
    return null;
  }

  static final _rowKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  static final _numpadKeys = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    if (HardwareTyping._reserved.contains(key)) return KeyEventResult.ignored;

    // A modifier held means a shortcut, not typing — Ctrl+V is not a `v`.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final digits = _digits;
    if (digits != null) {
      final digit = _digitOf(key);
      if (digit != null) {
        // A held-down 4 is not four presses of it: a repeat would cycle the
        // letter under somebody's thumb faster than they could read it.
        if (event is KeyDownEvent) digits(digit);
        return KeyEventResult.handled;
      }
    }

    final character = event.character;
    if (character == null || character.length != 1) {
      return KeyEventResult.ignored;
    }
    // Control characters arrive with a character too; only things that can
    // be drawn belong in a query.
    if (character.codeUnitAt(0) < 0x20) return KeyEventResult.ignored;

    widget.onCharacter(character.toUpperCase());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      // Never a stop on the way round: the arrows walk straight past it.
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}

/// Who the number keys belong to while a telephone keypad is on screen.
///
/// The keypad used to take them from `HardwareKeyboard`, where a press is seen
/// before the focus tree divides it up — so a mounted keypad ate every digit
/// in the app, and "is the keypad drawn" was a platform condition written down
/// in two places that could disagree. Here the claim lives in the focus tree,
/// where "while I am on screen" already means something.
abstract interface class DigitSink {
  void claimDigits(ValueChanged<String> onDigit);
  void releaseDigits(ValueChanged<String> onDigit);
}
