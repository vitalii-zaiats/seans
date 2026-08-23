import 'package:flutter/material.dart';

import '../platform/box_for_platform.dart';
import '../theme/nocturne.dart';
import 'focusable.dart';

/// What a keyboard is for.
enum KeyboardLayout {
  /// Ukrainian, then Latin and digits — for a title somebody is searching for.
  words(DpadKeyboard._rows),

  /// Lower-case Latin, digits and the punctuation an address is made of. No
  /// Cyrillic: a hostname cannot contain it, and offering it would only mean
  /// walking past three rows to reach the dot.
  address(['abcdefghij', 'klmnopqrst', 'uvwxyz0123', '456789.:-_', '/@?=&+~%']);

  const KeyboardLayout(this.rows);

  final List<String> rows;
}

/// The on-screen keyboard, walked with the D-pad.
///
/// Ukrainian first, then Latin and digits — a television has no keyboard, and
/// the catalogue is Ukrainian, so that is the row somebody reaches for.
///
/// **Draws nothing where a real keyboard exists.** In a browser or on a desktop
/// this grid is seventy buttons standing in for a key somebody already has
/// under their fingers, and it takes half the screen to do it. Typing still
/// works there and always did: `HardwareTyping` wraps both screens that use
/// this and feeds real key presses into the very same callbacks, so hiding the
/// grid removes a picture of a keyboard rather than the ability to type.
class DpadKeyboard extends StatelessWidget {
  const DpadKeyboard({
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    this.layout = KeyboardLayout.words,
    super.key,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Which set of keys to draw. An address needs `:` and `/`, and a title
  /// never does — putting both on one keyboard would make the common case walk
  /// past the rare one.
  final KeyboardLayout layout;

  static const _rows = [
    'АБВГҐДЕЄЖЗ',
    'ИІЇЙКЛМНОП',
    'РСТУФХЦЧШЩ',
    'ЬЮЯ0123456',
    '789ABCDEFG',
    'HIJKLMNOPQ',
    'RSTUVWXYZ',
  ];

  @override
  Widget build(BuildContext context) {
    // See the class docstring: a machine with a keyboard gets none of this.
    if (!platformBox.present) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in layout.rows) ...[
          Row(
            children: [
              for (final character in row.split('')) ...[
                _Key(
                  label: character,
                  onSelect: () => onKey(character),
                  autofocus: character == 'А',
                ),
                SizedBox(width: context.px(8)),
              ],
            ],
          ),
          SizedBox(height: context.px(8)),
        ],
        Row(
          children: [
            _Key(label: 'Пробіл', width: 200, onSelect: () => onKey(' ')),
            SizedBox(width: context.px(8)),
            _Key(label: '⌫', width: 96, onSelect: onBackspace),
            SizedBox(width: context.px(8)),
            _Key(label: 'Очистити', width: 160, onSelect: onClear),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onSelect,
    this.width = 56,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final double width;
  final bool autofocus;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: widget.autofocus,
      onSelect: widget.onSelect,
      // Keys must not grow: a shifting key is one you press by mistake.
      scaleOnFocus: 1,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        width: context.px(widget.width),
        height: context.px(56),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _focused ? context.accentTint : context.surface,
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: context.sp(19),
            color: _focused ? context.accentText : Nocturne.neutral300,
          ),
        ),
      ),
    );
  }
}
