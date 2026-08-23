import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/keypad.dart';
import '../core/remote/focus_area.dart';
import '../data/settings_store.dart';
import '../platform/box_for_platform.dart';
import '../theme/nocturne.dart';
import 'chip_row.dart';
import 'dpad_keyboard.dart';
import 't9_keypad.dart';

/// Whichever way of typing is switched on, and the switch itself.
///
/// The two are one widget so that both screens that collect text get the same
/// pair and the same switch, and so that neither has to know there are two.
/// The choice is a setting rather than a per-screen toggle: somebody who
/// prefers the number keys prefers them everywhere, and having to say so again
/// on the next screen is the sort of thing that makes a preference not worth
/// having.
///
/// **Nothing here is drawn where a real keyboard exists**, switch included.
/// See `DpadKeyboard`: in a browser both of these stand in for keys already
/// under somebody's fingers, and a switch between two pictures of a keyboard
/// is a setting for a problem that machine does not have.
class TypingPad extends StatelessWidget {
  const TypingPad({
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    this.layout = KeyboardLayout.words,
    super.key,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Which grid, when the grid is the one being shown.
  ///
  /// An address gets the grid whatever the setting says: a hostname is Latin
  /// with punctuation in it, and multi-tap over an alphabet that cannot spell
  /// `:` or `/` would be a worse way to type the one thing it cannot type.
  final KeyboardLayout layout;

  @override
  Widget build(BuildContext context) {
    if (!platformBox.present) return const SizedBox.shrink();

    final store = context.read<SettingsStore>();
    final mode = layout == KeyboardLayout.address
        ? TypingMode.keyboard
        : store.value.typingMode;

    // The row of modes and the grid under it are two areas in a column, so
    // stepping between them is the same move as stepping between two rows of
    // keys.
    return FocusArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (layout != KeyboardLayout.address) ...[
            TvChipRow(
              itemCount: TypingMode.values.length,
              builder: (context, index) {
                final option = TypingMode.values[index];
                return TvChip(
                  label: option.title,
                  hint: option.note,
                  selected: option == mode,
                  onSelect: () => store.setTypingMode(option),
                );
              },
            ),
            SizedBox(height: context.px(20)),
          ],
          switch (mode) {
            TypingMode.keyboard => DpadKeyboard(
              onKey: onKey,
              onBackspace: onBackspace,
              onClear: onClear,
              layout: layout,
            ),
            TypingMode.keypad => T9Keypad(
              onKey: onKey,
              onBackspace: onBackspace,
              onClear: onClear,
            ),
          },
        ],
      ),
    );
  }
}
