import 'dart:async';

import 'package:flutter/material.dart';

import '../core/keypad.dart';
import '../core/remote/focus_area.dart';
import '../core/sfx.dart';
import '../platform/box_for_platform.dart';
import '../theme/nocturne.dart';
import 'focusable.dart';
import 'hardware_typing.dart';

/// The twelve keys of a telephone, typed with the remote's own number pad.
///
/// A remote has 0–9 under the thumb already, and multi-tap is the gesture a
/// telephone taught everybody: 4 three times is `Ї`. The grid needs eleven
/// arrow presses to walk to the same letter, and that — not novelty — is why
/// this stands beside it.
///
/// **A digit has to type wherever the ring is sitting** — on a key, on the
/// results beside them, or on nothing at all. It used to get that by watching
/// `HardwareKeyboard`, which sees a press before the focus tree divides it up:
/// so a mounted keypad swallowed every digit in the app, on every screen above
/// it in the stack. It asks the `HardwareTyping` above it instead, which is
/// the same widget that would otherwise put a literal `4` into the query — one
/// place, and the claim ends when this leaves the tree.
///
/// The keys are drawn to be read as much as pressed: which letters live under
/// which digit is the one thing nobody remembers, and on an unfamiliar
/// alphabet nobody ever knew.
class T9Keypad extends StatefulWidget {
  const T9Keypad({
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    super.key,
  });

  /// One character, already upper-cased — the same callback the grid feeds.
  final ValueChanged<String> onKey;

  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  State<T9Keypad> createState() => _T9KeypadState();
}

class _T9KeypadState extends State<T9Keypad> {
  /// 1 and 0 carry no letters on a telephone and carry none in the index
  /// either. What 1 carries here is the punctuation a Ukrainian title actually
  /// contains — `Об'єднані`, `Джентльмени-невдахи`.
  static const _punctuation = "'-.";

  /// How long a key stays "the one being cycled".
  ///
  /// A telephone waited about a second. Shorter and `АА` is impossible to
  /// type; longer and every double letter is a pause somebody has to sit
  /// through.
  static const _settleFor = Duration(milliseconds: 900);

  Keypad _keypad = Keypad.ukrainian;

  /// The typing this keypad borrows the number keys from.
  DigitSink? _typing;

  /// Held rather than torn off at each use, so the claim and the release name
  /// the same object.
  late final void Function(String) _onDigit = _typed;

  /// A digit off a real keyboard or the remote's own number row.
  void _typed(String digit) {
    SfxCue.tap.play();
    _press(digit);
  }

  /// The digit being cycled, and how far through its letters. `null` between
  /// letters — the next press of any key starts a new one.
  String? _cycling;
  int _at = 0;
  Timer? _settle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final typing = HardwareTyping.of(context);
    if (identical(typing, _typing)) return;
    _typing?.releaseDigits(_onDigit);
    _typing = typing;
    typing?.claimDigits(_onDigit);
  }

  @override
  void dispose() {
    _typing?.releaseDigits(_onDigit);
    _settle?.cancel();
    super.dispose();
  }

  /// What a digit does, whichever way it was pressed.
  void _press(String digit) {
    if (digit == '0') return _insert(' ');

    final letters = digit == '1' ? _punctuation : _keypad.lettersFor(digit);
    if (letters.isEmpty) return;

    if (_cycling == digit) {
      // Round again from the same key: what is already in the query is the
      // previous letter of this very press, so it goes back out.
      widget.onBackspace();
      setState(() => _at = (_at + 1) % letters.length);
    } else {
      setState(() {
        _cycling = digit;
        _at = 0;
      });
    }
    widget.onKey(letters[_at]);
    _restartSettle();
  }

  /// A character that is not part of any cycle — a space, or the grid's own.
  void _insert(String character) {
    _stopCycling();
    widget.onKey(character);
  }

  void _restartSettle() {
    _settle?.cancel();
    _settle = Timer(_settleFor, () {
      if (mounted) setState(() => _cycling = null);
    });
  }

  void _stopCycling() {
    _settle?.cancel();
    if (_cycling != null) setState(() => _cycling = null);
  }

  void _backspace() {
    _stopCycling();
    widget.onBackspace();
  }

  void _clear() {
    _stopCycling();
    widget.onClear();
  }

  /// Latin or Ukrainian. One key rather than a menu, because a telephone did
  /// it with one key and because half the catalogue is titled in each.
  void _switchAlphabet() {
    _stopCycling();
    setState(() => _keypad = _keypad.other);
  }

  @override
  Widget build(BuildContext context) {
    // Same rule as the grid, and the same reason: where there is a real
    // keyboard this is a picture of one, and typing already works without it.
    if (!platformBox.present) return const SizedBox.shrink();

    final gap = SizedBox(width: context.px(10));

    Widget row(List<Widget> keys) => Padding(
      padding: EdgeInsets.only(bottom: context.px(10)),
      child: FocusArea(
        flow: Axis.horizontal,
        child: Row(
          children: [
            for (final key in keys) ...[key, if (key != keys.last) gap],
          ],
        ),
      ),
    );

    Widget digit(String value, {bool preferred = false}) {
      final letters = value == '1'
          ? _punctuation
          : value == '0'
          ? ''
          : _keypad.lettersFor(value);
      return _PadKey(
        digit: value,
        letters: value == '0' ? '␣' : letters,
        // Only the key mid-cycle points at a letter, and only then does
        // anybody need to know which press they are on.
        at: _cycling == value ? _at : null,
        preferred: preferred,
        onSelect: () => _press(value),
      );
    }

    return FocusArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          row([digit('1'), digit('2', preferred: true), digit('3')]),
          row([digit('4'), digit('5'), digit('6')]),
          row([digit('7'), digit('8'), digit('9')]),
          row([
            _PadKey(
              digit: _keypad.other.title,
              letters: 'мова',
              small: true,
              onSelect: _switchAlphabet,
            ),
            digit('0'),
            _PadKey(
              digit: '⌫',
              letters: 'стерти',
              small: true,
              onSelect: _backspace,
            ),
          ]),
          _PadKey(
            digit: 'Очистити',
            letters: '',
            small: true,
            width: 620,
            onSelect: _clear,
          ),
        ],
      ),
    );
  }
}

class _PadKey extends StatefulWidget {
  const _PadKey({
    required this.digit,
    required this.letters,
    required this.onSelect,
    this.at,
    this.preferred = false,
    this.small = false,
    this.width = 200,
  });

  final String digit;
  final String letters;
  final VoidCallback onSelect;

  /// Which of [letters] the next press would replace, or `null` when this key
  /// is not the one being cycled.
  final int? at;

  final bool preferred;

  /// A key whose label is a word rather than a digit, and so is set in the
  /// size a word can be read at.
  final bool small;

  final double width;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final live = widget.at != null;

    return Focusable(
      preferred: widget.preferred,
      onSelect: widget.onSelect,
      // Keys must not grow: a shifting key is one you press by mistake.
      scaleOnFocus: 1,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: context.px(widget.width),
        height: context.px(76),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _focused || live ? context.accentTint : context.surface,
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.digit,
              style: TextStyle(
                fontSize: context.sp(widget.small ? 19 : 26),
                fontWeight: FontWeight.w600,
                color: _focused || live
                    ? context.accentText
                    : Nocturne.neutral300,
              ),
            ),
            if (widget.letters.isNotEmpty) ...[
              SizedBox(width: context.px(10)),
              // Letter by letter rather than one string, so the one the next
              // press would land on can be picked out of it.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < widget.letters.length; index++)
                    Text(
                      widget.letters[index],
                      style: TextStyle(
                        fontSize: context.sp(16),
                        letterSpacing: context.px(1),
                        color: widget.at == index
                            ? context.accent
                            : _focused
                            ? context.accentText
                            : Nocturne.neutral500,
                        fontWeight: widget.at == index
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
